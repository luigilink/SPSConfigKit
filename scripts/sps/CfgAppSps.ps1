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
#Requires -RunAsAdministrator
<#
  .SYNOPSIS
  Compiles the SharePoint Server Subscription Edition DSC configuration: SharePoint
  farm provisioning (binaries + language packs + cumulative updates), service
  applications, web applications, search topology, and the co-located Office
  Online Server farm used for in-browser document rendering.

  .DESCRIPTION
  Imports node + non-node data from a .psd1 file and secret material from
  Secrets.psd1, then compiles MOF files for every node defined in AllNodes.
  The script is idempotent: re-running it simply regenerates the MOFs in
  the output directory and refreshes the checksums.

  .PARAMETER inputFile
  Full path to the ConfigurationData .psd1. Defaults to CfgAppSps.psd1 in
  the same directory as the script.

  .PARAMETER secretsFile
  Full path to the Secrets.psd1. Defaults to ..\Secrets.psd1 relative to
  the script directory.

  .PARAMETER OutputPath
  Directory where the compiled MOF files (and checksums) are written.
  Defaults to <scriptDir>\MOF. The directory is created if missing.

  .EXAMPLE
  .\CfgAppSps.ps1

  .EXAMPLE
  .\CfgAppSps.ps1 -inputFile .\CfgAppSps.psd1 -secretsFile ..\Secrets.psd1 -OutputPath C:\DSC\MOF

  .NOTES
  Project : SPSConfigKit
  Requires: PowerShell 5.1, RunAsAdministrator, and the DSC modules listed in the Import-DscResource calls below.
#>

[CmdletBinding()]
param(
  [Parameter()]
  [System.String]
  $inputFile,

  [Parameter()]
  [System.String]
  $secretsFile,

  [Parameter()]
  [System.String]
  $OutputPath
)

try {
  #Resolve a reliable base path even when $PSScriptRoot is empty (for example when executed interactively)
  [System.String]$scriptBasePath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
  }
  elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
  }
  else {
    (Get-Location).Path
  }

  #Import configuration data from the specified .psd1 file
  if ([string]::IsNullOrWhiteSpace($inputFile)) {
    Write-Host 'No input file provided. Try to use CfgAppSps.psd1 in the same directory as the script.'
    $inputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppSps.psd1'
  }
  if (Test-Path $inputFile) {
    Write-Host "Importing configuration data from $inputFile"
    $configurationData = Import-PowerShellDataFile -Path $inputFile
  }
  else {
    throw "Missing $inputFile"
  }

  if ([string]::IsNullOrWhiteSpace($secretsFile)) {
    Write-Host 'No secrets file provided. Try to use Secrets.psd1 in the parent directory of the script.'
    $secretsFile = Join-Path -Path (Split-Path -Path $scriptBasePath -Parent) -ChildPath 'Secrets.psd1'
  }
  if (Test-Path $secretsFile) {
    Write-Host "Importing secrets data from $secretsFile"
    $secretsData = Import-PowerShellDataFile -Path $secretsFile
    #Initialize each secret as a variable
    $serviceAccounts = $secretsData.serviceAccounts
    foreach ($serviceAccount in $serviceAccounts) {
      $username = $serviceAccount.UserName
      $password = ConvertTo-SecureString $serviceAccount.Password -AsPlainText -Force
      $credential = New-Object -TypeName System.Management.Automation.PSCredential `
        -ArgumentList $username, $password
      New-Variable -Name $serviceAccount.Name -Value $credential -Force
    }
  }
  else {
    throw "Missing $secretsFile"
  }

  #Initialization of the output path for the generated MOF files.
  #Honour the -OutputPath parameter when supplied; otherwise default to <scriptDir>\MOF.
  if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $mofOutputPath = Join-Path -Path $scriptBasePath -ChildPath 'MOF'
  }
  else {
    $mofOutputPath = $OutputPath
  }
  if (-not (Test-Path -Path $mofOutputPath)) {
    New-Item -Path $mofOutputPath -ItemType Directory | Out-Null
  }

  function Get-CertThumbprint() {
    param
    (
      [parameter(Mandatory = $true)]
      [System.String]
      $CertPath
    )
    try {
      $certObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
      $certObject.Import($CertPath, "", 'DefaultKeySet')
      $item = Get-Item $CertPath
      return @{
        Error      = $false
        Thumbprint = $certObject.Thumbprint
        BaseName   = $item.BaseName
      }
    }
    catch {
      Write-Warning $_.Exception.Message
      Write-Warning "$CertPath was not found"
      return @{
        Error      = $true
        Thumbprint = "0000000000000000000000000000000000000000"
        BaseName   = "ERROR"
      }
    }
  }

  function Resolve-ProductPaths() {
    <#
      .SYNOPSIS
      Resolves installation-media source/destination paths for a product (SharePoint, OOS, ...)
      with sensible defaults, so customers with non-standard file hierarchies can override any
      level without forking the configuration script.

      Resolution rules (all overrides are optional):
        Source           = $ProductConfig.SourcePath       ?? Join-Path $SourceRoot      $DefaultSubFolder
        Destination      = $ProductConfig.DestinationPath  ?? Join-Path $DestinationRoot $DefaultSubFolder
        Binaries         = Join-Path $Destination ($ProductConfig.Subfolders.Binaries         ?? 'BIN')
        LanguagePack     = Join-Path $Destination ($ProductConfig.Subfolders.LanguagePack     ?? 'LP')
        CumulativeUpdate = Join-Path $Destination ($ProductConfig.Subfolders.CumulativeUpdate ?? 'CU')
    #>
    param
    (
      [parameter(Mandatory = $true)] [hashtable] $ProductConfig,
      [parameter(Mandatory = $true)] [System.String] $SourceRoot,
      [parameter(Mandatory = $true)] [System.String] $DestinationRoot,
      [parameter(Mandatory = $true)] [System.String] $DefaultSubFolder
    )
    $source = if ($ProductConfig.SourcePath) { $ProductConfig.SourcePath } else { Join-Path $SourceRoot $DefaultSubFolder }
    $dest = if ($ProductConfig.DestinationPath) { $ProductConfig.DestinationPath } else { Join-Path $DestinationRoot $DefaultSubFolder }
    $subs = if ($ProductConfig.Subfolders) { $ProductConfig.Subfolders } else { @{} }
    $binSub = if ($subs.Binaries) { $subs.Binaries } else { 'BIN' }
    $lpSub = if ($subs.LanguagePack) { $subs.LanguagePack } else { 'LP' }
    $cuSub = if ($subs.CumulativeUpdate) { $subs.CumulativeUpdate } else { 'CU' }
    return @{
      Source           = $source
      Destination      = $dest
      Binaries         = (Join-Path $dest $binSub)
      LanguagePack     = (Join-Path $dest $lpSub)
      CumulativeUpdate = (Join-Path $dest $cuSub)
    }
  }

  Configuration CfgAppSps {
    # NOTE: Module versions below MUST stay in sync with
    #       scripts/init/Initialize-DscNode.psd1 (Modules table).
    #Import the required DSC resources
    Import-DscResource -ModuleName CertificateDsc -ModuleVersion 6.0.0
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion 10.0.0
    Import-DscResource -ModuleName NetworkingDsc -ModuleVersion 9.1.0
    Import-DscResource -ModuleName OfficeOnlineServerDsc -ModuleVersion 1.5.0
    Import-DscResource -ModuleName PSDscResources -ModuleVersion 2.12.0.0
    Import-DscResource -ModuleName SharePointDsc -ModuleVersion 5.7.0
    Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 17.5.1
    Import-DscResource -ModuleName WebAdministrationDsc -ModuleVersion 4.2.1
    Import-DscResource -ModuleName xCredSSP -ModuleVersion 1.4.0
    
    #Initialize Master and Search Master variables based on the roles defined in the configuration data
    $SPSMaster = $AllNodes.Where{ $_.IsSPSServer -and $_.IsMaster }.NodeName
    $SPSSearchMaster = ($AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -like "*Search*" } | Select-Object -First 1).NodeName
    
    #For All servers
    Node $AllNodes.Nodename {
      #Set the Local Configuration Manager
      LocalConfigurationManager {
        ConfigurationMode  = 'ApplyOnly'
        RebootNodeIfNeeded = $true
      }
      #Create the SoftwarePackages folder
      File APPLICATION_SpsAddSoftwarePackages {
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Data)\SoftwarePackages"
      }
      #Stop unnecessary Windows Services
      Service SYSTEM_SvcSpoolerManualStopped {
        Name        = 'Spooler'
        StartupType = 'Manual'
        State       = 'Stopped'
      }
      Service SYSTEM_SvcAudioSrvManualStopped {
        Name        = 'AudioSrv'
        StartupType = 'Manual'
        State       = 'Stopped'
      }
      Service SYSTEM_SvcTWerSvcDisableStopped {
        Name        = 'WerSvc'
        StartupType = 'Disabled'
        State       = 'Stopped'
      }
      #Enable Windows Firewall File And Printer Sharing
      Script SYSTEM_EnableFileAndPrinterSharing {
        GetScript  = { }
        TestScript = { return $null -ne (Get-NetFirewallRule -DisplayGroup 'File And Printer Sharing' -Enabled True -ErrorAction SilentlyContinue | Where-Object { $_.Profile -eq 'Domain' }) }
        SetScript  = { Set-NetFirewallRule -DisplayGroup 'File And Printer Sharing' -Enabled True -Profile Domain }
      }
      #Enable Windows Firewall Remote Event Log Management
      Script SYSTEM_EnableRemoteEventLogManagement {
        GetScript  = { }
        TestScript = { return $null -ne (Get-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -ErrorAction SilentlyContinue | Where-Object { $_.Profile -eq 'Domain' }) }
        SetScript  = { Set-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -Profile Any }
      }
      #Install the Remote Server Administration Tools for Active Directory Domain Services Tools
      WindowsFeature SYSTEM_ADS_Feature_RSAT-AD-Tools {
        Name                 = 'RSAT-AD-Tools'
        IncludeAllSubFeature = $true
        Ensure               = 'Present'
      }
      #Set the AuthServerAllowlist registry key
      Registry SYSTEM_SPSAuthServerAllowList {
        Key       = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge'
        ValueName = 'AuthServerAllowlist'
        ValueType = 'String'
        ValueData = "*app1*,*$($ConfigurationData.NonNodeData.DomainName)*"
        Ensure    = 'Present'
      }
      # Log the progress of the configuration application
      Log SYSTEM_AllNodes_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = '[SYSTEM]All Nodes Configuration Completed'
        DependsOn = '[Registry]SYSTEM_SPSAuthServerAllowList'
      }
    }

    #For all servers with SharePoint Role
    Node $AllNodes.Where{ $_.IsSPSServer }.NodeName {
      Group AddSPSetupAccountToAdminGroup {
        GroupName            = "Administrators"
        Ensure               = "Present"
        MembersToInclude     = $Node.LocalAdmins
        Credential           = $ADSETUP
        PsDscRunAsCredential = $ADSETUP
      }
      #Configure CredSSP Server | Client
      xCredSSP SECURITY_CredSSPServer {
        Ensure = 'Present'
        Role   = 'Server'
      }
      xCredSSP SECURITY_CredSSPClient {
        Ensure            = 'Present'
        Role              = 'Client'
        DelegateComputers = "*.$($ConfigurationData.NonNodeData.DomainName)"
      }
      #With CLIConfg utility, create the SQL Server alias
      $aliasSQLs = $ConfigurationData.NonNodeData.SQLAlias
      foreach ($aliasSQL in $aliasSQLs) {
        SqlAlias "MIDDLEWARE_SqlAlias_$($aliasSQL.Name)" {
          Ensure            = 'Present'
          Protocol          = 'TCP'
          TcpPort           = $aliasSQL.Port
          UseDynamicTcpPort = $False
          Name              = $aliasSQL.ServerAlias
          ServerName        = "$($aliasSQL.ServerName)\$($aliasSQL.InstanceName)"
        }
      }

      #Initialize variables for SharePoint Source Path.
      # Resolution is delegated to Resolve-ProductPaths so customers can override
      # NonNodeData.SharePoint.SourcePath / .DestinationPath / .Subfolders.* in their .psd1
      # without touching the configuration script. Defaults preserve the original layout:
      #   <SourcePath>\SPS  /  <Drives.Data>\SoftwarePackages\SPS  with BIN / LP / CU subfolders.
      $spPaths = Resolve-ProductPaths `
        -ProductConfig    $ConfigurationData.NonNodeData.SharePoint `
        -SourceRoot       $ConfigurationData.NonNodeData.SourcePath `
        -DestinationRoot  (Join-Path $ConfigurationData.NonNodeData.Drives.Data 'SoftwarePackages') `
        -DefaultSubFolder 'SPS'
      #Copy the SharePoint installation files from the Azure File Share
      File APPLICATION_SpsGetSources {
        Ensure          = 'Present'
        Type            = 'Directory'
        SourcePath      = $spPaths.Source
        DestinationPath = $spPaths.Destination
        Recurse         = $true
        MatchSource     = $true
        Force           = $true
        Checksum        = 'modifiedDate'
        Credential      = $ADSETUP
      }
      #Install the SharePoint prerequisites
      if ($Node.SPVersion -eq 'SE') {
        $requiredFeatures = @(
          'NET-WCF-Pipe-Activation45', 'NET-WCF-HTTP-Activation45', 'NET-WCF-TCP-Activation45',
          'Web-Server', 'Web-WebServer', 'Web-Common-Http', 'Web-Static-Content', 'Web-Default-Doc',
          'Web-Dir-Browsing', 'Web-Http-Errors', 'Web-App-Dev', 'Web-Asp-Net45', 'Web-Net-Ext45',
          'Web-ISAPI-Ext', 'Web-ISAPI-Filter', 'Web-Health', 'Web-Http-Logging', 'Web-Log-Libraries',
          'Web-Request-Monitor', 'Web-Http-Tracing', 'Web-Security', 'Web-Basic-Auth',
          'Web-Windows-Auth', 'Web-Filtering', 'Web-Performance', 'Web-Stat-Compression',
          'Web-Dyn-Compression', 'WAS', 'WAS-Process-Model', 'WAS-Config-APIs'
        )

        foreach ($feature in $requiredFeatures) {
          WindowsFeature "WindowsFeature-$feature" {
            Ensure = 'Present'
            Name   = $feature
          }
        }
      }
      SPInstallPrereqs APPLICATION_SpsInstallPrereqs {
        DependsOn        = '[File]APPLICATION_SpsGetSources'
        Ensure           = 'Present'
        IsSingleInstance = 'Yes'
        InstallerPath    = (Join-Path $spPaths.Binaries 'prerequisiteinstaller.exe')
        OnlineMode       = $True
      }

      #IIS clean up
      $appPoolToRemove = @('.NET v2.0', '.NET v2.0 Classic', '.NET v4.5', '.NET v4.5 Classic', 'Classic .NET AppPool', 'DefaultAppPool')
      foreach ($appPool in $appPoolToRemove) {
        WebAppPool ('MIDDLEWARE_' + $appPool.Replace(' ', '')) {
          DependsOn = '[SPInstallPrereqs]APPLICATION_SpsInstallPrereqs'
          Ensure    = 'Absent'
          Name      = $appPool
        }
      }
      WebSite MIDDLEWARE_RemoveDefaultWebSite {
        DependsOn    = '[SPInstallPrereqs]APPLICATION_SpsInstallPrereqs'
        Ensure       = 'Absent'
        Name         = 'Default Web Site'
        PhysicalPath = 'C:\inetpub\wwwroot'
      }
      #Configure IIS logging
      File MIDDLEWARE_IIS-LogFolder {
        DependsOn       = '[SPInstallPrereqs]APPLICATION_SpsInstallPrereqs'
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.LogFolder)"
      }
      IisLogging MIDDLEWARE_IIS-ConfigureLogFolder {
        DependsOn = '[File]MIDDLEWARE_IIS-LogFolder'
        LogPath   = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.LogFolder)"
      }
      #Configure IIS HTTPERR
      File MIDDLEWARE_IIS-LogFolderHTTPERR {
        DependsOn       = '[SPInstallPrereqs]APPLICATION_SpsInstallPrereqs'
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.httpErrFolder)"
      }
      Registry MIDDLEWARE_IIS-RegLogFolderHTTPERR {
        DependsOn = '[File]MIDDLEWARE_IIS-LogFolderHTTPERR'
        Key       = 'HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\HTTP\Parameters'
        ValueName = 'ErrorLoggingDir'
        ValueType = 'String'
        ValueData = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.httpErrFolder)"
        Ensure    = 'Present'
      }
      #Install SharePoint Binaries
      SPInstall APPLICATION_SpsInstallSharePoint {
        DependsOn        = '[SPInstallPrereqs]APPLICATION_SpsInstallPrereqs'
        Ensure           = 'Present'
        IsSingleInstance = 'Yes'
        BinaryDir        = $spPaths.Binaries
        ProductKey       = "$($ConfigurationData.NonNodeData.SharePoint.ProductKey)"
        DataPath         = "$($ConfigurationData.NonNodeData.Drives.Data)\OfficeServer\Data"
      }
      Log APPLICATION_SpsInstallSharePoint_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = '[SPInstall]Installation of SharePoint Server Completed'
        DependsOn = '[SPInstall]APPLICATION_SpsInstallSharePoint'
      }
      # Installation of SharePoint Language Packs (data-driven).
      # When NonNodeData.SharePoint.LanguagePacks is null or empty, no SPInstallLanguagePack
      # resources are emitted and the SPProductUpdate (CU) resource chains directly off SPInstall.
      # When one or more locales are listed, each pack installs sequentially (chained via DependsOn)
      # to avoid concurrent SharePoint setup invocations, and the CU resource depends on the last pack.
      $spLanguagePacks = $ConfigurationData.NonNodeData.SharePoint.LanguagePacks
      $cuDependsOn = '[SPInstall]APPLICATION_SpsInstallSharePoint'
      if ($null -ne $spLanguagePacks -and $spLanguagePacks.Count -gt 0) {
        $previousLangPackResource = '[SPInstall]APPLICATION_SpsInstallSharePoint'
        foreach ($spLanguagePack in $spLanguagePacks) {
          # Sanitise the locale code (e.g. 'fr-fr' -> 'frfr') to build a valid DSC resource identifier.
          $lpToken = ($spLanguagePack -replace '[^A-Za-z0-9]', '')
          $lpResourceName = "APPLICATION_SpsLangPack_$lpToken"
          SPInstallLanguagePack $lpResourceName {
            DependsOn = $previousLangPackResource
            Ensure    = 'Present'
            BinaryDir = (Join-Path $spPaths.LanguagePack $spLanguagePack)
          }
          # Log the progress of the installation of each Language Pack
          Log "APPLICATION_SpsInstallLanguagePack_${lpToken}_Completed" {
            #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
            Message   = "[SPInstallLanguagePack]Installation of Language Pack $spLanguagePack Completed"
            DependsOn = "[SPInstallLanguagePack]$lpResourceName"
          }
          $previousLangPackResource = "[SPInstallLanguagePack]$lpResourceName"
        }
        # CU must wait for the final language pack so binary patching applies to every installed locale.
        $cuDependsOn = $previousLangPackResource
      }
      # Add SharePoint diagnostic logs folder
      File APPLICATION_SpsApplyDiagLogFolder {
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs)"
      }
      # Add SharePoint Usage logs folder
      File APPLICATION_SpsApplyUsageLogFolder {
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.SharePoint.UsageLogs)"
      }
      #Install SharePoint Server Cumulative Updates.
      # UberCumulativeUpdate may be either a fully-qualified path (used as-is, the original
      # behaviour) or a path relative to $spPaths.CumulativeUpdate. Detecting via IsPathRooted
      # preserves backward compatibility for existing .psd1 files.
      $spCuValue = $ConfigurationData.NonNodeData.SharePoint.UberCumulativeUpdate
      $spCuSetupFile = if ([System.IO.Path]::IsPathRooted($spCuValue)) {
        $spCuValue
      }
      else {
        Join-Path $spPaths.CumulativeUpdate $spCuValue
      }
      SPProductUpdate 'APPLICATION_SpsCumulativeUpdateUberInstallation' {
        DependsOn            = $cuDependsOn
        SetupFile            = $spCuSetupFile
        ShutdownServices     = $false
        Ensure               = 'Present'
        PsDscRunAsCredential = $SETUP
      }
      # Log the progress of the installation of SharePoint Server
      Log APPLICATION_SpsCumulativeUpdateUberInstallation_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = '[SPProductUpdate]Installation of Cumulative Update Completed'
        DependsOn = '[SPProductUpdate]APPLICATION_SpsCumulativeUpdateUberInstallation'
      }
    }
    #For All SharePoint servers MASTER
    Node $SPSMaster {
      #New SPFarm Object
      $sqlAliasADM = $ConfigurationData.NonNodeData.SQLAlias | Where-Object -FilterScript { $_.Name -eq 'ADMIN' }
      $sqlAliasSVC = $ConfigurationData.NonNodeData.SQLAlias | Where-Object -FilterScript { $_.Name -eq 'SERVICES' }
      SPFarm APPLICATION_SpsCreateSPFarm {
        DependsOn                    = '[SqlAlias]MIDDLEWARE_SqlAlias_ADMIN', '[SPProductUpdate]APPLICATION_SpsCumulativeUpdateUberInstallation'
        PsDscRunAsCredential         = $SETUP
        Ensure                       = 'Present'
        IsSingleInstance             = 'Yes'
        DatabaseServer               = $sqlAliasADM.ServerAlias
        FarmConfigDatabaseName       = "$($ConfigurationData.NonNodeData.SharePoint.FarmConfigDatabaseName)"
        Passphrase                   = $PassPhrase
        FarmAccount                  = $FARM
        AdminContentDatabaseName     = "$($ConfigurationData.NonNodeData.SharePoint.AdminContentDatabaseName)"
        CentralAdministrationPort    = "$($ConfigurationData.NonNodeData.SharePoint.CentralAdministrationPort)"
        RunCentralAdmin              = $true
        ServerRole                   = $Node.SPServerRole
        DatabaseConnectionEncryption = 'Optional'
      }
      # Add SharePoint Managed Account.
      # Allowlist of Secrets.psd1 entries that SharePoint owns as Managed Accounts.
      # The list is read from NonNodeData.SharePoint.ManagedAccounts so customers can extend
      # it (e.g. add a dedicated Workflow / custom service-app account) without forking the
      # configuration script. When the key is omitted the historical default
      # @('FARM', 'IISAPP', 'SEARCH') is used. The allowlist approach guarantees that
      # unrelated entries added to Secrets.psd1 (PULLSETUP / IISPULLAPP for the DSC pull
      # server, SQL / OOS / monitoring accounts, etc.) never leak into the SPS MOF.
      $spManagedAccountNames = if ($ConfigurationData.NonNodeData.SharePoint.ManagedAccounts) {
        $ConfigurationData.NonNodeData.SharePoint.ManagedAccounts
      }
      else {
        @('FARM', 'IISAPP', 'SEARCH')
      }
      $spManagedAccounts = $secretsData.serviceAccounts | Where-Object -FilterScript {
        $spManagedAccountNames -contains $_.Name
      }
      foreach ($spManagedAccount in $spManagedAccounts) {
        $name = $spManagedAccount.Name
        $username = "$($spManagedAccount.UserName)"
        $password = ConvertTo-SecureString $spManagedAccount.Password -AsPlainText -Force
        $credential = New-Object -TypeName System.Management.Automation.PSCredential `
          -ArgumentList $username, $password

        SPManagedAccount ('APPLICATION_SpsManagedAccount_' + $name) {
          DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
          Ensure               = 'Present'
          AccountName          = $username
          Account              = $credential
          PsDscRunAsCredential = $SETUP
        }
      }
      # Add Certificates for SPWebApplication
      # Skip non-SharePoint certs: DSC pull-server, Office Online Server, and SQL Server certs are
      # imported elsewhere (DscPull/OfficeOnline by their own Node blocks; SQL by CfgAppSql).
      $spCertificates = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -ne 'OfficeOnlineCert' -and `
          $_.Name -ne 'SQLServerCert' -and `
          $_.Name -ne 'DscPullCert' }
      foreach ($spCertificate in $spCertificates) {
        #Import certificate in Sharepoint
        SPCertificate "APPLICATION_SpsPFXCert_$($spCertificate.Name)" {
          CertificateFilePath  = "$($spCertificate.PfxPath)"
          PsDscRunAsCredential = $ADSETUP
          Ensure               = 'Present'
          # Per-cert PFX password: resolves the PSCredential auto-materialised by the secrets loader
          # in Secrets.psd1 (Name = $spCertificate.Name, e.g. 'SharePointCert'). Fails fast at
          # compile time if the Secrets entry is missing.
          CertificatePassword  = (Get-Variable -Name $spCertificate.Name -ValueOnly)
          Exportable           = $true
          DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        }
      }

      #Configuration of SharePoint Diagnostic Logging
      SPDiagnosticLoggingSettings APPLICATION_SpsApplyDiagLogSettings {
        DependsOn                                   = '[SPFarm]APPLICATION_SpsCreateSPFarm', '[File]APPLICATION_SpsApplyDiagLogFolder'
        PsDscRunAsCredential                        = $SETUP
        IsSingleInstance                            = 'Yes'
        LogPath                                     = "$($configurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs)"
        LogSpaceInGB                                = 20
        AppAnalyticsAutomaticUploadEnabled          = $false
        CustomerExperienceImprovementProgramEnabled = $false
        DaysToKeepLogs                              = 30
        DownloadErrorReportingUpdatesEnabled        = $false
        ErrorReportingAutomaticUploadEnabled        = $false
        ErrorReportingEnabled                       = $false
        EventLogFloodProtectionEnabled              = $false
        LogCutInterval                              = 30
        LogMaxDiskSpaceUsageEnabled                 = $true
        ScriptErrorReportingDelay                   = 30
        ScriptErrorReportingEnabled                 = $true
        ScriptErrorReportingRequireAuth             = $true
      }
      # Add SharePoint Service Application Pool
      SPServiceAppPool APPLICATION_SpsSvcAppMainServiceAppPool {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = $ConfigurationData.NonNodeData.SharePoint.ServiceAppPoolName
        Ensure               = 'Present'
        ServiceAccount       = $IISAPP.UserName
      }
      # Add SharePoint State Service Application
      SPStateServiceApp APPLICATION_SpsSvcAppStateServiceApp {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.StateService.Name
        Ensure               = 'Present'
        DatabaseServer       = $sqlAliasSVC.ServerAlias
        DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.Services.StateService.DatabaseName
      }
      # Add SharePoint Session State Service Application
      SPSessionStateService APPLICATION_SpsSvcAppSessionStateServiceApp {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.Services.SessionState.DatabaseName
        DatabaseServer       = $sqlAliasSVC.ServerAlias
        Ensure               = 'Present'
      }
      # Add SharePoint Usage Service Application
      SPUsageApplication APPLICATION_SpsSvcAppUsageServiceApp {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.UsageService.Name
        DatabaseServer       = $sqlAliasSVC.ServerAlias
        DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.Services.UsageService.DatabaseName
        UsageLogCutTime      = 5
        UsageLogMaxSpaceGB   = 5
        UsageLogLocation     = "$($configurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.SharePoint.UsageLogs)"
      }
      #Distributed Cache Service Configuration
      if ($null -eq $Node.CacheSize) {
        $dcCacheSizeInMB = 1024
      }
      else {
        $dcCacheSizeInMB = $Node.CacheSize
      }
      if ($Node.IsAFCache) {
        SPDistributedCacheService APPLICATION_SpsEnableDistributedCache {
          DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
          PsDscRunAsCredential = $SETUP
          Name                 = 'AppFabricCachingService'
          Ensure               = 'Present'
          CacheSizeInMB        = $dcCacheSizeInMB
          ServiceAccount       = $IISAPP.UserName
          CreateFirewallRules  = $true
        }
      }
      else {
        SPDistributedCacheService APPLICATION_SpsEnableDistributedCache {
          DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
          PsDscRunAsCredential = $SETUP
          Name                 = 'AppFabricCachingService'
          Ensure               = 'Absent'
          CacheSizeInMB        = $dcCacheSizeInMB
          ServiceAccount       = $IISAPP.UserName
          CreateFirewallRules  = $true
        }
      }
      #Outgoing Email Settings for Central Administration Web Application
      SPOutgoingEmailSettings APPLICATION_OutgoingEmailCA {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        WebAppUrl            = "http://$($Node.NodeName):$($ConfigurationData.NonNodeData.SharePoint.CentralAdministrationPort)"
        CharacterSet         = $ConfigurationData.NonNodeData.SharePoint.MailSettings.CharacterSet
        SMTPServer           = $ConfigurationData.NonNodeData.SharePoint.MailSettings.SMTPServer
        ReplyToAddress       = $ConfigurationData.NonNodeData.SharePoint.MailSettings.ReplyToAddress
        FromAddress          = $ConfigurationData.NonNodeData.SharePoint.MailSettings.FromAddress
      }
      <#Configure CEIP Data Collection SPTimerJob
  Name                    TypeName
  ----                    --------
  job-static-ceip         Microsoft.Office.Server.Diagnostics.StaticSqmDataCollectionJob
  job-ceip-datacollection Microsoft.SharePoint.Administration.SPSqmTimerJobDefinition#>
      SPTimerJobState APPLICATION_CEIPStaticJobDefinition {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        TypeName             = 'Microsoft.Office.Server.Diagnostics.StaticSqmDataCollectionJob'
        Schedule             = 'daily between 00:00:00 and 00:00:00'
        WebAppUrl            = 'N/A'
        Enabled              = $false
      }
      SPTimerJobState APPLICATION_CEIPDataCollectionJobDefinition {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        TypeName             = 'Microsoft.SharePoint.Administration.SPSqmTimerJobDefinition'
        Schedule             = 'daily between 04:30:00 and 04:30:00'
        WebAppUrl            = 'N/A'
        Enabled              = $false
      }
      #Health Analyzer Rule Configuration
      SPHealthAnalyzerRuleState APPLICATION_SPHealthRuleDisableAppPoolAccountAdmin {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = 'Accounts used by application pools or service identities are in the local machine Administrators group.'
        Enabled              = $False
      }
      SPHealthAnalyzerRuleState APPLICATION_SPHealthRuleDisableBuiltInAccounts {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = 'Built-in accounts are used as application pool or service identities.'
        Enabled              = $False
      }
      #Initialize variables for all Service Applications and all Web Applications
      $sqlAliasSVC = $ConfigurationData.NonNodeData.SQLAlias | Where-Object -FilterScript { $_.Name -eq 'SERVICES' }
      $sqlAliasWEB = $ConfigurationData.NonNodeData.SQLAlias | Where-Object -FilterScript { $_.Name -eq 'CONTENT' }
      $uspSvcAppName = $ConfigurationData.NonNodeData.SharePoint.Services.UserProfile.Name
      $mmsSvcAppName = $ConfigurationData.NonNodeData.SharePoint.Services.ManagedMetadataService.Name
      $mySiteHostLocation = $ConfigurationData.NonNodeData.SharePoint.Services.UserProfile.MySiteHostLocation
      $superUserServiceAccount = $serviceAccounts | Where-Object -FilterScript { $_.Name -eq 'SUPERUSER' }
      $superReaderServiceAccount = $serviceAccounts | Where-Object -FilterScript { $_.Name -eq 'SUPEREADER' }

      # Add SharePoint Managed Metadata Service Application
      SPManagedMetaDataServiceApp APPLICATION_SpsSvcAppManagedMetadataServiceApp {
        DependsOn                     = '[SPServiceAppPool]APPLICATION_SpsSvcAppMainServiceAppPool', `
          '[SqlAlias]MIDDLEWARE_SqlAlias_SERVICES'
        PsDscRunAsCredential          = $SETUP
        Name                          = $mmsSvcAppName
        ProxyName                     = $mmsSvcAppName
        ApplicationPool               = $ConfigurationData.NonNodeData.SharePoint.ServiceAppPoolName
        DatabaseServer                = $sqlAliasSVC.ServerAlias
        DatabaseName                  = $ConfigurationData.NonNodeData.SharePoint.Services.ManagedMetadataService.DatabaseName
        Ensure                        = 'Present'
        DefaultLanguage               = 1036
        Languages                     = @(1033, 1036)
        ContentTypePushdownEnabled    = $true
        ContentTypeSyndicationEnabled = $true
      }
      SPManagedMetaDataServiceAppDefault APPLICATION_SpsSvcAppManagedMetadataServiceAppDefault {
        DependsOn                      = '[SPManagedMetaDataServiceApp]APPLICATION_SpsSvcAppManagedMetadataServiceApp'
        PsDscRunAsCredential           = $SETUP
        ServiceAppProxyGroup           = 'default'
        DefaultSiteCollectionProxyName = $mmsSvcAppName
        DefaultKeywordProxyName        = $mmsSvcAppName
      }

      # Add each web application from configuration data file
      $spWebApps = $ConfigurationData.NonNodeData.SharePoint.WebApplications
      foreach ($spWebApp in $spWebApps) {
        # Get certificate information via the WebApp.CertName indirection so the descriptive WebApp
        # name (e.g. 'SharePoint') can differ from the cert/Secrets entry name (e.g. 'SharePointCert').
        $getCertInfo = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -eq "$($spWebApp.CertName)" }
        #Retrieve the certificate Thumprint from CertPath
        try {
          $getSPCertificate = Get-CertThumbprint -CertPath "$($getCertInfo.CertPath)"
        }
        catch {
          Write-Error "Failed to retrieve the certificate: $_"
          throw
        }

        if ($null -eq $spWebApp.HostHeader) {
          SPWebApplication "APPLICATION_SpsWebApplication_$($spWebApp.Name)" {
            DependsOn               = '[SPManagedMetaDataServiceApp]APPLICATION_SpsSvcAppManagedMetadataServiceApp'
            PsDscRunAsCredential    = $SETUP
            Name                    = "$($spWebApp.Name)"
            ApplicationPool         = "$($spWebApp.ApplicationPool)"
            ApplicationPoolAccount  = $IISAPP.UserName
            AllowAnonymous          = $false
            DatabaseName            = "$($spWebApp.ContentDBName)"
            DatabaseServer          = $sqlAliasWEB.ServerAlias
            WebAppUrl               = "$($spWebApp.Url)"
            Ensure                  = 'Present'
            Path                    = "$($spWebApp.Path)"
            Port                    = $spWebApp.Port
            CertificateThumbprint   = "$($getSPCertificate.Thumbprint)"
            UseServerNameIndication = $false
          }
        }
        else {
          SPWebApplication "APPLICATION_SpsWebApplication_$($spWebApp.Name)" {
            DependsOn               = '[SPManagedMetaDataServiceApp]APPLICATION_SpsSvcAppManagedMetadataServiceApp'
            PsDscRunAsCredential    = $SETUP
            Name                    = "$($spWebApp.Name)"
            ApplicationPool         = "$($spWebApp.ApplicationPool)"
            ApplicationPoolAccount  = $IISAPP.UserName
            AllowAnonymous          = $false
            DatabaseName            = "$($spWebApp.ContentDBName)"
            DatabaseServer          = $sqlAliasWEB.ServerAlias
            WebAppUrl               = "$($spWebApp.Url)"
            HostHeader              = "$($spWebApp.HostHeader)"
            Ensure                  = 'Present'
            Path                    = "$($spWebApp.Path)"
            Port                    = $spWebApp.Port
            CertificateThumbprint   = "$($getSPCertificate.Thumbprint)"
            UseServerNameIndication = $true
          }
        }
        #Configure SharePoint Designer Settings
        SPDesignerSettings "APPLICATION_SpsWebAppDesignerSettings_$($spWebApp.Name)" {
          DependsOn                              = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
          PsDscRunAsCredential                   = $SETUP
          SettingsScope                          = 'WebApplication'
          AllowSharePointDesigner                = $False
          AllowDetachPagesFromDefinition         = $False
          AllowCustomiseMasterPage               = $False
          WebAppUrl                              = $mySiteHostLocation
          AllowCreateDeclarativeWorkflow         = $False
          AllowSavePublishDeclarativeWorkflow    = $False
          AllowSaveDeclarativeWorkflowAsTemplate = $False
          AllowManageSiteURLStructure            = $False
        }
        #Cache Account Settings for SPWebApplication
        SPCacheAccounts "APPLICATION_SpsWebAppCacheAccounts_$($spWebApp.Name)" {
          DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
          PsDscRunAsCredential = $SETUP
          WebAppUrl            = "$($spWebApp.Url)"
          SuperUserAlias       = $superUserServiceAccount.UserName
          SuperReaderAlias     = $superReaderServiceAccount.UserName
        }
        #Configure SharePoint Web Application Policies Permissions
        SPWebAppPolicy "APPLICATION_SpsWebAppPolicy_$($spWebApp.Name)" {
          DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
          PsDscRunAsCredential = $SETUP
          WebAppUrl            = "$($spWebApp.Url)"
          MembersToInclude     = @(
            @(MSFT_SPWebPolicyPermissions {
                Username           = $Content.UserName
                PermissionLevel    = 'Full Read'
                ActAsSystemAccount = $false
              }
            )
            @(MSFT_SPWebPolicyPermissions {
                Username        = $SETUP.UserName
                PermissionLevel = 'Full Control'
                IdentityType    = 'Claims'
              }
            )
            @(MSFT_SPWebPolicyPermissions {
                Username        = $ADSETUP.UserName
                PermissionLevel = 'Full Control'
                IdentityType    = 'Claims'
              }
            )
          )
        }
        # If Forms Based Authentication is enabled for the web application, configure it
        if ($spWebApp.FormsAuth) {
          SPWebAppAuthentication "APPLICATION_SpsWebApplicationFBA_$($spWebApp.Name)" {
            DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
            PsDscRunAsCredential = $SETUP
            WebAppUrl            = "$($spWebApp.Url)"
            Default              = @(
              MSFT_SPWebAppAuthenticationMode {
                AuthenticationMethod = 'FBA'
                MembershipProvider   = 'FBAMembershipProvider'
                RoleProvider         = 'FBARoleProvider'
              }
              MSFT_SPWebAppAuthenticationMode {
                AuthenticationMethod = 'WindowsAuthentication'
                WindowsAuthMethod    = 'NTLM'
              }
            )
          }
        }
        #SharePoint outgoing email settings for web application
        SPOutgoingEmailSettings "APPLICATION_OutgoingEmai_$($spWebApp.Name)" {
          DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
          PsDscRunAsCredential = $SETUP
          WebAppUrl            = "$($spWebApp.Url)"
          CharacterSet         = $ConfigurationData.NonNodeData.SharePoint.MailSettings.CharacterSet
          SMTPServer           = $ConfigurationData.NonNodeData.SharePoint.MailSettings.SMTPServer
          ReplyToAddress       = $ConfigurationData.NonNodeData.SharePoint.MailSettings.ReplyToAddress
          FromAddress          = $ConfigurationData.NonNodeData.SharePoint.MailSettings.FromAddress
        }
        # Add SharePoint managed path if needed
        if (($spWebApp.ManagedPath).Count -ne 0) {
          foreach ($spManagedPath in $spWebApp.ManagedPath) {
            SPManagedPath "APPLICATION_SPSWebAppManagedPath_$($spManagedPath.Name)" {
              DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
              PsDscRunAsCredential = $SETUP
              Ensure               = 'Present'
              Explicit             = $spManagedPath.Explicit
              HostHeader           = $spManagedPath.HostHeader
              WebAppUrl            = "$($spWebApp.Url)"
              RelativeUrl          = $spManagedPath.RelativeUrl
            }
          }
        }
        # Add SharePoint Sites to create if needed
        if (($spWebApp.Sites).Count -ne 0) {
          foreach ($spSite in $spWebApp.Sites) {
            #Set WarningSiteCount and MaximumSiteCount for Content Database of each Site Collection
            SPContentDatabase "APPLICATION_SpsWebApp_$($spSite.ContentDatabase)" {
              DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)"
              PsDscRunAsCredential = $SETUP
              Ensure               = 'Present'
              Name                 = "$($spSite.ContentDatabase)"
              DatabaseServer       = $sqlAliasWEB.ServerAlias
              WebAppUrl            = "$($spWebApp.Url)"
              WarningSiteCount     = 0
              MaximumSiteCount     = 1
            }
            if ($spSite.HostHeaderWebApplication) {
              SPSite "APPLICATION_SpsWebAppSite_$($spSite.Name)" {
                DependsOn                = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)", "[SPContentDatabase]APPLICATION_SpsWebApp_$($spSite.ContentDatabase)"
                PsDscRunAsCredential     = $SETUP
                Url                      = $spSite.Url
                OwnerAlias               = $FARM.UserName
                Name                     = $spSite.Name
                Template                 = $spSite.Template
                Language                 = $spSite.Language
                ContentDatabase          = $spSite.ContentDatabase
                HostHeaderWebApplication = "$($spWebApp.Url)"
              }
            }
            else {
              SPSite "APPLICATION_SpsWebAppSite_$($spSite.Name)" {
                DependsOn            = "[SPWebApplication]APPLICATION_SpsWebApplication_$($spWebApp.Name)", "[SPContentDatabase]APPLICATION_SpsWebApp_$($spSite.ContentDatabase)"
                PsDscRunAsCredential = $SETUP
                Url                  = $spSite.Url
                OwnerAlias           = $FARM.UserName
                Name                 = $spSite.Name
                Template             = $spSite.Template
                Language             = $spSite.Language
                ContentDatabase      = $spSite.ContentDatabase
              }
            }
          }
        }
      }
      # Add App Management Service Application and subscription settings Service Application
      SPAppManagementServiceApp APPLICATION_SpsSvcAppAppManagementServiceApp {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm', '[SqlAlias]MIDDLEWARE_SqlAlias_SERVICES'
        PsDscRunAsCredential = $SETUP
        Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.AppManagementService.Name
        ProxyName            = $ConfigurationData.NonNodeData.SharePoint.Services.AppManagementService.Name
        ApplicationPool      = $ConfigurationData.NonNodeData.SharePoint.ServiceAppPoolName
        DatabaseServer       = $sqlAliasSVC.ServerAlias
        DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.Services.AppManagementService.DatabaseName
        Ensure               = 'Present'
      }
      # Add SharePoint User Profile Service Application
      SPUserProfileServiceApp APPLICATION_SpsSvcAppUserProfileServiceApp {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm', '[SqlAlias]MIDDLEWARE_SqlAlias_SERVICES', "[SPSite]APPLICATION_SpsWebAppSite_MySiteHost"
        PsDscRunAsCredential = $SETUP
        Name                 = $uspSvcAppName
        ProxyName            = $uspSvcAppName
        ApplicationPool      = $ConfigurationData.NonNodeData.SharePoint.ServiceAppPoolName
        MySiteHostLocation   = $mySiteHostLocation
        ProfileDBName        = $ConfigurationData.NonNodeData.SharePoint.Services.UserProfile.ProfileDBName
        ProfileDBServer      = $sqlAliasSVC.ServerAlias
        SocialDBName         = $ConfigurationData.NonNodeData.SharePoint.Services.UserProfile.SocialDBName
        SocialDBServer       = $sqlAliasSVC.ServerAlias
        SyncDBName           = $ConfigurationData.NonNodeData.SharePoint.Services.UserProfile.SyncDBName
        SyncDBServer         = $sqlAliasSVC.ServerAlias
        Ensure               = 'Present'
        NoILMUsed            = $true
      }
      #Manage Managed Metadata Service Application Permissions
      $membersToIncludeMMS = @()
      $membersToIncludeMMS += MSFT_SPServiceAppSecurityEntry {
        Username     = $FARM.UserName
        AccessLevels = 'Full Access to Term Store'
      }
      $membersToIncludeMMS += MSFT_SPServiceAppSecurityEntry {
        Username     = $SETUP.UserName
        AccessLevels = 'Full Access to Term Store'
      }
      SPServiceAppSecurity APPLICATION_ServiceAppSecurity_MMS_SharingPermissions {
        DependsOn            = '[SPManagedMetaDataServiceApp]APPLICATION_SpsSvcAppManagedMetadataServiceApp'
        ServiceAppName       = $mmsSvcAppName
        SecurityType         = 'SharingPermissions'
        MembersToInclude     = $membersToIncludeMMS
        PsDscRunAsCredential = $SETUP
      }
      #Manage User Profile Service Application Permissions
      $membersToIncludeUSP = @()
      $membersToIncludeUSP += MSFT_SPServiceAppSecurityEntry {
        Username     = $FARM.UserName
        AccessLevels = 'Full Control'
      }
      $membersToIncludeUSP += MSFT_SPServiceAppSecurityEntry {
        Username     = $Content.UserName
        AccessLevels = 'Full Control'
      }
      $membersToIncludeUSP += MSFT_SPServiceAppSecurityEntry {
        Username     = $IISAPP.UserName
        AccessLevels = 'Full Control'
      }
      $membersToIncludeUSP += MSFT_SPServiceAppSecurityEntry {
        Username     = $SETUP.UserName
        AccessLevels = 'Full Control'
      }
      $svcSecurityTypes = @('SharingPermissions', 'Administrators')
      foreach ($svcSecurityType in $svcSecurityTypes) {
        SPServiceAppSecurity ('APPLICATION_ServiceAppSecurity_USP_' + $svcSecurityType) {
          DependsOn            = '[SPUserProfileServiceApp]APPLICATION_SpsSvcAppUserProfileServiceApp'
          ServiceAppName       = $uspSvcAppName
          SecurityType         = $svcSecurityType
          MembersToInclude     = $membersToIncludeUSP
          PsDscRunAsCredential = $SETUP
        }
      }
      # Add Subscription Settings Service Application
      SPSubscriptionSettingsServiceApp APPLICATION_SpsSvcAppSubscriptionSettingsServiceApp {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm', '[SqlAlias]MIDDLEWARE_SqlAlias_SERVICES'
        PsDscRunAsCredential = $SETUP
        Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.SubscriptionSettingsService.Name
        ApplicationPool      = $ConfigurationData.NonNodeData.SharePoint.ServiceAppPoolName
        DatabaseServer       = $sqlAliasSVC.ServerAlias
        DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.Services.SubscriptionSettingsService.DatabaseName
        Ensure               = 'Present'
      }
      #Set App Catalog URL for App Management Service Application
      SPAppCatalog APPLICATION_SpsSvcMainAppCatalog {
        DependsOn            = '[SPAppManagementServiceApp]APPLICATION_SpsSvcAppAppManagementServiceApp'
        SiteUrl              = $ConfigurationData.NonNodeData.SharePoint.Services.AppManagementService.AppCatalogUrl
        PsDscRunAsCredential = $SETUP
      }
      #Initialize variables for Office Online Server configuration
      $oosCertInfo = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -eq 'OfficeOnlineCert' }
      # Add Office Online Server Certificate in SPTrustedRootAuthority
      SPTrustedRootAuthority APPLICATION_AddOOSTrustedRootAuthority {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        Name                 = 'OOS'
        CertificateFilePath  = "$($oosCertInfo.CertPath)"
        Ensure               = 'Present'
        PsDscRunAsCredential = $ADSETUP
      }
      #OfficeOnlineServer | Add WOPIBINDING
      SPOfficeOnlineServerBinding APPLICATION_CreateWOPIBinding {
        DependsOn            = "[SPTrustedRootAuthority]APPLICATION_AddOOSTrustedRootAuthority"
        PsDscRunAsCredential = $SETUP
        DnsName              = "$($ConfigurationData.NonNodeData.OOS.URL)"
        Ensure               = 'Present'
        Zone                 = 'External-HTTPS'
      }
      #OfficeOnlineServer | Remove PDF file type
      SPOfficeOnlineServerSupressionSettings APPLICATION_OOSRemovePDFExtension {
        DependsOn            = '[SPOfficeOnlineServerBinding]APPLICATION_CreateWOPIBinding'
        PsDscRunAsCredential = $SETUP
        Ensure               = 'Present'
        Extension            = 'pdf'
        Actions              = 'edit', 'view'
      }
      # Configure Service Account for Search Service and Search Host Controller Service
      SPServiceIdentity APPLICATION_SpsSvcAppSearchService {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = 'SharePoint Server Search'
        ManagedAccount       = "$($SEARCH.UserName)"
      }
      SPServiceIdentity APPLICATION_SpsSvcAppSearchHostController {
        DependsOn            = '[SPFarm]APPLICATION_SpsCreateSPFarm'
        PsDscRunAsCredential = $SETUP
        Name                 = 'Search Host Controller Service'
        ManagedAccount       = "$($SEARCH.UserName)"
      }
      Log APPLICATION_SPSMaster_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = 'SharePoint Master Configuration Completed'
        DependsOn = '[SPAppCatalog]APPLICATION_SpsSvcMainAppCatalog'
      }
    }

    #For All SharePoint servers NON MASTER
    # Selector: match nodes that have IsSPSServer set AND IsMaster either absent or explicitly $false.
    # Using `-not $_.IsMaster` rather than `$_.IsMaster -eq $false`, because `$null -eq $false` is
    # $False in PowerShell, so the old form would silently drop nodes whose IsMaster key is missing.
    Node $AllNodes.Where{ ($_.IsSPSServer) -and (-not $_.IsMaster) }.NodeName {
      # Wait for the Master SharePoint server to complete configuration before configuring Search Service Application on Search Master
      WaitForAll PROCESS_SPSWaitForWebApp {
          PsDscRunAsCredential = $SETUP
          ResourceName         = '[Log]APPLICATION_SPSMaster_Completed'
          NodeName             = $SPSMaster
          RetryIntervalSec     = 60
          RetryCount           = 180
      }
      #New SPFarm Object
      $sqlAliasADM = $ConfigurationData.NonNodeData.SQLAlias | Where-Object -FilterScript { $_.Name -eq 'ADMIN' }
      SPFarm APPLICATION_SpsJoinSPFarm {
        DependsOn                    = '[SqlAlias]MIDDLEWARE_SqlAlias_ADMIN', '[SPProductUpdate]APPLICATION_SpsCumulativeUpdateUberInstallation'
        PsDscRunAsCredential         = $SETUP
        Ensure                       = 'Present'
        IsSingleInstance             = 'Yes'
        DatabaseServer               = $sqlAliasADM.ServerAlias
        FarmConfigDatabaseName       = "$($ConfigurationData.NonNodeData.SharePoint.FarmConfigDatabaseName)"
        Passphrase                   = $PassPhrase
        FarmAccount                  = $FARM
        AdminContentDatabaseName     = "$($ConfigurationData.NonNodeData.SharePoint.AdminContentDatabaseName)"
        CentralAdministrationPort    = "$($ConfigurationData.NonNodeData.SharePoint.CentralAdministrationPort)"
        RunCentralAdmin              = $false
        ServerRole                   = $Node.SPServerRole
        DatabaseConnectionEncryption = 'Optional'
      }
      #Distributed Cache Service Configuration
      if ($null -eq $Node.CacheSize) {
        $dcCacheSizeInMB = 1024
      }
      else {
        $dcCacheSizeInMB = $Node.CacheSize
      }
      if ($Node.IsAFCache) {
        SPDistributedCacheService APPLICATION_SpsEnableDistributedCache {
          DependsOn            = '[SPFarm]APPLICATION_SpsJoinSPFarm'
          PsDscRunAsCredential = $SETUP
          Name                 = 'AppFabricCachingService'
          Ensure               = 'Present'
          CacheSizeInMB        = $dcCacheSizeInMB
          ServiceAccount       = $IISAPP.UserName
          CreateFirewallRules  = $true
        }
      }
      else {
        SPDistributedCacheService APPLICATION_SpsEnableDistributedCache {
          DependsOn            = '[SPFarm]APPLICATION_SpsJoinSPFarm'
          PsDscRunAsCredential = $SETUP
          Name                 = 'AppFabricCachingService'
          Ensure               = 'Absent'
          CacheSizeInMB        = $dcCacheSizeInMB
          ServiceAccount       = $IISAPP.UserName
          CreateFirewallRules  = $false
        }
      }
      Log APPLICATION_SPSNoMaster_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = '[SPFarm]Join SharePoint Farm Completed'
        DependsOn = '[SPFarm]APPLICATION_SpsJoinSPFarm'
      }
    }

    #For All SharePoint servers SEARCH MASTER
    Node $SPSSearchMaster {
      # Initialize the SQL Server Alias variable for the Search Service
      $searchCenterUrl = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.SearchCenterUrl
      $sqlAliasSCH = $ConfigurationData.NonNodeData.SQLAlias | Where-Object -FilterScript { $_.Name -eq 'SEARCH' }
      if ($Node.IsMaster) {
        $dependsOnForSearchApp = '[Log]APPLICATION_SPSMaster_Completed'
      }
      else {
        # Default branch: non-master Search node depends on the join-farm log raised in the non-master Node block.
        $dependsOnForSearchApp = '[Log]APPLICATION_SPSNoMaster_Completed'
      }
      #Define CrawlSchedules for User Profile Content Source
      $CrawlSchedules = @{
        EverySundayAt6AM = @{
          ScheduleType                  = "Weekly"
          StartHour                     = '6'
          StartMinute                   = '0'
          CrawlScheduleRunEveryInterval = '1'
          CrawlScheduleDaysOfWeek       = 'Sunday'
        }
        Every15Min       = @{
          ScheduleType                  = "Daily"
          StartHour                     = '6'
          StartMinute                   = '0'
          CrawlScheduleRunEveryInterval = '1'
          CrawlScheduleRepeatInterval   = '15'
          CrawlScheduleRepeatDuration   = '960'
        }
      }
      # Add SharePoint Search Service Application
      SPSearchServiceApp APPLICATION_SpsSvcAppSearchServiceApp {
        DependsOn                   = $dependsOnForSearchApp
        PsDscRunAsCredential        = $SETUP
        ApplicationPool             = $ConfigurationData.NonNodeData.SharePoint.ServiceAppPoolName
        Name                        = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Name
        ProxyName                   = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Name
        DatabaseName                = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.DatabaseName
        DatabaseServer              = $sqlAliasSCH.ServerAlias
        DefaultContentAccessAccount = $Content
        Ensure                      = 'Present'
        SearchCenterUrl             = $searchCenterUrl
      }
      # Add Permissions on SharePoint Search Service Application
      $membersToIncludeUSP = @()
      $membersToIncludeUSP += MSFT_SPServiceAppSecurityEntry {
        Username     = "$($FARM.UserName)"
        AccessLevels = 'Full Control'
      }
      $membersToIncludeUSP += MSFT_SPServiceAppSecurityEntry {
        Username     = "$($SETUP.UserName)"
        AccessLevels = 'Full Control'
      }

      $schSecurityTypes = @('SharingPermissions', 'Administrators')
      foreach ($schSecurityType in $schSecurityTypes) {
        SPServiceAppSecurity ('APPLICATION_ServiceAppSecurity_SCH_' + $schSecurityType) {
          DependsOn            = '[SPSearchServiceApp]APPLICATION_SpsSvcAppSearchServiceApp'
          ServiceAppName       = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Name
          SecurityType         = $schSecurityType
          MembersToInclude     = $membersToIncludeUSP
          PsDscRunAsCredential = $SETUP
        }
      }
      # Add SharePoint Search Service Application Topology
      SPSearchTopology APPLICATION_SpsSvcSearchTopo {
        DependsOn               = '[SPSearchServiceApp]APPLICATION_SpsSvcAppSearchServiceApp'
        PsDscRunAsCredential    = $SETUP
        ServiceAppName          = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Name
        Admin                   = $AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -eq "Search" -and $_.IsSrcAdmin }.Nodename
        Crawler                 = $AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -eq "Search" -and $_.IsSrcCrawl }.Nodename
        ContentProcessing       = $AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -eq "Search" -and $_.IsCntProc }.Nodename
        AnalyticsProcessing     = $AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -eq "Search" -and $_.IsSrcAnalyt }.Nodename
        QueryProcessing         = $AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -eq "Search" -and $_.IsSrcQuery }.Nodename
        IndexPartition          = $AllNodes.Where{ $_.IsSPSServer -and $_.SPServerRole -eq "Search" -and $_.IsIndexPart }.Nodename
        FirstPartitionDirectory = "$($ConfigurationData.NonNodeData.Drives.Data)\$($ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Topology.FirstPartitionDirectory)"
      }
      # Add SharePoint Search content sources
      SPSearchContentSource APPLICATION_SpsSvcSearchContentSourceSPSites {
        DependsOn            = '[SPSearchTopology]APPLICATION_SpsSvcSearchTopo'
        PsDscRunAsCredential = $SETUP
        Ensure               = 'Present'
        ContentSourceType    = 'SharePoint'
        ServiceAppName       = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Name
        Addresses            = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.ContentSources.LocalSharePointsites.StartAddresses
        ContinuousCrawl      = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.ContentSources.LocalSharePointsites.ContinuousCrawl
        Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.ContentSources.LocalSharePointsites.Name
        Priority             = 'Normal'
        CrawlSetting         = 'CrawlVirtualServers'
      }
      # Add SharePoint Search content sources
      SPSearchContentSource APPLICATION_SpsSvcSearchContentSourceProfile {
        DependsOn            = '[SPSearchTopology]APPLICATION_SpsSvcSearchTopo'
        PsDscRunAsCredential = $SETUP
        Ensure               = 'Present'
        ContentSourceType    = 'SharePoint'
        ServiceAppName       = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.Name
        IncrementalSchedule  = MSFT_SPSearchCrawlSchedule {
          ScheduleType                  = $CrawlSchedules.Every15Min.ScheduleType
          StartHour                     = $CrawlSchedules.Every15Min.StartHour
          StartMinute                   = $CrawlSchedules.Every15Min.StartMinute
          CrawlScheduleRunEveryInterval = $CrawlSchedules.Every15Min.CrawlScheduleRunEveryInterval
          CrawlScheduleRepeatInterval   = $CrawlSchedules.Every15Min.CrawlScheduleRepeatInterval
          CrawlScheduleRepeatDuration   = $CrawlSchedules.Every15Min.CrawlScheduleRepeatDuration
        }
        FullSchedule         = MSFT_SPSearchCrawlSchedule {
          ScheduleType                  = $CrawlSchedules.EverySundayAt6AM.ScheduleType
          StartHour                     = $CrawlSchedules.EverySundayAt6AM.StartHour
          StartMinute                   = $CrawlSchedules.EverySundayAt6AM.StartMinute
          CrawlScheduleRunEveryInterval = $CrawlSchedules.EverySundayAt6AM.CrawlScheduleRunEveryInterval
          CrawlScheduleDaysOfWeek       = $CrawlSchedules.EverySundayAt6AM.CrawlScheduleDaysOfWeek
        }
        Addresses            = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.ContentSources.SharePointProfile.StartAddresses
        Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.SearchService.ContentSources.SharePointProfile.Name
        Priority             = 'Normal'
        CrawlSetting         = 'CrawlVirtualServers'
      }
      Log APPLICATION_SPSearchServiceApp_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = '[SPSearchServiceApp]SharePoint Search Service App Configuration Completed'
        DependsOn = '[SPSearchContentSource]APPLICATION_SpsSvcSearchContentSourceProfile'
      }
    }

    #For All Office Online servers
    Node $AllNodes.Where{ ($_.IsOOSServer) }.NodeName {
      # OOS servers are always domain-joined member servers in this kit (the AD DC
      # is provisioned by CfgAppPdc.ps1, never co-located on an OOS box). Join the
      # domain, then reboot before anything else runs on the node.
      Computer JoinDomain {
        Name       = $Node.NodeName
        DomainName = $ConfigurationData.NonNodeData.DomainName
        Credential = $ADSETUP
      }

      PendingReboot RebootOnSignalFromJoinDomain {
        Name             = "RebootOnSignalFromJoinDomain"
        SkipCcmClientSDK = $true
        DependsOn        = "[Computer]JoinDomain"
      }
      $dependsOnSPSSetup = '[PendingReboot]RebootOnSignalFromJoinDomain'
      Group AddSPSetupAccountToAdminGroup {
        GroupName            = "Administrators"
        Ensure               = "Present"
        MembersToInclude     = $Node.LocalAdmins
        Credential           = $ADSETUP
        PsDscRunAsCredential = $ADSETUP
        DependsOn            = $dependsOnSPSSetup
      }
      #Initialize path variables.
      # Resolution is delegated to Resolve-ProductPaths so customers can override
      # NonNodeData.OOS.SourcePath / .DestinationPath / .Subfolders.* in their .psd1
      # without touching the configuration script. Defaults preserve the original layout:
      #   <SourcePath>\OOS  /  <Drives.Data>\SoftwarePackages\OOS  with BIN / LP / CU subfolders.
      $oosPaths = Resolve-ProductPaths `
        -ProductConfig    $ConfigurationData.NonNodeData.OOS `
        -SourceRoot       $ConfigurationData.NonNodeData.SourcePath `
        -DestinationRoot  (Join-Path $ConfigurationData.NonNodeData.Drives.Data 'SoftwarePackages') `
        -DefaultSubFolder 'OOS'
      #Install Office Online Server Prerequisites
      $requiredFeatures = @(
        'Web-Server', 'Web-Mgmt-Tools', 'Web-Mgmt-Console', 'Web-WebServer',
        'Web-Common-Http', 'Web-Default-Doc', 'Web-Static-Content', 'Web-Performance',
        'Web-Stat-Compression', 'Web-Dyn-Compression', 'Web-Security', 'Web-Filtering',
        'Web-Windows-Auth', 'Web-App-Dev', 'Web-Net-Ext45', 'Web-Asp-Net45',
        'Web-ISAPI-Ext', 'Web-ISAPI-Filter', 'Web-Includes',
        'Windows-Identity-Foundation', 'Server-Media-Foundation'
      )
      foreach ($feature in $requiredFeatures) {
        WindowsFeature "WindowsFeature-$feature" {
          Ensure = 'Present'
          Name   = $feature
        }
      }
      $prereqDependencies = $requiredFeatures | ForEach-Object -Process {
        return "[WindowsFeature]WindowsFeature-$_"
      }
      #IIS clean up
      $appPoolToRemove = @('.NET v2.0', '.NET v2.0 Classic', '.NET v4.5', '.NET v4.5 Classic', 'Classic .NET AppPool', 'DefaultAppPool')
      foreach ($appPool in $appPoolToRemove) {
        WebAppPool ('MIDDLEWARE_' + $appPool.Replace(' ', '')) {
          DependsOn = $prereqDependencies
          Ensure    = 'Absent'
          Name      = $appPool
        }
      }
      WebSite MIDDLEWARE_RemoveDefaultWebSite {
        DependsOn    = $prereqDependencies
        Ensure       = 'Absent'
        Name         = 'Default Web Site'
        PhysicalPath = 'C:\inetpub\wwwroot'
      }
      #Configure IIS logging
      File MIDDLEWARE_IIS-LogFolder {
        DependsOn       = $prereqDependencies
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.LogFolder)"
      }
      IisLogging MIDDLEWARE_IIS-ConfigureLogFolder {
        DependsOn = '[File]MIDDLEWARE_IIS-LogFolder'
        LogPath   = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.LogFolder)"
      }

      #Configure IIS HTTPERR
      File MIDDLEWARE_IIS-LogFolderHTTPERR {
        DependsOn       = $prereqDependencies
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.httpErrFolder)"
      }
      Registry MIDDLEWARE_IIS-RegLogFolderHTTPERR {
        DependsOn = '[File]MIDDLEWARE_IIS-LogFolderHTTPERR'
        Key       = 'HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\HTTP\Parameters'
        ValueName = 'ErrorLoggingDir'
        ValueType = 'String'
        ValueData = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.IIS.httpErrFolder)"
        Ensure    = 'Present'
      }
      #Get Office Online Server installation files
      File APPLICATION_OOSGetSources {
        SourcePath      = $oosPaths.Source
        DestinationPath = $oosPaths.Destination
        Ensure          = 'Present'
        Recurse         = $true
        Credential      = $ADSETUP
        MatchSource     = $true
      }
      Log APPLICATION_OOSGetSources_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = 'Finished running the file resource with ID APPLICATION_WACGetSources'
        DependsOn = '[File]APPLICATION_OOSGetSources'
      }
      #Install Office Online Server
      OfficeOnlineServerInstall APPLICATION_OOSInstallBinaries {
        Path      = (Join-Path $oosPaths.Binaries 'setup.exe')
        DependsOn = $prereqDependencies, '[File]APPLICATION_OOSGetSources'
        Ensure    = 'Present'
      }
      #Install Office Online Server Language Pack fr-FR
      OfficeOnlineServerInstallLanguagePack APPLICATION_OOSInstallLP {
        BinaryDir = (Join-Path $oosPaths.LanguagePack 'Fr-fr')
        Language  = 'fr-fr'
        DependsOn = $prereqDependencies, '[File]APPLICATION_OOSGetSources', '[OfficeOnlineServerInstall]APPLICATION_OOSInstallBinaries'
        Ensure    = 'Present'
      }
      #Install Office Online Server Updates.
      # CUFileName may be a filename (resolved under $oosPaths.CumulativeUpdate, the original
      # behaviour) or a fully-qualified path (used as-is). IsPathRooted preserves backward
      # compatibility for existing .psd1 files.
      if ($null -ne $ConfigurationData.NonNodeData.OOS.CUFileName) {
        $oosCuValue = $ConfigurationData.NonNodeData.OOS.CUFileName
        $oosCuSetupFile = if ([System.IO.Path]::IsPathRooted($oosCuValue)) {
          $oosCuValue
        }
        else {
          Join-Path $oosPaths.CumulativeUpdate $oosCuValue
        }
        OfficeOnlineServerProductUpdate APPLICATION_OOSInstallCU {
          Ensure               = 'Present'
          DependsOn            = '[OfficeOnlineServerInstallLanguagePack]APPLICATION_OOSInstallLP'
          PsDscRunAsCredential = $SETUP
          SetupFile            = $oosCuSetupFile
          Servers              = $ConfigurationData.NonNodeData.OOS.AllServers
        }
      }
      #Import Certificate to LocalMachine\My store
      $oosCertificate = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -eq 'OfficeOnlineCert' }
      #Retrieve the certificate Thumprint from CertPath
      try {
        $getOOSCertificate = Get-CertThumbprint -CertPath "$($oosCertificate.CertPath)"
      }
      catch {
        Write-Error "Failed to retrieve the certificate: $_"
        throw
      }
      PfxImport APPLICATION_OOSCertificateImport {
        DependsOn  = '[OfficeOnlineServerProductUpdate]APPLICATION_OOSInstallCU'
        Thumbprint = $getOOSCertificate.Thumbprint
        Path       = "$($oosCertificate.PfxPath)"
        Store      = 'My'
        Location   = 'LocalMachine'
        # Per-cert PFX password: resolves the PSCredential auto-materialised by the secrets loader
        # in Secrets.psd1 (Name = $oosCertificate.Name, i.e. 'OfficeOnlineCert').
        Credential = (Get-Variable -Name $oosCertificate.Name -ValueOnly)
        Exportable = $true
        Ensure     = 'Present'
      }
      #Create Office Online Server Farm or Join the Farm
      if ($Node.IsMaster) {
        #Creation de la ferme WAC
        OfficeOnlineServerFarm APPLICATION_CreateWACFarm {
          DependsOn                   = '[PfxImport]APPLICATION_OOSCertificateImport'
          InternalURL                 = "http://$($ConfigurationData.NonNodeData.OOS.URL)"
          ExternalURL                 = "https://$($ConfigurationData.NonNodeData.OOS.URL)"
          EditingEnabled              = $true
          CertificateName             = "$($oosCertificate.FriendlyName)"
          LogLocation                 = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.OOS.LogLocation)"
          CacheLocation               = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.OOS.CacheLocation)"
          RenderingLocalCacheLocation = "$($ConfigurationData.NonNodeData.Drives.Logs)\$($ConfigurationData.NonNodeData.OOS.RenderingLocalCacheLocation)"
          SSLOffloaded                = $false
          AllowHttp                   = $True
        }
      }
      else {
        #Join existing Office Online Server farm.
        # NOTE: the OOS Node block is gated on IsOOSServer (not IsWACServer); look up the master accordingly.
        $MachineToJoin = $AllNodes.Where{ $_.IsOOSServer -and $_.IsMaster }.Nodename
        OfficeOnlineServerMachine APPLICATION_JoinWACFarm {
          DependsOn     = '[PfxImport]APPLICATION_OOSCertificateImport'
          Ensure        = 'Present'
          MachineToJoin = $MachineToJoin
        }
      }
    }
  }
  #Run the CfgAppSps configuration with the provided ConfigurationData
  # Note: Import-PowerShellDataFile returns hashtables, so use ForEach-Object
  # (hashtable dot-syntax) instead of Select-Object -ExpandProperty.
  $nodeList = ($configurationData.AllNodes | Where-Object { $_.NodeName -ne '*' } | ForEach-Object { $_.NodeName }) -join ', '
  Write-Host ("[{0}] Compiling CfgAppSps for node(s) : {1}" -f (Get-Date -Format 'o'), $nodeList)
  Write-Host ("[{0}] MOF output path            : {1}" -f (Get-Date -Format 'o'), $mofOutputPath)
  CfgAppSps -ConfigurationData $ConfigurationData -OutputPath $mofOutputPath

  #Checksum the generated MOF files
  New-DscChecksum -Force -Path $mofOutputPath -Verbose
  Write-Host ("[{0}] Compilation complete." -f (Get-Date -Format 'o'))
}
catch {
  # Preserve full error context (script, line number, exception message) before rethrowing.
  Write-Error -Message ("CfgAppSps compilation failed at {0}:{1} - {2}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}
