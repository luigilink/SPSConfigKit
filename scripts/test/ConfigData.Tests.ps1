<#
.SYNOPSIS
  Pre-flight Pester (v5) test suite that validates a SPSConfigKit ConfigurationData
  .psd1 file against the companion Secrets.psd1 and (optionally) against the file
  system, so structural mistakes are caught BEFORE compiling MOFs or running
  Start-DscConfiguration.

.DESCRIPTION
  Designed to be invoked through scripts/test/Invoke-ConfigDataTest.ps1, which
  builds a Pester container with -Data @{ ConfigPath = ...; SecretsPath = ...;
  SkipFilesystem = ... }. The same suite handles SPS, OOS, SQL and PDC/PULL
  configurations: sections only run when the relevant NonNodeData sub-tree is
  present in the file under test.

  All checks are read-only. Filesystem checks (UNC reachability, cert PFX/CER
  existence, setup.exe, language-pack folders, CU files) are gated by
  -SkipFilesystem so the suite can be run on a workstation that doesn't yet
  have the install share mounted.

.NOTES
  Requires Pester 5.0 or later. The DSC pull / SP / SQL targets ship with Pester
  3.x out of the box; install v5 with:
      Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
#>

#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[CmdletBinding()]
param
(
  [Parameter(Mandatory = $true)]
  [string] $ConfigPath,

  [Parameter(Mandatory = $false)]
  [string] $SecretsPath,

  [Parameter(Mandatory = $false)]
  [switch] $SkipFilesystem
)

# ---------------------------------------------------------------------------
# Discovery-time load: makes the data available to -ForEach so each language
# pack / certificate / SQL alias / managed account gets its own It block (clean
# Pester reports instead of a single opaque "loop failed" line).
# ---------------------------------------------------------------------------
BeforeDiscovery {
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "ConfigPath not found: $ConfigPath"
  }
  $cfg = Import-PowerShellDataFile -LiteralPath $ConfigPath

  # ---- product detection (drives which Describe blocks run) ----
  $hasSps = [bool]$cfg.NonNodeData.SharePoint
  $hasSearchTopology = [bool]$cfg.NonNodeData.SharePoint.Services.SearchService
  $hasOos = [bool]$cfg.NonNodeData.OOS
  # SQL *tier* detection = an actual SQL node. NonNodeData.SQL alone is NOT sufficient:
  # the SharePoint config also declares a NonNodeData.SQL block (ForceEncryption flag) so
  # it can trust the SQL certificate, but it has no IsSQLServer node and must not trigger
  # the SQL role / SQL install Describe blocks.
  $hasSql = [bool]($cfg.AllNodes | Where-Object IsSQLServer)
  # SQL connection-encryption opt-in (may be declared by BOTH the SQL and SharePoint configs).
  $hasSqlEncryption = [bool]$cfg.NonNodeData.SQL.ForceEncryption
  # SQL maintenance-plan opt-in (Ola Hallengren solution).
  $hasSqlMaintenance = [bool]$cfg.NonNodeData.SQL.InstallMaintenanceSolution
  $hasAdc = [bool]$cfg.NonNodeData.ADC
  $hasAliases = [bool]$cfg.NonNodeData.SQLAlias
  # Source media is only relevant to product configs that copy install bits
  # (SPS / OOS / SQL). PDC and PULL declare no NonNodeData.SourcePath.
  $needsSourcePath = [bool]($hasSps -or $hasOos -or $hasSql)
  # Drives are now DERIVED from the authoritative NonNodeData.Disks list by the
  # Cfg*.ps1 scripts (a drive letter is declared only once). Reproduce that
  # derivation here so the drive-letter tests validate the effective values, and
  # expose the raw Disks list for its own tests.
  $disks = @($cfg.NonNodeData.Disks)
  $derivedDrives = @{}
  foreach ($disk in $disks) {
    if (-not [string]::IsNullOrWhiteSpace($disk.Type) -and -not [string]::IsNullOrWhiteSpace($disk.Letter)) {
      switch ($disk.Type) {
        'Data' { $derivedDrives.Data = ($disk.Letter.TrimEnd(':')) + ':' }
        'Logs' { $derivedDrives.Logs = ($disk.Letter.TrimEnd(':')) + ':' }
        'Temp' { $derivedDrives.Temp = ($disk.Letter.TrimEnd(':')) + ':' }
      }
    }
  }
  if (-not $derivedDrives.ContainsKey('Temp') -and $derivedDrives.ContainsKey('Data')) {
    $derivedDrives.Temp = $derivedDrives.Data
  }
  $declaredDrives = @($derivedDrives.Keys)
  # Non-OS disks that DSC will initialise (used by the Disks tests below).
  $dataDisks = @($disks | Where-Object { $_.Type -ne 'OS' })

  # ---- data-driven test inputs ----
  $allNodes = @($cfg.AllNodes | Where-Object { $_.NodeName -and $_.NodeName -ne '*' })
  $sqlAliases = @($cfg.NonNodeData.SQLAlias)
  $certs = @($cfg.NonNodeData.ADC.certificates)
  $languagePacks = @($cfg.NonNodeData.SharePoint.LanguagePacks)
  # Wrap each LanguagePacks entry in a pscustomobject (NOT a hashtable, which
  # Pester would splat-bind into test variables) so the test title can render
  # something meaningful even when the .psd1 wraps each entry in a hashtable
  # like @(@{ Name = 'fr-fr' }) instead of the expected @('fr-fr'). Without
  # this, the failing test prints 'System.Collections.Hashtable is a valid
  # xx-XX locale code', which is opaque.
  $languagePackEntries = foreach ($lp in $languagePacks) {
    $display = if ($null -eq $lp) {
      '<null -- expected a string; check for a stray comma in LanguagePacks>'
    }
    elseif ($lp -is [string]) {
      $lp
    }
    elseif ($lp -is [System.Collections.IDictionary] -and $lp.Name) {
      "<hashtable Name='$($lp.Name)' -- expected a string>"
    }
    elseif ($lp -is [System.Collections.IDictionary]) {
      '<hashtable -- expected a string>'
    }
    else {
      "<$($lp.GetType().Name) -- expected a string>"
    }
    [pscustomobject]@{
      Value   = $lp
      Display = $display
    }
  }
  $managedAccounts = @($cfg.NonNodeData.SharePoint.ManagedAccounts)
  if (-not $managedAccounts -or $managedAccounts.Count -eq 0) {
    # Mirror the script's backward-compatible default so the test covers the
    # behaviour that will actually be compiled into the MOF.
    $managedAccounts = @('FARM', 'IISAPP', 'SEARCH')
  }
  $webApps = @($cfg.NonNodeData.SharePoint.WebApplications)
}

# ---------------------------------------------------------------------------
# Runtime load: same data, exposed to the It blocks via $script: scope.
# ---------------------------------------------------------------------------
BeforeAll {
  # Resolve the default Secrets.psd1 path when caller didn't supply one.
  if (-not $SecretsPath) {
    $SecretsPath = Join-Path -Path (Split-Path -Parent (Split-Path -Parent $ConfigPath)) -ChildPath 'Secrets.psd1'
  }

  $script:ConfigPath = $ConfigPath
  $script:SecretsPath = $SecretsPath
  $script:SkipFilesystem = [bool]$SkipFilesystem
  $script:ConfigData = Import-PowerShellDataFile -LiteralPath $ConfigPath

  # Reproduce the Drives derivation the Cfg*.ps1 scripts do from NonNodeData.Disks,
  # so the drive-letter tests validate the effective (derived) values at run time.
  $script:DerivedDrives = @{}
  foreach ($disk in @($script:ConfigData.NonNodeData.Disks)) {
    if (-not [string]::IsNullOrWhiteSpace($disk.Type) -and -not [string]::IsNullOrWhiteSpace($disk.Letter)) {
      switch ($disk.Type) {
        'Data' { $script:DerivedDrives.Data = ($disk.Letter.TrimEnd(':')) + ':' }
        'Logs' { $script:DerivedDrives.Logs = ($disk.Letter.TrimEnd(':')) + ':' }
        'Temp' { $script:DerivedDrives.Temp = ($disk.Letter.TrimEnd(':')) + ':' }
      }
    }
  }
  if (-not $script:DerivedDrives.ContainsKey('Temp') -and $script:DerivedDrives.ContainsKey('Data')) {
    $script:DerivedDrives.Temp = $script:DerivedDrives.Data
  }

  if (Test-Path -LiteralPath $SecretsPath) {
    $script:SecretsData = Import-PowerShellDataFile -LiteralPath $SecretsPath
    $script:SecretNames = @($script:SecretsData.serviceAccounts | ForEach-Object { $_.Name })
  }
  else {
    $script:SecretsData = $null
    $script:SecretNames = @()
  }

  # Mirror Resolve-ProductPaths from CfgAppSps.ps1 so filesystem checks use the
  # same defaults the configuration script uses at MOF-compile time.
  function script:Resolve-ProductPath {
    param
    (
      [Parameter(Mandatory = $true)] [hashtable] $ProductConfig,
      [Parameter(Mandatory = $true)] [string]    $SourceRoot,
      [Parameter(Mandatory = $true)] [string]    $DestinationRoot,
      [Parameter(Mandatory = $true)] [string]    $DefaultSubFolder
    )
    $source = if ($ProductConfig.SourcePath) { $ProductConfig.SourcePath } else { Join-Path $SourceRoot $DefaultSubFolder }
    $dest = if ($ProductConfig.DestinationPath) { $ProductConfig.DestinationPath } else { Join-Path $DestinationRoot $DefaultSubFolder }
    $subs = if ($ProductConfig.Subfolders) { $ProductConfig.Subfolders } else { @{} }
    $binSub = if ($subs.Binaries) { $subs.Binaries } else { 'BIN' }
    $lpSub = if ($subs.LanguagePack) { $subs.LanguagePack } else { 'LP' }
    $cuSub = if ($subs.CumulativeUpdate) { $subs.CumulativeUpdate } else { 'CU' }
    return [pscustomobject]@{
      Source           = $source
      Destination      = $dest
      Binaries         = (Join-Path $dest $binSub)
      LanguagePack     = (Join-Path $dest $lpSub)
      CumulativeUpdate = (Join-Path $dest $cuSub)
    }
  }
}

# ===========================================================================
# 1. File integrity
# ===========================================================================
Describe 'ConfigurationData file' {
  It 'loads successfully via Import-PowerShellDataFile' {
    { Import-PowerShellDataFile -LiteralPath $script:ConfigPath } | Should -Not -Throw
  }
  It 'exposes AllNodes' {
    $script:ConfigData.AllNodes | Should -Not -BeNullOrEmpty
  }
  It 'exposes NonNodeData' {
    $script:ConfigData.NonNodeData | Should -Not -BeNullOrEmpty
  }
  It 'declares the wildcard AllNodes baseline (NodeName = *)' {
    $wildcard = $script:ConfigData.AllNodes | Where-Object { $_.NodeName -eq '*' }
    $wildcard | Should -Not -BeNullOrEmpty
    $wildcard.PSDscAllowDomainUser | Should -BeTrue
  }

  It 'wildcard encrypts credentials (CertificateFile + Thumbprint) — or is flagged as not yet encrypted' {
    # Security-first: production MOFs MUST encrypt credentials, which
    # Initialize-DscEncryption.ps1 wires up by setting PSDscAllowPlainTextPassword
    # to $false on the wildcard block plus CertificateFile / Thumbprint. This test
    # validates that encrypted branch. It does NOT require plain text (the previous
    # behaviour, which wrongly failed a *secured* config). When the config is not
    # yet encrypted (authoring/dev), the check is skipped with a reminder — the
    # post-compile MofEncryption guard-rail is the hard gate.
    $wildcard = $script:ConfigData.AllNodes | Where-Object { $_.NodeName -eq '*' }
    if ($wildcard.PSDscAllowPlainTextPassword -eq $false) {
      $wildcard.CertificateFile | Should -Not -BeNullOrEmpty -Because (
        'PSDscAllowPlainTextPassword = $false requires a CertificateFile so credentials are encrypted at compile time'
      )
      $wildcard.Thumbprint | Should -Not -BeNullOrEmpty -Because (
        'PSDscAllowPlainTextPassword = $false requires the encryption certificate Thumbprint'
      )
      [string]$wildcard.Thumbprint | Should -Match '^[0-9A-Fa-f]{40}$' -Because (
        'an X.509 certificate thumbprint is 40 hexadecimal characters'
      )
    }
    else {
      Set-ItResult -Skipped -Because (
        'credentials are NOT encrypted (PSDscAllowPlainTextPassword is $true or absent). ' +
        'Run scripts/init/Initialize-DscEncryption.ps1 before compiling production MOFs; ' +
        'the post-compile MofEncryption guard-rail enforces encryption on the actual MOFs.'
      )
    }
  }
}

# ===========================================================================
# 2. AllNodes — uniqueness and role consistency
# ===========================================================================
Describe 'AllNodes integrity' {
  It 'has unique NodeName values' {
    $names = @($script:ConfigData.AllNodes | ForEach-Object NodeName)
    ($names | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }

  Context 'SPS role nodes' -Skip:(-not $hasSps) {
    It 'declares at least one IsSPSServer node' {
      @($script:ConfigData.AllNodes | Where-Object IsSPSServer).Count | Should -BeGreaterThan 0
    }
    It 'declares exactly one SPS master (IsMaster = $true)' {
      @($script:ConfigData.AllNodes | Where-Object { $_.IsSPSServer -and $_.IsMaster }).Count | Should -Be 1
    }
  }

  Context 'OOS role nodes' -Skip:(-not $hasOos) {
    It 'declares at least one IsOOSServer node' {
      @($script:ConfigData.AllNodes | Where-Object IsOOSServer).Count | Should -BeGreaterThan 0
    }
    It 'declares exactly one OOS master (IsMaster = $true)' {
      @($script:ConfigData.AllNodes | Where-Object { $_.IsOOSServer -and $_.IsMaster }).Count | Should -Be 1
    }
  }

  Context 'SQL role nodes' -Skip:(-not $hasSql) {
    It 'declares at least one IsSQLServer node' {
      @($script:ConfigData.AllNodes | Where-Object IsSQLServer).Count | Should -BeGreaterThan 0
    }
  }
}

# ===========================================================================
# 3. Common NonNodeData (Disks / derived Drives, SourcePath)
# ===========================================================================
Describe 'NonNodeData common' {
  Context 'Source media path' -Skip:(-not $needsSourcePath) {
    It 'declares NonNodeData.SourcePath' {
      $script:ConfigData.NonNodeData.SourcePath | Should -Not -BeNullOrEmpty
    }

    It 'NonNodeData.SourcePath looks like a UNC or rooted local path' {
      $script:ConfigData.NonNodeData.SourcePath |
        Should -Match '^(\\\\[^\\]+\\[^\\]+|[A-Za-z]:\\)'
    }
  }

  It 'derived Drives.<_> is formatted as <letter>:' -ForEach $declaredDrives {
    $drive = $script:DerivedDrives.$_
    $drive | Should -Not -BeNullOrEmpty
    $drive | Should -Match '^[A-Z]:$'
  }
}

# ===========================================================================
# 3b. Disks — the authoritative data-disk list Initialize-DscDisks.ps1 consumes
# ===========================================================================
Describe 'NonNodeData Disks' {
  It 'declares a NonNodeData.Disks list' {
    @($script:ConfigData.NonNodeData.Disks).Count | Should -BeGreaterThan 0
  }

  It 'declares at least the SYSTEM/DATA/LOGS disks (best practice)' {
    $types = @($script:ConfigData.NonNodeData.Disks | ForEach-Object Type)
    $types | Should -Contain 'OS'
    $types | Should -Contain 'Data'
    $types | Should -Contain 'Logs'
  }

  It 'exactly one disk carries the OS type' {
    @($script:ConfigData.NonNodeData.Disks | Where-Object Type -eq 'OS').Count | Should -Be 1
  }

  It 'disk Ids are unique' {
    $ids = @($script:ConfigData.NonNodeData.Disks | ForEach-Object { [string]$_.Id })
    ($ids | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }

  It 'drive letters are unique' {
    $letters = @($script:ConfigData.NonNodeData.Disks | ForEach-Object { [string]$_.Letter })
    ($letters | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }

  It '<_.Letter> (<_.Type>) has an Id, single-letter drive and a label' -ForEach $dataDisks {
    [string]$_.Id | Should -Match '^\d+$' -Because 'DiskId is keyed by disk Number'
    [string]$_.Letter | Should -Match '^[A-Z]$'
    $_.FSLabel | Should -Not -BeNullOrEmpty
  }
}

# ===========================================================================
# 4. ADC / Certificates — references and (optional) reachability
# ===========================================================================
Describe 'ADC certificates' -Skip:(-not $hasAdc) {
  It 'certificate names are unique' {
    $names = @($script:ConfigData.NonNodeData.ADC.certificates | ForEach-Object Name)
    ($names | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }

  It 'certificate friendly names are unique' {
    $fn = @($script:ConfigData.NonNodeData.ADC.certificates | ForEach-Object FriendlyName)
    ($fn | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }

  It '<_.Name> resolves a certificate + pfx path (CertPath/PfxPath or CerFileName/PfxFileName)' -ForEach $certs {
    # DRY: an entry may carry an explicit CertPath/PfxPath, or just the file names
    # (CerFileName/PfxFileName), from which Cfg*.ps1 derives the path using the
    # shared NonNodeData.SourcePath. Either form is valid, but one must be present.
    ($_.CertPath -or $_.CerFileName) | Should -BeTrue -Because 'each certificate needs an explicit CertPath or a CerFileName to derive from SourcePath'
    ($_.PfxPath -or $_.PfxFileName) | Should -BeTrue -Because 'each certificate needs an explicit PfxPath or a PfxFileName to derive from SourcePath'
  }

  It '<_.Name> has a matching Secrets.psd1 entry (drives the PFX password)' -ForEach $certs {
    $script:SecretNames | Should -Contain $_.Name
  }

  Context 'Filesystem reachability' -Skip:($SkipFilesystem -or -not $hasAdc) {
    It '<_.Name> certificate file exists' -ForEach $certs {
      $root = ([string]$script:ConfigData.NonNodeData.SourcePath).TrimEnd('\')
      $cerPath = if ($_.CertPath) { $_.CertPath } else { '{0}\{1}' -f $root, $_.CerFileName }
      Test-Path -LiteralPath $cerPath | Should -BeTrue
    }
    It '<_.Name> pfx file exists' -ForEach $certs {
      $root = ([string]$script:ConfigData.NonNodeData.SourcePath).TrimEnd('\')
      $pfxPath = if ($_.PfxPath) { $_.PfxPath } else { '{0}\{1}' -f $root, $_.PfxFileName }
      Test-Path -LiteralPath $pfxPath | Should -BeTrue
    }
  }
}

# ===========================================================================
# 5. SQL aliases
# ===========================================================================
Describe 'SQL aliases' -Skip:(-not $hasAliases) {
  It 'alias names are unique' {
    $names = @($script:ConfigData.NonNodeData.SQLAlias | ForEach-Object Name)
    ($names | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }

  It '<_.Name> Port is an integer in 1..65535' -ForEach $sqlAliases {
    [int]$_.Port | Should -BeGreaterOrEqual 1
    [int]$_.Port | Should -BeLessOrEqual 65535
  }

  It '<_.Name> declares ServerAlias, ServerName, InstanceName' -ForEach $sqlAliases {
    $_.ServerAlias | Should -Not -BeNullOrEmpty
    $_.ServerName | Should -Not -BeNullOrEmpty
    $_.InstanceName | Should -Not -BeNullOrEmpty
  }
}

# ===========================================================================
# 6. SharePoint — product key, paths, language packs, managed accounts, web apps
# ===========================================================================
Describe 'SharePoint configuration' -Skip:(-not $hasSps) {
  Context 'Product key' {
    It 'ProductKey matches XXXXX-XXXXX-XXXXX-XXXXX-XXXXX' {
      $script:ConfigData.NonNodeData.SharePoint.ProductKey |
        Should -Match '^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$'
    }
    It 'ProductKey is not the placeholder XXXXX-...' {
      $script:ConfigData.NonNodeData.SharePoint.ProductKey |
        Should -Not -Be 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
    }
  }

  Context 'Central Administration port' {
    It 'CentralAdministrationPort is an integer in 1..65535' {
      [int]$script:ConfigData.NonNodeData.SharePoint.CentralAdministrationPort | Should -BeGreaterOrEqual 1
      [int]$script:ConfigData.NonNodeData.SharePoint.CentralAdministrationPort | Should -BeLessOrEqual 65535
    }
  }

  Context 'Search service topology' -Skip:(-not $hasSearchTopology) {
    It 'SearchService declares Topology.FirstPartitionDirectory' {
      # CfgAppSps.ps1 builds SPSearchTopology.FirstPartitionDirectory as
      # "<Drives.Data>\<SearchService.Topology.FirstPartitionDirectory>". A missing
      # key silently compiles the index location to the bare drive root (e.g. F:\).
      $script:ConfigData.NonNodeData.SharePoint.Services.SearchService.Topology.FirstPartitionDirectory |
        Should -Not -BeNullOrEmpty
    }
    It 'FirstPartitionDirectory is a relative path (joined onto the data drive)' {
      # It must NOT be rooted, otherwise "<Drive>:\<rooted path>" produces a broken path.
      $fpd = $script:ConfigData.NonNodeData.SharePoint.Services.SearchService.Topology.FirstPartitionDirectory
      [System.IO.Path]::IsPathRooted($fpd) | Should -BeFalse -Because 'it is concatenated after <Drives.Data>\'
    }
  }

  Context 'Language packs' -Skip:($languagePacks.Count -eq 0) {
    It '<_.Display> is a valid xx-XX locale code' -ForEach $languagePackEntries {
      $_.Value | Should -BeOfType [string] -Because (
        "CfgAppSps.ps1 treats each LanguagePacks entry as a string path component " +
        "(see foreach (`$spLanguagePack in `$spLanguagePacks)). Declare them as " +
        "@('fr-fr','es-es') -- not as hashtables."
      )
      [string]$_.Value | Should -Match '^[a-z]{2}-[a-z]{2}$' -Because (
        'SharePoint Language Pack folders follow the xx-xx locale convention (e.g. fr-fr, es-es).'
      )
    }
  }

  Context 'Managed accounts' {
    It '<_> exists in Secrets.psd1' -ForEach $managedAccounts {
      $script:SecretNames | Should -Contain $_
    }
  }

  Context 'Web applications' -Skip:($webApps.Count -eq 0) {
    It '<_.Name> references a known ADC certificate via CertName' -ForEach $webApps {
      $known = @($script:ConfigData.NonNodeData.ADC.certificates | ForEach-Object Name)
      $known | Should -Contain $_.CertName
    }
  }

  Context 'Installation paths (filesystem)' -Skip:$SkipFilesystem {
    BeforeAll {
      $script:SpsPaths = script:Resolve-ProductPath `
        -ProductConfig $script:ConfigData.NonNodeData.SharePoint `
        -SourceRoot    $script:ConfigData.NonNodeData.SourcePath `
        -DestinationRoot ("{0}\SoftwarePackages" -f $script:DerivedDrives.Data) `
        -DefaultSubFolder 'SPS'
    }
    It 'SourcePath is reachable' {
      Test-Path -LiteralPath $script:SpsPaths.Source | Should -BeTrue
    }
    It 'SourcePath contains a BIN sub-folder with setup.exe' {
      $setup = Join-Path -Path (Join-Path $script:SpsPaths.Source 'BIN') -ChildPath 'setup.exe'
      Test-Path -LiteralPath $setup | Should -BeTrue
    }
    It 'Language pack folder for <_.Display> exists with setup.exe' -ForEach $languagePackEntries {
      $_.Value | Should -BeOfType [string] -Because (
        "CfgAppSps.ps1 joins each LanguagePacks entry as a string path component; " +
        'non-string entries produce wrong folder paths at MOF-compile time.'
      )
      $lpRoot = Join-Path $script:SpsPaths.Source 'LP'
      $setup = Join-Path (Join-Path $lpRoot ([string]$_.Value)) 'setup.exe'
      Test-Path -LiteralPath $setup | Should -BeTrue
    }
    It 'UberCumulativeUpdate package exists' {
      $cu = $script:ConfigData.NonNodeData.SharePoint.UberCumulativeUpdate
      $cu | Should -Not -BeNullOrEmpty
      $path = if ([System.IO.Path]::IsPathRooted($cu)) { $cu } else { Join-Path (Join-Path $script:SpsPaths.Source 'CU') $cu }
      Test-Path -LiteralPath $path | Should -BeTrue
    }
  }
}

# ===========================================================================
# 7. Office Online Server
# ===========================================================================
Describe 'OOS configuration' -Skip:(-not $hasOos) {
  It 'declares CertFriendlyName that matches an ADC certificate' {
    $friendly = @($script:ConfigData.NonNodeData.ADC.certificates | ForEach-Object FriendlyName)
    $friendly | Should -Contain $script:ConfigData.NonNodeData.OOS.CertFriendlyName
  }

  It 'declares URL' {
    $script:ConfigData.NonNodeData.OOS.URL | Should -Not -BeNullOrEmpty
  }

  It 'AllServers lists every IsOOSServer node' {
    $oosNodeNames = @($script:ConfigData.AllNodes | Where-Object IsOOSServer | ForEach-Object NodeName)
    $allServers = @($script:ConfigData.NonNodeData.OOS.AllServers)
    $missing = @($oosNodeNames | Where-Object { $_ -notin $allServers })
    $missing -join ', ' | Should -BeExactly '' -Because 'OfficeOnlineServerProductUpdate.Servers must target every OOS node'
  }

  Context 'Installation paths (filesystem)' -Skip:$SkipFilesystem {
    BeforeAll {
      $script:OosPaths = script:Resolve-ProductPath `
        -ProductConfig $script:ConfigData.NonNodeData.OOS `
        -SourceRoot    $script:ConfigData.NonNodeData.SourcePath `
        -DestinationRoot ("{0}\SoftwarePackages" -f $script:DerivedDrives.Data) `
        -DefaultSubFolder 'OOS'
    }
    It 'SourcePath is reachable' {
      Test-Path -LiteralPath $script:OosPaths.Source | Should -BeTrue
    }
    It 'SourcePath contains a BIN sub-folder with setup.exe' {
      $setup = Join-Path -Path (Join-Path $script:OosPaths.Source 'BIN') -ChildPath 'setup.exe'
      Test-Path -LiteralPath $setup | Should -BeTrue
    }
    It 'CUFileName package exists' {
      $cu = $script:ConfigData.NonNodeData.OOS.CUFileName
      $cu | Should -Not -BeNullOrEmpty
      $path = if ([System.IO.Path]::IsPathRooted($cu)) { $cu } else { Join-Path (Join-Path $script:OosPaths.Source 'CU') $cu }
      Test-Path -LiteralPath $path | Should -BeTrue
    }
  }
}

# ===========================================================================
# 8. SQL configuration
# ===========================================================================
Describe 'SQL configuration' -Skip:(-not $hasSql) {
  Context 'Installation paths (filesystem)' -Skip:$SkipFilesystem {
    BeforeAll {
      # SQL uses a simpler layout — setup.exe sits at the root of the source share,
      # no BIN/LP/CU sub-folders. We still resolve via the same helper for source,
      # but only the .Source field is meaningful.
      $sqlCfg = if ($script:ConfigData.NonNodeData.SQL) { $script:ConfigData.NonNodeData.SQL } else { @{} }
      $script:SqlPaths = script:Resolve-ProductPath `
        -ProductConfig $sqlCfg `
        -SourceRoot    $script:ConfigData.NonNodeData.SourcePath `
        -DestinationRoot ("{0}\SoftwarePackages" -f $script:DerivedDrives.Data) `
        -DefaultSubFolder 'SQL'
    }
    It 'SourcePath is reachable' {
      Test-Path -LiteralPath $script:SqlPaths.Source | Should -BeTrue
    }
    It 'SourcePath contains setup.exe at its root' {
      Test-Path -LiteralPath (Join-Path $script:SqlPaths.Source 'setup.exe') | Should -BeTrue
    }
  }
}

# ===========================================================================
# 8b. SQL connection encryption (declared by the SQL and/or SharePoint config)
# ===========================================================================
Describe 'SQL connection encryption' -Skip:(-not $hasSqlEncryption) {
  It 'CertificateName resolves to an ADC certificate' {
    $certName = if ($script:ConfigData.NonNodeData.SQL.CertificateName) { $script:ConfigData.NonNodeData.SQL.CertificateName } else { 'SQLServerCert' }
    $names = @($script:ConfigData.NonNodeData.ADC.certificates | ForEach-Object Name)
    $names | Should -Contain $certName -Because 'ForceEncryption imports/binds (SQL) or trusts (SharePoint) this certificate'
  }

  It 'DatabaseConnectionEncryption, when set, is Optional / Mandatory / Strict' {
    $level = $script:ConfigData.NonNodeData.SQL.DatabaseConnectionEncryption
    if ($null -ne $level) {
      $level | Should -BeIn @('Optional', 'Mandatory', 'Strict')
    }
    else {
      Set-ItResult -Skipped -Because 'DatabaseConnectionEncryption is not declared (defaults to Optional)'
    }
  }

  It 'Mandatory / Strict declare DatabaseServerCertificateHostName' {
    $level = $script:ConfigData.NonNodeData.SQL.DatabaseConnectionEncryption
    if ($level -in @('Mandatory', 'Strict')) {
      $script:ConfigData.NonNodeData.SQL.DatabaseServerCertificateHostName |
        Should -Not -BeNullOrEmpty -Because 'the SQL alias never matches the certificate SAN, so the host name to validate must be supplied'
    }
    else {
      Set-ItResult -Skipped -Because 'DatabaseServerCertificateHostName is only required for Mandatory / Strict'
    }
  }
}

# ===========================================================================
# 8c. SQL maintenance plan (Ola Hallengren) - opt-in
# ===========================================================================
Describe 'SQL maintenance plan' -Skip:(-not $hasSqlMaintenance) {
  It 'declares a MaintenanceSolution.ScriptFileName ending in .sql' {
    $maint = $script:ConfigData.NonNodeData.SQL.MaintenanceSolution
    $name = if ($maint -and $maint.ScriptFileName) { $maint.ScriptFileName } else { 'MaintenanceSolution.sql' }
    $name | Should -Match '\.sql$'
  }

  It 'declares a non-empty target DatabaseName' {
    $maint = $script:ConfigData.NonNodeData.SQL.MaintenanceSolution
    $db = if ($maint -and $maint.DatabaseName) { $maint.DatabaseName } else { 'master' }
    $db | Should -Not -BeNullOrEmpty
  }
}

# ===========================================================================
# 9. Secrets.psd1 cross-reference
# ===========================================================================
Describe 'Secrets.psd1' {
  It 'is reachable at <_>' -ForEach @($SecretsPath) {
    Test-Path -LiteralPath $_ | Should -BeTrue
  }
  It 'declares serviceAccounts with unique Name values' {
    $script:SecretsData | Should -Not -BeNullOrEmpty
    $names = @($script:SecretsData.serviceAccounts | ForEach-Object Name)
    ($names | Group-Object | Where-Object Count -GT 1).Count | Should -Be 0
  }
}
