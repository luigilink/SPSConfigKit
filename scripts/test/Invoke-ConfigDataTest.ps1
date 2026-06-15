<#
.SYNOPSIS
  Driver that runs the ConfigData.Tests.ps1 Pester suite against a given
  SPSConfigKit ConfigurationData (.psd1) file.

.DESCRIPTION
  Wraps Invoke-Pester so callers don't have to remember the New-PesterContainer
  / -Data plumbing. Exits with code 0 on success, 1 if any test fails — handy
  for a pre-MOF gate in CI or a release script.

.PARAMETER ConfigPath
  Path to the ConfigurationData .psd1 to validate (e.g. .\scripts\sps\CfgAppSps.psd1).

.PARAMETER SecretsPath
  Path to the companion Secrets.psd1. When omitted, defaults to
  <repo>\scripts\Secrets.psd1 (i.e. the sibling Secrets.psd1 two folders above
  the config file).

.PARAMETER SkipFilesystem
  Skip the share/cert/setup.exe reachability tests. Useful from a workstation
  that doesn't have the install share mounted, or for quick syntax-only checks.

.PARAMETER Output
  Pester output verbosity. One of None, Normal, Detailed, Diagnostic. Default:
  Detailed (one line per It block, with reason for any failure).

.EXAMPLE
  PS> .\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sps\CfgAppSps.psd1

.EXAMPLE
  PS> .\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sql\CfgAppSql.psd1 -SkipFilesystem
#>

#Requires -Version 5.1

[CmdletBinding()]
param
(
  [Parameter(Mandatory = $true)]
  [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
  [string] $ConfigPath,

  [Parameter(Mandatory = $false)]
  [string] $SecretsPath,

  [Parameter(Mandatory = $false)]
  [switch] $SkipFilesystem,

  [Parameter(Mandatory = $false)]
  [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
  [string] $Output = 'Detailed'
)

# Ensure Pester v5 is available (PS5.1 ships with Pester 3.x).
$pester = Get-Module -ListAvailable -Name Pester |
  Where-Object { $_.Version -ge [version]'5.0.0' } |
  Sort-Object Version -Descending |
  Select-Object -First 1

if (-not $pester) {
  throw @'
Pester 5.0.0 or later is required. Install with:
    Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
'@
}
Import-Module Pester -MinimumVersion 5.0.0 -ErrorAction Stop

# Resolve absolute paths so the test suite is invariant to caller's $PWD.
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
if ($SecretsPath) {
  $SecretsPath = (Resolve-Path -LiteralPath $SecretsPath).Path
}
else {
  # Default: <repo>\scripts\Secrets.psd1 — sibling of the product sub-folder.
  $SecretsPath = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $ConfigPath)) -ChildPath 'Secrets.psd1'
}

$testsPath = Join-Path -Path $PSScriptRoot -ChildPath 'ConfigData.Tests.ps1'
if (-not (Test-Path -LiteralPath $testsPath)) {
  throw "Test file not found: $testsPath"
}

$container = New-PesterContainer -Path $testsPath -Data @{
  ConfigPath     = $ConfigPath
  SecretsPath    = $SecretsPath
  SkipFilesystem = [bool]$SkipFilesystem
}

$config = New-PesterConfiguration
$config.Run.Container = $container
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output

Write-Host ''
Write-Host ("Validating ConfigurationData : {0}" -f $ConfigPath) -ForegroundColor Cyan
Write-Host ("Cross-referencing Secrets    : {0}" -f $SecretsPath) -ForegroundColor Cyan
Write-Host ("Filesystem checks            : {0}" -f $(if ($SkipFilesystem) { 'SKIPPED' } else { 'enabled' })) -ForegroundColor Cyan
Write-Host ''

$result = Invoke-Pester -Configuration $config

# Pester v5 exposes counts on the run result. SkippedCount covers It blocks
# that were gated off (e.g. SPS/OOS/ADC sections that don't apply to a
# SQL-only config); we surface it so a clean run doesn't look misleadingly
# "all green" when most blocks never executed.
$passed  = [int]$result.PassedCount
$failed  = [int]$result.FailedCount
$skipped = [int]$result.SkippedCount
$total   = $passed + $failed + $skipped

if ($failed -gt 0) {
  Write-Host ''
  Write-Host ("{0} test(s) failed ({1} passed, {2} skipped, {3} total). Fix the .psd1 before compiling MOFs." -f `
      $failed, $passed, $skipped, $total) -ForegroundColor Red
  exit 1
}

Write-Host ''
if ($skipped -gt 0) {
  Write-Host ("{0} of {1} test(s) passed; {2} skipped (sections not present in this config or filesystem checks disabled). ConfigurationData looks healthy." -f `
      $passed, $total, $skipped) -ForegroundColor Green
}
else {
  Write-Host ("All {0} test(s) passed. ConfigurationData looks healthy." -f $passed) -ForegroundColor Green
}
exit 0
