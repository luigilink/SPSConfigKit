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
    By default it only registers the LCM; pass -UpdateNow to also trigger the
    first pull (Update-DscConfiguration -Wait) so the node fetches, applies and
    reports its configuration immediately — which populates the pull server's
    reports and therefore the compliance dashboard.

    .PARAMETER DSCRegistrationKey
    Registration key (GUID) used by the LCM to authenticate against the pull
    server. Optional when -DomainDefaultsPath resolves it for the current domain;
    when supplied it overrides the per-domain default.

    .PARAMETER DSCPullServerUrl
    Full URL of the pull server OData endpoint, e.g.
    https://pull.contoso.com/PSDSCPullServer.svc. Optional when -DomainDefaultsPath
    resolves it for the current domain; when supplied it overrides the default.
    SPSConfigKit expects an HTTPS/443 pull server; a non-HTTPS URL is warned about.

    .PARAMETER DomainDefaultsPath
    Optional path to a .psd1 that maps each domain FQDN to its pull-server
    RegistrationKey and Url, so the correct pull server is selected automatically
    per domain without editing this script. When -DSCRegistrationKey /
    -DSCPullServerUrl are omitted, the entry for the current domain is used. Keep
    the real file OUT of source control (it holds registration keys); a
    CfgLcmPull.DomainDefaults.sample.psd1 ships as a template. Shape:
        @{ 'contoso.com' = @{ RegistrationKey = '<guid>'; PullServerUrl = 'https://pull.contoso.com/PSDSCPullServer.svc' } }

    .PARAMETER NodeManifestPath
    Optional folder (typically a UNC share the pull server and the dashboard can
    both read) where this script publishes a per-node <NodeName>.json entry after
    registering, containing NodeName, AgentId and ConfigurationNames. The
    compliance dashboard (New-SPSDscDashboard.ps1) reads these entries to discover
    which nodes exist, because the pull server's OData API cannot enumerate nodes
    (GET /Nodes returns HTTP 400) — it only answers keyed Nodes(AgentId='...')
    queries. May also be supplied per-domain via -DomainDefaultsPath
    (NodeManifestPath key). Re-registration overwrites the node's own file.

    .PARAMETER UpdateNow
    After registering the LCM in Pull mode, trigger an immediate
    Update-DscConfiguration -Wait so the node pulls, applies and reports right
    away (populating the compliance dashboard). Ignored with -DisableLCM.

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

    .PARAMETER CertificateThumbprint
    Thumbprint (40 hex chars) of the document-encryption certificate the LCM uses
    to decrypt the credentials in the MOF it pulls. When omitted it is resolved
    automatically from the newest CN=DSC Encryption certificate that has a private
    key in Cert:\LocalMachine\My (imported by Initialize-DscNode.ps1).

    .PARAMETER CertificateSubject
    Subject of the document-encryption certificate to look up when
    -CertificateThumbprint is not supplied. Defaults to 'CN=DSC Encryption'.

    .EXAMPLE
    .\CfgLcmPull.ps1 -DSCRegistrationKey 'bde9f881-ab0d-40e3-97b4-4e92be8852d6' `
                     -DSCPullServerUrl   'https://pull.contoso.com/PSDSCPullServer.svc'

    .EXAMPLE
    # Resolve the pull server automatically for this domain and pull immediately
    .\CfgLcmPull.ps1 -DomainDefaultsPath .\CfgLcmPull.DomainDefaults.psd1 -UpdateNow

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
    [Parameter()]
    [System.String]
    $DSCRegistrationKey,

    [Parameter()]
    [System.String]
    $DSCPullServerUrl,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [System.String]
    $DomainDefaultsPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $NodeManifestPath,

    [Parameter()]
    [switch]
    $UpdateNow,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String[]]
    $ConfigurationNames = @($env:COMPUTERNAME),

    [Parameter()]
    [ValidateSet('ApplyOnly', 'ApplyAndMonitor', 'ApplyAndAutoCorrect')]
    [System.String]
    $ConfigurationMode = 'ApplyAndMonitor',

    [Parameter()]
    [ValidatePattern('^[0-9A-Fa-f]{40}$')]
    [System.String]
    $CertificateThumbprint,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $CertificateSubject = 'CN=DSC Encryption',

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

# Resolve the registration key / pull-server URL from a per-domain defaults file
# when they were not passed explicitly. This mirrors the operational convenience
# of auto-selecting the right pull server per domain WITHOUT baking any
# registration key into source control: the defaults file is customer-provided and
# git-ignored, and only a .sample template ships in the repo.
if (-not $DisableLCM) {
    if (($DomainDefaultsPath) -and
        ([string]::IsNullOrWhiteSpace($DSCRegistrationKey) -or [string]::IsNullOrWhiteSpace($DSCPullServerUrl))) {
        Write-Output ("Resolving pull-server defaults for domain '{0}' from {1}" -f $currentDomainName, $DomainDefaultsPath)
        $domainDefaults = Import-PowerShellDataFile -Path $DomainDefaultsPath
        $match = $domainDefaults[$currentDomainName]
        if (-not $match) {
            throw ("No entry for domain '{0}' in {1}. Add one, or pass -DSCRegistrationKey / -DSCPullServerUrl explicitly." -f $currentDomainName, $DomainDefaultsPath)
        }
        if ([string]::IsNullOrWhiteSpace($DSCRegistrationKey)) { $DSCRegistrationKey = $match.RegistrationKey }
        if ([string]::IsNullOrWhiteSpace($DSCPullServerUrl)) { $DSCPullServerUrl = $match.PullServerUrl }
        if ([string]::IsNullOrWhiteSpace($NodeManifestPath) -and $match.NodeManifestPath) { $NodeManifestPath = $match.NodeManifestPath }
    }

    if ([string]::IsNullOrWhiteSpace($DSCRegistrationKey) -or [string]::IsNullOrWhiteSpace($DSCPullServerUrl)) {
        throw 'Pull mode requires -DSCRegistrationKey and -DSCPullServerUrl (pass them directly, or use -DomainDefaultsPath with an entry for this domain).'
    }

    if ($DSCPullServerUrl -notlike 'https://*') {
        Write-Warning ("Pull server URL '{0}' is not HTTPS. SPSConfigKit expects an HTTPS/443 pull server; otherwise registration and reports travel in clear text." -f $DSCPullServerUrl)
    }
}

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
        $DebugMode = 'None',

        [Parameter()]
        [System.String]
        $CertificateId
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
            # Certificate the LCM uses to decrypt the encrypted credentials in the
            # MOF it pulls from the server. Resolved from the local store (the
            # CN=DSC Encryption cert imported by Initialize-DscNode.ps1) or from
            # -CertificateThumbprint. Empty in Disabled/Push mode where no
            # encrypted pull document is applied.
            CertificateID                  = $CertificateId
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

# Resolve the document-encryption certificate the LCM will use to decrypt the
# credentials in the MOF it pulls. Prefer the explicit -CertificateThumbprint;
# otherwise pick the newest CN=DSC Encryption certificate that has a private key
# in the local machine store (imported by Initialize-DscNode.ps1).
$resolvedCertId = $null
if ($CertificateThumbprint) {
    $resolvedCertId = $CertificateThumbprint
    Write-Output ("Using LCM decryption certificate from -CertificateThumbprint: {0}" -f $resolvedCertId)
}
else {
    $encryptionCert = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $CertificateSubject -and $_.HasPrivateKey } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if ($encryptionCert) {
        $resolvedCertId = $encryptionCert.Thumbprint
        Write-Output ("Resolved LCM decryption certificate '{0}' (thumbprint {1})" -f $CertificateSubject, $resolvedCertId)
    }
}

if ($DisableLCM) {
    $LCMArgs.RefreshMode = 'Push'
}
else {
    $LCMArgs.RefreshMode        = 'Pull'
    $LCMArgs.ConfigurationNames = $ConfigurationNames
    $LCMArgs.RegistrationKey    = $DSCRegistrationKey
    $LCMArgs.PullServerUrl      = $DSCPullServerUrl

    if ($resolvedCertId) {
        $LCMArgs.CertificateId = $resolvedCertId
    }
    else {
        Write-Warning ("No '{0}' certificate with a private key was found in the local machine store and -CertificateThumbprint was not supplied. The LCM will be unable to decrypt encrypted MOFs pulled from the server. Run Initialize-DscNode.ps1 to import the .pfx first." -f $CertificateSubject)
    }

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

# Step 6b - Publish this node's AgentId to the shared node manifest so the
# compliance dashboard can enumerate nodes. The pull server's OData API cannot
# list nodes (GET /Nodes returns HTTP 400 "resourceKeys is unexpected"); it only
# answers keyed queries (Nodes(AgentId='...')/Reports). Registration is the one
# moment we hold this node's AgentId, so we drop a per-node <NodeName>.json file
# in the manifest folder. Re-registration overwrites the same file, so a node
# that gets a new AgentId never leaves a stale entry behind.
if (-not $DisableLCM -and -not [string]::IsNullOrWhiteSpace($NodeManifestPath)) {
    try {
        $agentId = (Get-DscLocalConfigurationManager).AgentId
        if ([string]::IsNullOrWhiteSpace($agentId)) {
            Write-Warning 'LCM did not report an AgentId yet; skipping node manifest publication.'
        }
        else {
            if (-not (Test-Path -LiteralPath $NodeManifestPath)) {
                New-Item -Path $NodeManifestPath -ItemType Directory -Force | Out-Null
            }
            $manifestEntry = [ordered]@{
                NodeName           = $dscNodeTarget
                AgentId            = $agentId
                ConfigurationNames = @($ConfigurationNames)
                PullServerUrl      = $DSCPullServerUrl
                RegisteredOn       = (Get-Date).ToString('o')
            }
            $manifestFile = Join-Path -Path $NodeManifestPath -ChildPath ("{0}.json" -f $dscNodeTarget)
            $manifestEntry | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestFile -Encoding UTF8 -Force
            Write-Output ("Published node manifest entry for AgentId {0} to '{1}'." -f $agentId, $manifestFile)
        }
    }
    catch {
        Write-Warning ("Unable to publish the node manifest entry to '{0}': {1}" -f $NodeManifestPath, $_.Exception.Message)
    }
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

# Step 9 - Optionally trigger the first pull so the node fetches, applies and
# reports its configuration immediately. This is what populates the pull server's
# StatusReport records (and therefore the compliance dashboard). Skipped in Push
# mode; a failure here is non-fatal because the LCM will pull on its next interval.
if ($UpdateNow -and -not $DisableLCM) {
    try {
        Write-Output 'Triggering an immediate pull (Update-DscConfiguration -Wait)'
        Update-DscConfiguration -Wait -Verbose -ErrorAction Stop
    }
    catch {
        Write-Warning -Message ('Immediate Update-DscConfiguration failed (the LCM will still pull on its next interval): {0}' -f $_.Exception.Message)
    }
}

$endDate = Get-Date
Write-Output '-----------------------------------------------'
Write-Output '| CfgLcmPull complete'
Write-Output ("| Started on    {0}" -f $startDate.ToString('o'))
Write-Output ("| Completed on  {0}" -f $endDate.ToString('o'))
Write-Output ("| Duration      {0}" -f ($endDate - $startDate))
Write-Output '-----------------------------------------------'
#endregion
