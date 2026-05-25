#Requires -Version 5.1
#Requires -RunAsAdministrator

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
<#
    .SYNOPSIS
    Configure the Local Configuration Manager (LCM) to pull DSC configuration
    from the SPSConfigKit pull server.

    .DESCRIPTION
    CfgLcmPull.ps1 cleans the DSC configuration cache and configures the LCM
    to register with a DSC pull server published on HTTPS / port 443 (matching
    the pull server defined in CfgAppPull.ps1). Compatible with WMF 5.1.
    Triggering Update-DscConfiguration is intentionally left to the caller so
    the registration and the first pull can be scheduled / monitored
    independently.

    .PARAMETER DSCRegistrationKey
    Registration key (GUID) used by the LCM to authenticate against the pull
    server. Overrides the per-domain default.

    .PARAMETER DSCPullServerUrl
    Full URL of the pull server OData endpoint, e.g. https://pull.contoso.com/PSDSCPullServer.svc

    .PARAMETER ConfigurationNames
    Names of the configurations on the pull server the node should pull.
    Defaults to the node's COMPUTERNAME.

    .PARAMETER ConfigurationMode
    LCM consistency mode. Defaults to ApplyAndMonitor.

    .PARAMETER WorkingPath
    Folder for the compiled meta-MOF. Defaults to %TEMP%\LCMConfig.

    .PARAMETER DisableLCM
    Switch to put the LCM into Push mode (no pull server, no registration).

    .PARAMETER LcmDebugMode
    LCM DebugMode (None | ForceModuleImport | ResourceScriptBreakAll | All).
    Defaults to 'None'. Use 'ForceModuleImport' when iterating on modules.

    .PARAMETER StaggerMaxSeconds
    Upper bound (seconds) of a random delay before contacting the pull server,
    to spread load when many nodes register at the same time. Defaults to 30.
    Set to 0 to disable.

    .EXAMPLE
    .\CfgLcmPull.ps1 -DSCRegistrationKey 'bde9f881-ab0d-40e3-97b4-4e92be8852d6' `
                     -DSCPullServerUrl   'https://pull.contoso.com/PSDSCPullServer.svc'

    .EXAMPLE
    .\CfgLcmPull.ps1 -DisableLCM

    .NOTES
    FileName: CfgLcmPull.ps1
    Author  : Jean-Cyril DROUHIN
    Version : 1.0.0
    Licence : MIT License
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $DSCRegistrationKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $DSCPullServerUrl,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $ConfigurationNames = @($env:COMPUTERNAME),

    [Parameter()]
    [ValidateSet('ApplyOnly', 'ApplyAndMonitor', 'ApplyAndAutoCorrect')]
    [System.String]
    $ConfigurationMode = 'ApplyAndMonitor',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $WorkingPath = (Join-Path -Path $env:TEMP -ChildPath 'LCMConfig'),

    [Parameter()]
    [switch]
    $DisableLCM,

    [Parameter()]
    [ValidateSet('None', 'ForceModuleImport', 'ResourceScriptBreakAll', 'All')]
    [System.String]
    $LcmDebugMode = 'None',

    [Parameter()]
    [ValidateRange(0, 600)]
    [System.Int32]
    $StaggerMaxSeconds = 30
)

#region Main
# ===================================================================================
# CfgLcmPull - MAIN region
# ===================================================================================
$scriptVersion     = '1.0.0'
$startDate         = Get-Date
$psVersion         = $PSVersionTable.PSVersion.ToString()
$currentUser       = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
$dscNodeTarget     = $env:COMPUTERNAME
$currentDomainName = ([System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()).DomainName

Write-Output '-----------------------------------------------'
Write-Output "| CfgLcmPull v$scriptVersion"
Write-Output ("| Started on    {0} by {1}" -f $startDate.ToString('o'), $currentUser)
Write-Output "| PowerShell    $psVersion"
Write-Output "| Target node   $dscNodeTarget"
Write-Output "| Domain        $currentDomainName"
Write-Output '-----------------------------------------------'

[DSCLocalConfigurationManager()]
Configuration LCMConfig
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $NodeName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $RegistrationKey,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $PullServerUrl,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $ConfigurationNames = @($env:COMPUTERNAME),

        [Parameter()]
        [ValidateSet('ApplyOnly', 'ApplyAndMonitor', 'ApplyAndAutoCorrect')]
        [System.String]
        $ConfigurationMode = 'ApplyAndMonitor',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Disabled', 'Push', 'Pull')]
        [System.String]
        $RefreshMode,

        [Parameter()]
        [ValidateSet('None', 'ForceModuleImport', 'ResourceScriptBreakAll', 'All')]
        [System.String]
        $DebugMode = 'None'
    )

    Node $NodeName {
        Settings {
            RefreshMode                    = $RefreshMode
            ConfigurationMode              = $ConfigurationMode
            # Interval at which the LCM checks the pull server for updated
            # configurations (Pull mode only). Must be a multiple of
            # ConfigurationModeFrequencyMins (or vice versa).
            RefreshFrequencyMins           = 120
            # How often the current configuration is checked / re-applied.
            # Ignored when ConfigurationMode is ApplyOnly. Range 15..44640.
            ConfigurationModeFrequencyMins = 60
            AllowModuleOverwrite           = $true
            RebootNodeIfNeeded             = $true
            ActionAfterReboot              = 'ContinueConfiguration'
            DebugMode                      = $DebugMode
        }
        if ($RefreshMode -eq 'Pull') {
            ConfigurationRepositoryWeb PullSrv {
                ServerURL          = $PullServerUrl
                RegistrationKey    = $RegistrationKey
                ConfigurationNames = $ConfigurationNames
            }
            ResourceRepositoryWeb ResourceSrv {
                ServerURL       = $PullServerUrl
                RegistrationKey = $RegistrationKey
            }
            ReportServerWeb ReportSrv {
                ServerURL       = $PullServerUrl
                RegistrationKey = $RegistrationKey
            }
        }
    }
}

# Step 0 - Clear the DSC configuration cache (tolerate fresh hosts)
try {
    Write-Output 'Cleaning the DSC configuration cache'
    Remove-DscConfigurationDocument -Stage Current, Pending, Previous -Force -Verbose -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5

    $dscConfigCacheFullPath = Join-Path -Path $env:windir -ChildPath 'System32\Configuration'
    if (Test-Path -Path $dscConfigCacheFullPath) {
        Get-ChildItem -Path $dscConfigCacheFullPath -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -Verbose -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Warning -Message ('DSC cache cleanup encountered an error: {0}' -f $_.Exception.Message)
}

# Step 1 - Initialize and stagger the start to avoid pull-server load spikes
try {
    Write-Output 'Setting power management plan to "High Performance"...'
    Start-Process -FilePath "$env:SystemRoot\system32\powercfg.exe" `
                  -ArgumentList '/s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' `
                  -NoNewWindow

    Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null
    if ($StaggerMaxSeconds -gt 0) {
        $staggerSeconds = Get-Random -Minimum 0 -Maximum ($StaggerMaxSeconds + 1)
        Write-Output ("Staggering startup by {0} second(s) to avoid pull-server load spikes" -f $staggerSeconds)
        Start-Sleep -Seconds $staggerSeconds
    }
}
catch {
    Write-Warning -Message ('Host initialization step encountered an error: {0}' -f $_.Exception.Message)
}

# Step 2 - Show the current LCM state for context
try {
    Write-Output 'Current local configuration manager (LCM):'
    Get-DscLocalConfigurationManager |
        Format-List RefreshMode, ConfigurationMode, ConfigurationModeFrequencyMins, RefreshFrequencyMins, AllowModuleOverwrite, RebootNodeIfNeeded |
        Out-String |
        Write-Output
}
catch {
    Write-Warning -Message ('Unable to read the current LCM state: {0}' -f $_.Exception.Message)
}

# Step 3 - Build the meta-MOF parameter set
Write-Output 'Configuring the local configuration manager (LCM)'
if (-not (Test-Path -Path $WorkingPath)) {
    New-Item -Path $WorkingPath -ItemType Directory -Force | Out-Null
}

$LCMArgs = @{
    NodeName          = $dscNodeTarget
    ConfigurationMode = $ConfigurationMode
    OutputPath        = $WorkingPath
    DebugMode         = $LcmDebugMode
}
if ($DisableLCM) {
    $LCMArgs.RefreshMode = 'Push'
}
else {
    $LCMArgs.RefreshMode        = 'Pull'
    $LCMArgs.ConfigurationNames = $ConfigurationNames
    $LCMArgs.RegistrationKey    = $DSCRegistrationKey
    $LCMArgs.PullServerUrl      = $DSCPullServerUrl

    Write-Output ("LCM will register with '{0}' using configuration names '{1}'" -f `
        $LCMArgs.PullServerUrl, ($LCMArgs.ConfigurationNames -join ','))
}

# Step 4 - Compile the meta-MOF (critical - re-throw on failure)
try {
    LCMConfig @LCMArgs
}
catch {
    Write-Error -Message ("Failed to compile the LCM meta-MOF: {0}" -f $_.Exception.Message) -ErrorAction Continue
    throw
}

# Step 5 - Enact the meta-MOF (critical - re-throw on failure)
try {
    Set-DscLocalConfigurationManager -Path $WorkingPath -Force -Verbose
}
catch {
    Write-Error -Message ("Failed to apply the LCM meta-MOF: {0}" -f $_.Exception.Message) -ErrorAction Continue
    throw
}

# Step 6 - Display the resulting LCM state and surface a clear error if Pull mode didn't take
try {
    $LCMCfg = Get-DscLocalConfigurationManager
    $LCMCfg |
        Format-List RefreshMode, ConfigurationMode, ConfigurationModeFrequencyMins, RefreshFrequencyMins, AllowModuleOverwrite, RebootNodeIfNeeded, DebugMode |
        Out-String |
        Write-Output

    if (-not $DisableLCM -and $LCMCfg.RefreshMode -ne 'Pull') {
        throw ("LCM RefreshMode is '{0}' after Set-DscLocalConfigurationManager; expected 'Pull'." -f $LCMCfg.RefreshMode)
    }
}
catch {
    Write-Error -Message ("LCM verification failed: {0}" -f $_.Exception.Message) -ErrorAction Continue
    throw
}

# Step 7 - Clean up the compiled meta-MOF (non-critical, scoped to MOF artefacts)
try {
    Get-ChildItem -Path $WorkingPath -Filter '*.mof*' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -Verbose -ErrorAction SilentlyContinue

    # Only remove the working folder itself if it was the default and is now empty
    $defaultWorkingPath = Join-Path -Path $env:TEMP -ChildPath 'LCMConfig'
    if ($WorkingPath -eq $defaultWorkingPath -and `
        -not (Get-ChildItem -Path $WorkingPath -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -Path $WorkingPath -Force -Verbose
    }
}
catch {
    Write-Warning -Message ('Unable to clean meta-MOF artefacts in ''{0}'': {1}' -f $WorkingPath, $_.Exception.Message)
}

# Step 8 - Configure the firewall: File and Printer Sharing (Domain profile only)
try {
    Write-Output 'Configuring the firewall rule "File and Printer Sharing" (Domain profile only)'
    $existingFpsRules = Get-NetFirewallRule -DisplayGroup 'File And Printer Sharing' -ErrorAction SilentlyContinue
    if ($existingFpsRules) {
        Set-NetFirewallRule -DisplayGroup 'File And Printer Sharing' -Enabled True -Profile Domain -ErrorAction Stop
    }
    else {
        Write-Warning -Message 'Built-in "File And Printer Sharing" rule group not found; creating minimal SMB/NetBIOS inbound rules on the Domain profile.'
        New-NetFirewallRule -DisplayName 'File and Printer Sharing (SMB-In)' -Group 'File And Printer Sharing' `
            -Direction Inbound -Protocol TCP -LocalPort 445 -Profile Domain -Action Allow -Enabled True | Out-Null
        New-NetFirewallRule -DisplayName 'File and Printer Sharing (NB-Session-In)' -Group 'File And Printer Sharing' `
            -Direction Inbound -Protocol TCP -LocalPort 139 -Profile Domain -Action Allow -Enabled True | Out-Null
    }
}
catch {
    Write-Warning -Message ('Unable to enable "File and Printer Sharing" on the Domain profile: {0}' -f $_.Exception.Message)
}

$endDate = Get-Date
Write-Output '-----------------------------------------------'
Write-Output '| CfgLcmPull complete'
Write-Output ("| Started on    {0}" -f $startDate.ToString('o'))
Write-Output ("| Completed on  {0}" -f $endDate.ToString('o'))
Write-Output ("| Duration      {0}" -f ($endDate - $startDate))
Write-Output '-----------------------------------------------'
#endregion
