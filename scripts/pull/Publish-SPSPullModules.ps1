<#
  ---------------------------------------------------------------------------------
  The sample scripts are not supported under any Microsoft standard support
  program or service. The sample scripts are provided AS IS without warranty
  of any kind. Microsoft further disclaims all implied warranties including,
  without limitation, any implied warranties of merchantability or of fitness for
  a particular purpose. The entire risk arising out of the use or performance of
  the sample scripts and documentation remains with you. In no event shall
  Microsoft, its authors, or anyone else involved in the creation, production, or
  delivery of the scripts be liable for any damages whatsoever (including,
  without limitation, damages for loss of business profits, business interruption,
  loss of business information, or other pecuniary loss) arising out of the use
  of or inability to use the sample scripts or documentation, even if Microsoft
  has been advised of the possibility of such damages
  ---------------------------------------------------------------------------------
#>
#Requires -Version 5.1
<#
  .SYNOPSIS
  Packages the pinned DSC resource modules as versioned .zip files (plus checksums)
  into the pull server's module folder, so pull-mode nodes can download the
  resources they need.

  .DESCRIPTION
  A DSC pull server serves resource modules as
  <ModulePath>\<ModuleName>_<Version>.zip (each with a companion .checksum). Nodes
  in Pull mode download these to satisfy the Import-DscResource statements in their
  MOF. Without them, the LCM fails with "could not find the module" at apply time.

  By default the module list is read from the kit's single source of truth,
  scripts/init/Initialize-DscNode.psd1 (the same Modules table Initialize-DscNode.ps1
  installs and every Cfg*.ps1 pins). Alternatively, pass -ConfigurationScriptPath to
  derive the list from the Import-DscResource statements of a specific configuration
  script (parsed via the PowerShell AST, not text matching).

  Each module is zipped from the locally installed copy under
  <SourceModulesPath>\<ModuleName>\<Version>\ and a checksum is generated with
  New-DscChecksum. Re-running refreshes the archives in place (idempotent).

  .PARAMETER ManifestPath
  Path to Initialize-DscNode.psd1 (the module manifest). Default: the bundled
  ..\init\Initialize-DscNode.psd1 relative to this script. Ignored when
  -ConfigurationScriptPath is used.

  .PARAMETER ConfigurationScriptPath
  Optional. A Cfg*.ps1 whose `Import-DscResource -ModuleName X -ModuleVersion Y`
  lines drive the module list instead of the manifest. Parsed with the PS AST.

  .PARAMETER ModulePath
  Destination folder served by the pull server. Default:
  "$env:PROGRAMFILES\WindowsPowerShell\DscService\Modules" (the ModulePath set by
  CfgAppPull.ps1). Created if missing.

  .PARAMETER SourceModulesPath
  Root where the modules are installed locally. Default:
  "$env:PROGRAMFILES\WindowsPowerShell\Modules".

  .EXAMPLE
  # Publish every pinned module from the manifest to the local pull server
  .\Publish-SPSPullModules.ps1

  .EXAMPLE
  # Publish only the modules a given configuration imports
  .\Publish-SPSPullModules.ps1 -ConfigurationScriptPath ..\sps\CfgAppSps.ps1

  .EXAMPLE
  .\Publish-SPSPullModules.ps1 -ModulePath 'D:\DscService\Modules'

  .NOTES
  Project : SPSConfigKit. Run on the pull server (or a host that has the pinned
  modules installed) after CfgAppPull.ps1. Requires WMF 5.0+ (Compress-Archive).
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $ManifestPath,

  [Parameter()]
  [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
  [System.String]
  $ConfigurationScriptPath,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $ModulePath = (Join-Path -Path $env:PROGRAMFILES -ChildPath 'WindowsPowerShell\DscService\Modules'),

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $SourceModulesPath = (Join-Path -Path $env:PROGRAMFILES -ChildPath 'WindowsPowerShell\Modules')
)

$ErrorActionPreference = 'Stop'

function Get-ModuleFromManifest {
  param([System.String] $Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Manifest not found: $Path"
  }
  $data = Import-PowerShellDataFile -Path $Path
  if (-not $data.Modules) {
    throw "Manifest '$Path' has no 'Modules' table."
  }
  foreach ($m in $data.Modules) {
    [pscustomobject]@{ Name = $m.Name; Version = $m.Version }
  }
}

function Get-ModuleFromConfiguration {
  # Extract Import-DscResource -ModuleName X -ModuleVersion Y from a Cfg*.ps1 using
  # the PowerShell AST (robust) rather than string matching. PSDesiredStateConfiguration
  # is skipped (it is inbox and not served from the pull server).
  param([System.String] $Path)
  $tokens = $null; $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
  # Inside a `Configuration { }` block on Windows PowerShell 5.1 (with PSDesiredStateConfiguration
  # loaded), `Configuration` is a DSC dynamic keyword, so `Import-DscResource` is parsed as a
  # DynamicKeywordStatementAst rather than a CommandAst. When the file is parsed without the
  # Configuration keyword registered it stays a CommandAst. Match both so the module list is
  # resolved in either parsing context (otherwise nothing is published from the config script).
  $commands = $ast.FindAll({
      param($n)
      ($n -is [System.Management.Automation.Language.CommandAst] -and
        $n.GetCommandName() -eq 'Import-DscResource') -or
      ($n -is [System.Management.Automation.Language.DynamicKeywordStatementAst] -and
        $n.CommandElements.Count -gt 0 -and
        $n.CommandElements[0].Extent.Text -eq 'Import-DscResource')
    }, $true)

  $seen = @{}
  foreach ($cmd in $commands) {
    $name = $null; $version = $null
    $elements = $cmd.CommandElements
    for ($i = 0; $i -lt $elements.Count; $i++) {
      $el = $elements[$i]
      if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
        $paramName = $el.ParameterName
        $value = if ($i + 1 -lt $elements.Count) { $elements[$i + 1].Extent.Text.Trim("'`"") } else { $null }
        switch -Regex ($paramName) {
          '^ModuleName$'    { $name = $value }
          '^ModuleVersion$' { $version = $value }
        }
      }
    }
    if ($name -and ($name -notin 'PSDesiredStateConfiguration', 'PsDesiredStateConfiguration')) {
      if (-not $version) {
        throw "Import-DscResource for '$name' in '$Path' has no -ModuleVersion. Pin the version so the pull server serves a deterministic package."
      }
      $key = "$name`_$version"
      if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        [pscustomobject]@{ Name = $name; Version = $version }
      }
    }
  }
}

function Publish-DscResourceModule {
  param(
    [System.String] $Name,
    [System.String] $Version,
    [System.String] $Source,
    [System.String] $Destination
  )
  $moduleContent = Join-Path -Path $Source -ChildPath (Join-Path $Name (Join-Path $Version '*'))
  $moduleRoot = Join-Path -Path $Source -ChildPath (Join-Path $Name $Version)
  if (-not (Test-Path -LiteralPath $moduleRoot)) {
    throw ("Module '{0}' v{1} is not installed under '{2}'. Run Initialize-DscNode.ps1 (or Install-Module -RequiredVersion) first." -f $Name, $Version, $Source)
  }
  $zipPath = Join-Path -Path $Destination -ChildPath ("{0}_{1}.zip" -f $Name, $Version)

  if ($PSCmdlet.ShouldProcess($zipPath, 'Compress-Archive + New-DscChecksum')) {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Compress-Archive -Path $moduleContent -DestinationPath $zipPath -Force
    New-DscChecksum -Path $zipPath -Force | Out-Null
  }
  return $zipPath
}

$startDate = Get-Date
Write-Host '-----------------------------------------------'
Write-Host '| SPSConfigKit - Publish-SPSPullModules'
Write-Host ("| Started on         {0}" -f $startDate.ToString('o'))
Write-Host ("| Destination        {0}" -f $ModulePath)
Write-Host ("| Source modules     {0}" -f $SourceModulesPath)

try {
  # Resolve the module list (config script overrides the manifest).
  if ($ConfigurationScriptPath) {
    Write-Host ("| Module source      configuration script: {0}" -f $ConfigurationScriptPath)
    Write-Host '-----------------------------------------------'
    $modules = @(Get-ModuleFromConfiguration -Path $ConfigurationScriptPath)
  }
  else {
    $scriptBasePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
      $ManifestPath = Join-Path -Path (Split-Path -Path $scriptBasePath -Parent) -ChildPath 'init\Initialize-DscNode.psd1'
    }
    Write-Host ("| Module source      manifest: {0}" -f $ManifestPath)
    Write-Host '-----------------------------------------------'
    $modules = @(Get-ModuleFromManifest -Path $ManifestPath)
  }

  if ($modules.Count -eq 0) {
    Write-Warning 'No modules resolved. Nothing to publish.'
    return
  }

  if (-not (Test-Path -LiteralPath $ModulePath)) {
    Write-Host "Creating destination module folder $ModulePath"
    if ($PSCmdlet.ShouldProcess($ModulePath, 'Create directory')) {
      New-Item -Path $ModulePath -ItemType Directory -Force | Out-Null
    }
  }

  $published = @()
  $failed = @()
  foreach ($m in $modules) {
    try {
      $zip = Publish-DscResourceModule -Name $m.Name -Version $m.Version -Source $SourceModulesPath -Destination $ModulePath
      Write-Host ("  [+] {0} v{1} -> {2}" -f $m.Name, $m.Version, (Split-Path -Leaf $zip)) -ForegroundColor Green
      $published += $m
    }
    catch {
      Write-Host ("  [!] {0} v{1} - {2}" -f $m.Name, $m.Version, $_.Exception.Message) -ForegroundColor Yellow
      $failed += $m
    }
  }

  Write-Host '-----------------------------------------------'
  Write-Host ("| Published {0} module(s); {1} failed" -f $published.Count, $failed.Count)
  Write-Host '-----------------------------------------------'

  if ($failed.Count -gt 0) {
    throw ("{0} module(s) could not be published (see [!] lines above). Install the missing pinned modules and re-run." -f $failed.Count)
  }
}
catch {
  Write-Error -Message ("Publish-SPSPullModules failed at {0}:{1} - {2}" -f `
      $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}
