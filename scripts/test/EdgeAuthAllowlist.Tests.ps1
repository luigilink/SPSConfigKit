<#
.SYNOPSIS
  Static regression guard for the optional Edge AuthServerAllowlist registry key in
  scripts/sps/CfgAppSps.ps1 (issue #55).

.DESCRIPTION
  HKLM\SOFTWARE\Policies\Microsoft\Edge\AuthServerAllowlist is a browser Integrated Windows
  Auth policy, normally owned centrally by GPO / Intune. The kit used to write it
  unconditionally on every SharePoint node, with a hardcoded '*app1*' host pattern. It is now
  opt-in through NonNodeData.SharePoint.EdgeAuthAllowlist:
    * omitted / Enabled not set -> the Registry resource is not emitted (GPO stays authoritative);
    * Enabled = $true           -> the key is written, Hosts (or *<DomainName>* by default),
                                   with Force = $true so an existing (GPO-set) value is overwritten.

  These checks are pure text analysis of the shipped configuration script, so they run on any
  platform (no SharePoint modules / no MOF compilation) and guard against the hardcoded,
  always-on key being reintroduced.

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

Describe 'CfgAppSps Edge AuthServerAllowlist is optional (issue #55)' {
  It 'no longer hardcodes an app1 host pattern' {
    $bad = @($script:Lines | Where-Object { $_ -match '\*app1\*' })
    $bad.Count | Should -Be 0 -Because 'the *app1* literal was a dev/test leftover and must not ship'
  }

  It 'guards the AuthServerAllowlist registry resource behind EdgeAuthAllowlist.Enabled' {
    # The Registry resource must be emitted only inside an if (...EdgeAuthAllowlist.Enabled) block.
    $script:Text | Should -Match 'if\s*\(\s*\$edgeAuth\s+-and\s+\$edgeAuth\.Enabled\s*\)' -Because (
      'the browser policy key must be opt-in so GPO/Intune stays authoritative by default (issue #55)'
    )
    $script:Text | Should -Match "EdgeAuthAllowlist" -Because 'the opt-in comes from NonNodeData.SharePoint.EdgeAuthAllowlist'
  }

  It 'writes the registry value with Force so an existing (GPO-set) value is overwritten' {
    # Within the AuthServerAllowlist resource block, Force = $true must be present.
    $script:Text | Should -Match "(?s)Registry\s+SYSTEM_SPSAuthServerAllowList\s*\{[^}]*Force\s*=\s*\`$true" -Because (
      'DSC errors when overwriting an existing registry value unless Force is set'
    )
  }

  It 'defaults the host pattern to the domain when no explicit Hosts are given' {
    $script:Text | Should -Match '\*\$\(\$ConfigurationData\.NonNodeData\.DomainName\)\*' -Because (
      'omitting Hosts must fall back to every host in the domain, not a hardcoded server name'
    )
  }

  It 'keeps the completion Log compiling whether or not the registry resource is emitted' {
    # The Log DependsOn must be computed dynamically (variable), not a static reference to a
    # resource that may not exist.
    $script:Text | Should -Match 'DependsOn\s*=\s*\$allNodesCompletedDependsOn' -Because (
      'a static DependsOn on an omitted resource would break MOF compilation'
    )
  }
}
