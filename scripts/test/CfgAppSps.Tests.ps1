<#
.SYNOPSIS
  Static regression guard for scripts/sps/CfgAppSps.ps1: the SPFarm resources must never pass
  an empty DatabaseServerCertificateHostName to SharePointDsc's MSFT_SPFarm.

.DESCRIPTION
  MSFT_SPFarm decorates DatabaseServerCertificateHostName with [ValidateNotNullOrEmpty()].
  CfgAppSps resolves the host name to an empty string when
  NonNodeData.SQL.DatabaseServerCertificateHostName is not configured - the case for the
  default 'Optional' connection-encryption level. Passing that empty string to the SPFarm
  resource fails when the configuration is applied with:

      Cannot validate argument on parameter 'DatabaseServerCertificateHostName' because it is
      an empty string.

  (issue #51). DSC resource keywords cannot be splatted, so each SPFarm block
  (APPLICATION_SpsCreateSPFarm and APPLICATION_SpsJoinSPFarm) is emitted in an if/else guarded
  by [string]::IsNullOrWhiteSpace($sqlDbCertHostName): the property is included only in the
  branch where a host name was supplied, and omitted entirely otherwise.

  These checks are pure text analysis of the shipped configuration script, so they run on any
  platform (no SharePoint modules and no MOF compilation required) and guard against the bug
  being reintroduced.

.NOTES
  Requires Pester 5.0 or later.
#>

#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
  $script:ConfigScript = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'sps/CfgAppSps.ps1'
  if (-not (Test-Path -LiteralPath $script:ConfigScript)) {
    throw "CfgAppSps.ps1 not found at $script:ConfigScript"
  }
  $script:Lines = Get-Content -LiteralPath $script:ConfigScript
  $script:Text = $script:Lines -join "`n"
}

Describe 'CfgAppSps SPFarm DatabaseServerCertificateHostName (issue #51)' {
  It 'guards each SPFarm block with an IsNullOrWhiteSpace check on the host name' {
    # Each SPFarm resource (create + join) is wrapped in an if/else keyed on the host name so
    # the property is only emitted when a host name is configured. Exactly two such guards.
    $guards = @($script:Lines | Where-Object { $_ -match 'if \(\[string\]::IsNullOrWhiteSpace\(\$sqlDbCertHostName\)\)' })
    $guards.Count | Should -Be 2 -Because (
      'both SPFarm blocks (APPLICATION_SpsCreateSPFarm and APPLICATION_SpsJoinSPFarm) must be ' +
      'emitted conditionally so DatabaseServerCertificateHostName is omitted when empty (issue #51)'
    )
  }

  It 'only ever assigns DatabaseServerCertificateHostName from the resolved host-name variable' {
    # The property may appear only as `DatabaseServerCertificateHostName = $sqlDbCertHostName`
    # (inside the guarded else branch), never as a literal empty string.
    $assignments = @($script:Lines | Where-Object { $_ -match 'DatabaseServerCertificateHostName\s*=' })
    $assignments.Count | Should -Be 2 -Because 'the property is set once in each SPFarm else branch'
    $badLiteral = @($assignments | Where-Object { $_ -match "DatabaseServerCertificateHostName\s*=\s*(''|\`"\`"|'\s*'|\`"\s*\`")" })
    $badLiteral.Count | Should -Be 0 -Because 'an empty-string literal must never be assigned to the property'
    $fromVar = @($assignments | Where-Object { $_ -match 'DatabaseServerCertificateHostName\s*=\s*\$sqlDbCertHostName\b' })
    $fromVar.Count | Should -Be 2 -Because 'every assignment must come from the resolved $sqlDbCertHostName variable'
  }

  It 'still fails fast when Mandatory/Strict is requested without a host name' {
    # The pre-existing safety net must remain: Mandatory/Strict validate the certificate host
    # name, so they still require a non-empty DatabaseServerCertificateHostName.
    $needle = [regex]::Escape('requires NonNodeData.SQL.DatabaseServerCertificateHostName to be set')
    $script:Text | Should -Match $needle -Because (
      'raising the encryption level to Mandatory/Strict must still throw when no ' +
      'DatabaseServerCertificateHostName is configured'
    )
  }
}
