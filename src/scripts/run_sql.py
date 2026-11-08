# /// script
# requires-python = ">=3.11"
# dependencies = ["databricks-sdk>=0.40", "sqlparse>=0.5"]
# ///
"""Runs SQL on a SQL Warehouse using a Databricks CLI profile.

Usage:
    uv run src/scripts/run_sql.py -q "SELECT 1"
    uv run src/scripts/run_sql.py src/transformations/silver/*.sql
    uv run src/scripts/run_sql.py -q "SELECT ..." --json outputs/x.json

Files may contain multiple statements separated by ';'.
Variables: ${catalog} and ${var} are replaced via --var key=value.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
import time
from pathlib import Path

import sqlparse
from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import Disposition, Format, StatementState

DEFAULT_VARS = {"catalog": "synthea"}


def split_statements(sql: str) -> list[str]:
    out = []
    for stmt in sqlparse.split(sql):
        body = sqlparse.format(stmt, strip_comments=True).strip().rstrip(";").strip()
        if body:
            out.append(stmt.strip().rstrip(";"))
    return out


def render(sql: str, variables: dict[str, str]) -> str:
    def sub(m: re.Match) -> str:
        key = m.group(1)
        if key not in variables:
            raise KeyError(f"Undefined variable: ${{{key}}}")
        return variables[key]

    return re.sub(r"\$\{(\w+)\}", sub, sql)


def expand_paths(patterns: list[str]) -> list[Path]:
    """Expands wildcards here: PowerShell/cmd pass `*.sql` through literally (bash expands it first)."""
    out: list[Path] = []
    for p in patterns:
        if any(c in p for c in "*?["):
            matches = sorted(glob.glob(p))
            if not matches:
                sys.exit(f"No files match: {p}")
            out.extend(Path(m) for m in matches)
        else:
            out.append(Path(p))
    return out


def pick_warehouse(w: WorkspaceClient) -> str:
    wid = os.environ.get("DATABRICKS_WAREHOUSE_ID")
    if wid:
        return wid
    whs = list(w.warehouses.list())
    if not whs:
        sys.exit("No SQL Warehouse found.")
    serverless = [x for x in whs if x.enable_serverless_compute]
    return (serverless or whs)[0].id


def execute(w: WorkspaceClient, warehouse_id: str, sql: str):
    resp = w.statement_execution.execute_statement(
        warehouse_id=warehouse_id,
        statement=sql,
        wait_timeout="30s",
        format=Format.JSON_ARRAY,
        disposition=Disposition.INLINE,
    )
    while resp.status.state in (StatementState.PENDING, StatementState.RUNNING):
        time.sleep(2)
        resp = w.statement_execution.get_statement(resp.statement_id)
    if resp.status.state != StatementState.SUCCEEDED:
        err = resp.status.error.message if resp.status.error else resp.status.state
        raise RuntimeError(err)
    cols = [c.name for c in resp.manifest.schema.columns] if resp.manifest and resp.manifest.schema else []
    rows = resp.result.data_array if resp.result and resp.result.data_array else []
    return cols, rows


def print_table(cols: list[str], rows: list[list], limit: int) -> None:
    if not cols:
        return
    shown = rows[:limit]
    data = [["NULL" if v is None else str(v) for v in r] for r in shown]
    widths = [min(60, max([len(c)] + [len(r[i]) for r in data])) for i, c in enumerate(cols)]
    fmt = " | ".join(f"{{:<{wd}}}" for wd in widths)
    print(fmt.format(*cols))
    print("-+-".join("-" * wd for wd in widths))
    for r in data:
        print(fmt.format(*[v[:60] for v in r]))
    if len(rows) > limit:
        print(f"... ({len(rows)} rows, showing {limit})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*", help="SQL files; wildcards like silver/*.sql are expanded in any shell")
    ap.add_argument("-q", "--query")
    ap.add_argument("-p", "--profile", default=os.environ.get("DATABRICKS_PROFILE", "synthea"))
    ap.add_argument("--var", action="append", default=[], help="key=value")
    ap.add_argument("--json", help="saves the last query's result as JSON ('-' = JSON only, to stdout)")
    ap.add_argument("--limit", type=int, default=200)
    ap.add_argument("--continue-on-error", action="store_true")
    args = ap.parse_args()

    variables = dict(DEFAULT_VARS)
    for kv in args.var:
        k, _, v = kv.partition("=")
        variables[k] = v

    # files first, ad hoc query last (handy for validating what the files created)
    sources: list[tuple[str, str]] = [(str(f), f.read_text(encoding="utf-8")) for f in expand_paths(args.files)]
    if args.query:
        sources.append(("<query>", args.query))
    if not sources:
        ap.error("provide -q or .sql files")

    w = WorkspaceClient(profile=args.profile)
    wid = pick_warehouse(w)

    quiet = args.json == "-"
    failures = 0
    last = ([], [])
    for name, text in sources:
        for stmt in split_statements(render(text, variables)):
            preview = " ".join(sqlparse.format(stmt, strip_comments=True).split())[:110]
            if not quiet:
                print(f"\n>> [{name}] {preview}", flush=True)
            try:
                last = execute(w, wid, stmt)
                if not quiet:
                    print_table(*last, limit=args.limit)
            except Exception as e:  # noqa: BLE001
                failures += 1
                print(f"!! ERROR: {e}", file=sys.stderr, flush=True)
                if not args.continue_on_error:
                    sys.exit(1)

    if args.json:
        cols, rows = last
        payload = json.dumps([dict(zip(cols, r)) for r in rows], indent=2, ensure_ascii=False)
        if quiet:
            print(payload)
        else:
            out = Path(args.json)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(payload, encoding="utf-8")
            print(f"\nSaved to {out}")

    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
