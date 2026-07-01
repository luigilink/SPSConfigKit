<#
.SYNOPSIS
  Driver that runs the MofEncryption.Tests.ps1 Pester suite against compiled MOF
  files, failing if any credential was compiled in clear text.

.DESCRIPTION
  Wraps Invoke-Pester so callers don't have to remember the New-PesterContainer
  plumbing. Exits with code 0 when every MOF is encrypted, 1 if any clear-text
  credential is found — handy as a post-compile gate in CI or a release script,
  right after CfgApp*.ps1 writes the MOFs.

.PARAMETER MofPath
  Path to a compiled .mof file, or a folder containing them (e.g. .\scripts\sps\MOF).
  *.meta.mof files are ignored.

.PARAMETER Output
  Pester output verbosity. One of None, Normal, Detailed, Diagnostic. Default:
  Detailed.

.EXAMPLE
  PS> .\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF

.EXAMPLE
  PS> .\scripts\sps\CfgAppSps.ps1
  PS> .\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF
#>

#Requires -Version 5.1

[CmdletBinding()]
param
(
  [Parameter(Mandatory = $true)]
  [ValidateScript({ Test-Path -LiteralPath $_ })]
  [string] $MofPath,

  [Parameter(Mandatory = $false)]
  [ValidateSet('None', 'Normal', 'Detailed', 'Diagnostic')]
  [string] $Output = 'Detailed'
)

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

$MofPath = (Resolve-Path -LiteralPath $MofPath).Path

$testsPath = Join-Path -Path $PSScriptRoot -ChildPath 'MofEncryption.Tests.ps1'
if (-not (Test-Path -LiteralPath $testsPath)) {
  throw "Test file not found: $testsPath"
}

$container = New-PesterContainer -Path $testsPath -Data @{ MofPath = $MofPath }

$config = New-PesterConfiguration
$config.Run.Container = $container
$config.Run.PassThru = $true
$config.Output.Verbosity = $Output

Write-Host ''
Write-Host ("Verifying MOF encryption : {0}" -f $MofPath) -ForegroundColor Cyan
Write-Host ''

$result = Invoke-Pester -Configuration $config

$passed = [int]$result.PassedCount
$failed = [int]$result.FailedCount
$skipped = [int]$result.SkippedCount
$total = $passed + $failed + $skipped

if ($failed -gt 0) {
  Write-Host ''
  Write-Host ("{0} check(s) failed ({1} passed, {2} skipped, {3} total). CLEAR-TEXT CREDENTIALS DETECTED — do NOT ship these MOFs. Run Initialize-DscEncryption.ps1 and recompile." -f `
      $failed, $passed, $skipped, $total) -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host ("All {0} check(s) passed. Every credential in the MOF(s) is encrypted." -f $passed) -ForegroundColor Green
exit 0
