<#
.SYNOPSIS
  Creates the account-level groups used by the policies and the pipeline service principal.
  Idempotent: anything that already exists is reused.

.DESCRIPTION
  ABAC policies only see ACCOUNT principals (is_account_group_member).
  Groups created through the workspace API are workspace-local and do not work.

  Requires a profile authenticated against the Account Console:
    databricks auth login --host https://accounts.cloud.databricks.com `
      --account-id <account-id> --profile synthea-account

  Not available on Databricks Free Edition (no account API access): create the
  groups in the workspace UI instead (Settings > Identity and access > Groups).

.EXAMPLE
  ./src/scripts/setup_identities.ps1 -WorkspaceId <workspace-id>
  ./src/scripts/setup_identities.ps1 -WorkspaceId <workspace-id> -AddMeTo synthea_pii_readers
#>
param(
    [string]$AccountProfile = "synthea-account",
    [Parameter(Mandatory)][string]$WorkspaceId,
    [string]$PipelineSp = "synthea-pipeline",
    [string[]]$AddMeTo = @()
)
$ErrorActionPreference = "Stop"

$groups = "synthea_pipeline", "synthea_pii_readers", "synthea_analysts", "synthea_sensitive_readers"

# Runs the CLI and fails on a non-zero exit code (native exes ignore $ErrorActionPreference)
function Invoke-Db {
    $out = & databricks @args
    if ($LASTEXITCODE -ne 0) { throw "databricks $($args -join ' ') failed (exit $LASTEXITCODE)" }
    return $out
}

# No --filter: in PowerShell 5.1 the inner quotes of the SCIM filter get lost
$existingGroups = @(Invoke-Db account groups list -p $AccountProfile -o json | ConvertFrom-Json)

function Get-OrCreateGroup([string]$name) {
    $found = $existingGroups | Where-Object { $_.displayName -eq $name } | Select-Object -First 1
    if ($found) { Write-Host "= group $name ($($found.id))"; return $found.id }
    $g = Invoke-Db account groups create --display-name $name -p $AccountProfile -o json | ConvertFrom-Json
    Write-Host "+ group $name ($($g.id))"
    return $g.id
}

function Add-GroupMember([string]$groupId, [string]$memberId) {
    $patch = @{
        schemas    = @("urn:ietf:params:scim:api:messages:2.0:PatchOp")
        Operations = @(@{ op = "add"; path = "members"; value = @(@{ value = $memberId }) })
    } | ConvertTo-Json -Depth 5 -Compress
    $tmp = New-TemporaryFile
    Set-Content $tmp $patch -Encoding ascii   # utf8 in PS 5.1 writes a BOM and breaks --json
    try { Invoke-Db account groups patch $groupId --json "@$tmp" -p $AccountProfile | Out-Null }
    finally { Remove-Item $tmp }
}

$ids = @{}
foreach ($g in $groups) { $ids[$g] = Get-OrCreateGroup $g }

# Pipeline service principal -> synthea_pipeline group + workspace access
$sp = Invoke-Db account service-principals list -p $AccountProfile -o json | ConvertFrom-Json |
    Where-Object { $_.displayName -eq $PipelineSp } | Select-Object -First 1
if (-not $sp) {
    $sp = Invoke-Db account service-principals create --display-name $PipelineSp -p $AccountProfile -o json | ConvertFrom-Json
    Write-Host "+ service principal $PipelineSp ($($sp.applicationId))"
} else { Write-Host "= service principal $PipelineSp ($($sp.applicationId))" }
Add-GroupMember $ids["synthea_pipeline"] $sp.id
$assign = New-TemporaryFile
Set-Content $assign '{"permissions":["USER"]}' -Encoding ascii
try { Invoke-Db account workspace-assignment update $WorkspaceId $sp.id --json "@$assign" -p $AccountProfile | Out-Null }
finally { Remove-Item $assign }
Write-Host "+ $PipelineSp assigned to workspace $WorkspaceId"

foreach ($g in $AddMeTo) {
    $me = Invoke-Db current-user me -p synthea -o json | ConvertFrom-Json
    Add-GroupMember $ids[$g] $me.id
    Write-Host "+ you were added to $g"
}

Write-Host "`nNext step - run the medallion job as the service principal:"
Write-Host "  set run_as.service_principal_name: $($sp.applicationId) in databricks.yml"
