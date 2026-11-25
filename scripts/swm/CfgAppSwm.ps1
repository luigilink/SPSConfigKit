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
  Compiles the SharePoint Workflow Manager (SWM) DSC configuration: a dedicated server that
  hosts the workflow engine used by SharePoint 2013 workflows.

  .DESCRIPTION
  Imports node + non-node data from a .psd1 file and secret material from Secrets.psd1, then
  compiles MOF files for every node defined in AllNodes. The script is idempotent: re-running it
  simply regenerates the MOFs in the output directory and refreshes the checksums.

  The configuration is built step by step. It currently covers the Local Configuration Manager,
  the common hardening shared by every node of the kit, the local administrators of the SWM
  server, the IIS prerequisites (and IIS logging), the copy of the installers from the share,
  the installation of Service Fabric, the SharePoint Workflow Manager Client and SharePoint
  Workflow Manager, the Service Bus and Workflow Manager farms, the lab CA certificate of the
  Workflow Management endpoint, and its firewall rule. The SharePoint registration is added
  next.

  The role is SharePoint Workflow Manager (SWM), not the legacy Microsoft Workflow Manager,
  which is no longer installable (support ended on 14 July 2026).

  The data disks are initialised by scripts\init\Initialize-DscDisks.ps1, not by this
  configuration.

  .PARAMETER inputFile
  Full path to the ConfigurationData .psd1. Defaults to CfgAppSwm.psd1 in the same directory as
  the script.

  .PARAMETER secretsFile
  Full path to the Secrets.psd1. Defaults to ..\Secrets.psd1 relative to the script directory.

  .PARAMETER OutputPath
  Directory where the compiled MOF files (and checksums) are written. Defaults to
  <scriptDir>\MOF. The directory is created if missing.

  .EXAMPLE
  .\CfgAppSwm.ps1

  .EXAMPLE
  .\CfgAppSwm.ps1 -inputFile .\CfgAppSwm.psd1 -secretsFile ..\Secrets.psd1 -OutputPath C:\DSC\MOF

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
    Write-Host 'No input file provided. Try to use CfgAppSwm.psd1 in the same directory as the script.'
    $inputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppSwm.psd1'
  }
  if (Test-Path $inputFile) {
    Write-Host "Importing configuration data from $inputFile"
    $configurationData = Import-PowerShellDataFile -Path $inputFile
  }
  else {
    throw "Missing $inputFile"
  }

  # Fail fast: without an IsSWMServer node the configuration would compile only the common block.
  if (-not @($configurationData.AllNodes | Where-Object { $_.IsSWMServer }).Count) {
    throw "No node carries IsSWMServer = `$True in $inputFile. Declare the SharePoint Workflow Manager node."
  }

  # Fail fast on a .psd1 that predates a setting, instead of an obscure compilation error.
  $swmSettings = $configurationData.NonNodeData.SWM
  $swmSqlAliasSetting = $configurationData.NonNodeData.SQLAlias | Where-Object { $_.Name -eq 'WORKFLOW' } | Select-Object -First 1
  $requiredSwmSettings = @{
    'LogFolder'                    = $swmSettings.LogFolder
    'ServiceFabric.FileName'       = $swmSettings.ServiceFabric.FileName
    'ServiceFabric.MinimumVersion' = $swmSettings.ServiceFabric.MinimumVersion
    'WorkflowClient.FileName'      = $swmSettings.WorkflowClient.FileName
    'WorkflowClient.ProductId'     = $swmSettings.WorkflowClient.ProductId
    'WorkflowServer.FileName'      = $swmSettings.WorkflowServer.FileName
    'WorkflowServer.ProductId'     = $swmSettings.WorkflowServer.ProductId
    'SQLAlias.ServerAlias'         = $swmSqlAliasSetting.ServerAlias
    'SQLAlias.ServerName'          = $swmSqlAliasSetting.ServerName
    'SQLAlias.InstanceName'        = $swmSqlAliasSetting.InstanceName
    'SQLAlias.Port'                = $swmSqlAliasSetting.Port
    'ServiceBus.FarmDatabase'      = $swmSettings.ServiceBus.FarmDatabase
    'ServiceBus.Namespace'         = $swmSettings.ServiceBus.Namespace
    'WorkflowManager.FarmDatabase' = $swmSettings.WorkflowManager.FarmDatabase
  }
  $missingSwmSettings = @($requiredSwmSettings.Keys | Where-Object { [string]::IsNullOrWhiteSpace($requiredSwmSettings[$_]) } | Sort-Object)
  if ($missingSwmSettings.Count) {
    throw "NonNodeData.SWM settings are missing in ${inputFile}: $($missingSwmSettings -join ', '). Update the file from the version delivered with the kit."
  }

  # DRY: derive certificate paths from the single share root (NonNodeData.SourcePath)
  # + each entry's CerFileName / PfxFileName, so the share host is defined only once.
  # An explicit CertPath / PfxPath on an entry is still honoured (backward compatible).
  $certSourcePath = $configurationData.NonNodeData.SourcePath
  if ($configurationData.NonNodeData.ADC -and $configurationData.NonNodeData.ADC.certificates) {
    foreach ($cert in $configurationData.NonNodeData.ADC.certificates) {
      $certRoot = $certSourcePath.TrimEnd('\')
      if ([string]::IsNullOrWhiteSpace($cert.CertPath) -and -not [string]::IsNullOrWhiteSpace($cert.CerFileName)) {
        $cert.CertPath = '{0}\{1}' -f $certRoot, $cert.CerFileName
      }
      if ([string]::IsNullOrWhiteSpace($cert.PfxPath) -and -not [string]::IsNullOrWhiteSpace($cert.PfxFileName)) {
        $cert.PfxPath = '{0}\{1}' -f $certRoot, $cert.PfxFileName
      }
    }
  }

  # DRY: derive the semantic Drives hashtable (Data/Logs/Temp -> letter) from the
  # authoritative NonNodeData.Disks list, so a drive letter is declared only once.
  # Temp falls back to the Data drive when no dedicated Temp disk is declared.
  if ($configurationData.NonNodeData.Disks) {
    $byType = @{}
    foreach ($disk in $configurationData.NonNodeData.Disks) {
      if (-not [string]::IsNullOrWhiteSpace($disk.Type) -and -not [string]::IsNullOrWhiteSpace($disk.Letter)) {
        $byType[$disk.Type] = ($disk.Letter.TrimEnd(':')) + ':'
      }
    }
    $drives = @{}
    if ($byType.Data) { $drives.Data = $byType.Data }
    if ($byType.Logs) { $drives.Logs = $byType.Logs }
    $drives.Temp = if ($byType.Temp) { $byType.Temp } elseif ($byType.Data) { $byType.Data } else { $null }
    $configurationData.NonNodeData.Drives = $drives
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
      $credential = New-Object -Typename System.Management.Automation.PSCredential `
        -Argumentlist $username, $password
      New-Variable -Name $serviceAccount.Name -Value $credential -Force
    }
  }
  else {
    throw "Missing $secretsFile"
  }

  # A Script resource writes its values in clear text in the MOF: the farm secrets are encrypted instead.
  foreach ($secretName in @('SWM', 'SWMCertKey') + @($configurationData.NonNodeData.SWM.SslCertificateName | Where-Object { $_ })) {
    if (-not (Get-Variable -Name $secretName -ErrorAction SilentlyContinue)) {
      throw "Missing '$secretName' entry in $secretsFile. Update the file from Secrets.sample.psd1."
    }
  }
  $dscCertificateFile = ($configurationData.AllNodes | Where-Object { $_.NodeName -eq '*' }).CertificateFile
  if ([string]::IsNullOrWhiteSpace($dscCertificateFile) -or -not (Test-Path -Path $dscCertificateFile)) {
    throw "The DSC encryption certificate (CertificateFile = '$dscCertificateFile') was not found. Run scripts\init\Initialize-DscEncryption.ps1 first."
  }

  function Protect-SwmSecret {
    <#
      .SYNOPSIS
      Encrypts a secret for the DSC encryption certificate (public certificate only). The Script
      resources decrypt it with Unprotect-CmsMessage, run by an account that can read the private
      key of the certificate on the node.
    #>
    param(
      [Parameter(Mandatory = $true)] [System.String] $CertificatePath,
      [Parameter(Mandatory = $true)] [System.String] $PlainText
    )
    return (Protect-CmsMessage -To $CertificatePath -Content $PlainText)
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

  Configuration CfgAppSwm {
    # NOTE: Module versions below MUST stay in sync with
    #       scripts/init/Initialize-DscNode.psd1 (Modules table).
    #Import the required DSC resources
    Import-DscResource -ModuleName CertificateDsc -ModuleVersion 6.0.0
    Import-DscResource -ModuleName NetworkingDsc -ModuleVersion 9.1.0
    Import-DscResource -ModuleName PSDscResources -ModuleVersion 2.12.0.0
    Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 17.5.1
    Import-DscResource -ModuleName WebAdministrationDsc -ModuleVersion 4.2.1

    $swmHttpsPort = if ($ConfigurationData.NonNodeData.SWM.HttpsPort) { [int]$ConfigurationData.NonNodeData.SWM.HttpsPort } else { 12290 }

    #For All servers
    Node $AllNodes.Nodename {
      #Set the Local Configuration Manager
      LocalConfigurationManager {
        ConfigurationMode  = 'ApplyOnly'
        RebootNodeIfNeeded = $true
        # Certificate the LCM uses to decrypt the encrypted credentials in this
        # node's MOF. $Node.Thumbprint is injected into the wildcard block by
        # Initialize-DscEncryption.ps1; without it the LCM cannot process an
        # encrypted MOF ("LCM is not configured with a certificate").
        CertificateID      = $Node.Thumbprint
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
        TestScript = { return $null -ne (Get-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -ErrorAction SilentlyContinue | Where-Object { $_.Profile -eq 'Any' }) }
        SetScript  = { Set-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -Profile Any }
      }
    }

    #For all servers with the SharePoint Workflow Manager role
    Node $AllNodes.Where{ $_.IsSWMServer }.Nodename {
      # Same pattern as the Office Online Server block of CfgAppSps.
      Group MIDDLEWARE_AddSWMAccountsToAdminGroup {
        GroupName            = 'Administrators'
        Ensure               = 'Present'
        MembersToInclude     = $Node.LocalAdmins
        Credential           = $ADSETUP
        PsDscRunAsCredential = $ADSETUP
      }

      # Documented IIS prerequisites, plus the management tools to bind the endpoint certificate.
      $requiredFeatures = @(
        'Web-Server', 'Web-Windows-Auth', 'Web-Net-Ext45', 'Web-Asp-Net45',
        'Web-Mgmt-Tools', 'Web-Mgmt-Console'
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

      $swmDestination = Join-Path (Join-Path $ConfigurationData.NonNodeData.Drives.Data 'SoftwarePackages') 'SWM'
      File MIDDLEWARE_SWMGetSources {
        SourcePath      = (Join-Path $ConfigurationData.NonNodeData.SourcePath 'SWM')
        DestinationPath = $swmDestination
        Ensure          = 'Present'
        Recurse         = $true
        Credential      = $SETUP
        MatchSource     = $true
        DependsOn       = '[Group]MIDDLEWARE_AddSWMAccountsToAdminGroup'
      }
      Log MIDDLEWARE_SWMGetSources_Completed {
        #The message below gets written to the Microsoft-Windows-Desired State Configuration/Analytic log
        Message   = 'Finished running the file resource with ID MIDDLEWARE_SWMGetSources'
        DependsOn = '[File]MIDDLEWARE_SWMGetSources'
      }

      # Order required by the installers: Service Fabric, then the Client, then SPWFM.
      $swmBin = Join-Path $swmDestination 'BIN'
      $swmLogs = Join-Path $ConfigurationData.NonNodeData.Drives.Logs $ConfigurationData.NonNodeData.SWM.LogFolder
      $serviceFabricSetup = Join-Path $swmBin $ConfigurationData.NonNodeData.SWM.ServiceFabric.FileName
      $serviceFabricMinVersion = $ConfigurationData.NonNodeData.SWM.ServiceFabric.MinimumVersion

      File MIDDLEWARE_SWMLogFolder {
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = $swmLogs
      }

      Script MIDDLEWARE_SWMInstallServiceFabric {
        DependsOn  = '[Log]MIDDLEWARE_SWMGetSources_Completed'
        GetScript  = { return @{ Result = 'Azure Service Fabric Runtime' } }
        TestScript = {
          $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
          # The LCM runs the script in strict mode: some Uninstall keys have no DisplayName.
          $installed = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.PSObject.Properties['DisplayVersion'] -and $_.DisplayName -like '*Service Fabric*' }
          foreach ($entry in $installed) {
            $version = $null
            if ([System.Version]::TryParse([string]$entry.DisplayVersion, [ref]$version) -and $version -ge [System.Version]$using:serviceFabricMinVersion) { return $true }
          }
          return $false
        }
        SetScript  = {
          $process = Start-Process -FilePath $using:serviceFabricSetup -ArgumentList '/accepteula' -Wait -PassThru
          # 3010 = restart required, left to the LCM.
          if ($process.ExitCode -eq 3010) { $global:DSCMachineStatus = 1 }
          elseif ($process.ExitCode -ne 0) { throw "Azure Service Fabric setup failed with exit code $($process.ExitCode)." }
        }
      }

      MsiPackage MIDDLEWARE_SWMInstallClient {
        DependsOn = '[Script]MIDDLEWARE_SWMInstallServiceFabric', '[File]MIDDLEWARE_SWMLogFolder'
        Ensure    = 'Present'
        Path      = (Join-Path $swmBin $ConfigurationData.NonNodeData.SWM.WorkflowClient.FileName)
        ProductId = $ConfigurationData.NonNodeData.SWM.WorkflowClient.ProductId
        LogPath   = (Join-Path $swmLogs 'SWMClientInstall.log')
      }

      MsiPackage MIDDLEWARE_SWMInstallServer {
        DependsOn = '[MsiPackage]MIDDLEWARE_SWMInstallClient'
        Ensure    = 'Present'
        Path      = (Join-Path $swmBin $ConfigurationData.NonNodeData.SWM.WorkflowServer.FileName)
        ProductId = $ConfigurationData.NonNodeData.SWM.WorkflowServer.ProductId
        LogPath   = (Join-Path $swmLogs 'SWMServerInstall.log')
      }

      $swmSqlAlias = $ConfigurationData.NonNodeData.SQLAlias | Where-Object { $_.Name -eq 'WORKFLOW' } | Select-Object -First 1
      SqlAlias MIDDLEWARE_SWMSqlAlias {
        Ensure            = 'Present'
        Protocol          = 'TCP'
        TcpPort           = $swmSqlAlias.Port
        UseDynamicTcpPort = $False
        Name              = $swmSqlAlias.ServerAlias
        ServerName        = "$($swmSqlAlias.ServerName)\$($swmSqlAlias.InstanceName)"
      }
      $sbFarmDb = 'Data Source={0};Initial Catalog={1};Integrated Security=True' -f $swmSqlAlias.ServerAlias, $ConfigurationData.NonNodeData.SWM.ServiceBus.FarmDatabase
      $swmRunAsAccount = $SWM.UserName
      $swmEnableFirewall = [bool]$ConfigurationData.NonNodeData.SWM.EnableFirewallRules
      $encSwmPassword = Protect-SwmSecret -CertificatePath $Node.CertificateFile -PlainText $SWM.GetNetworkCredential().Password
      $encSwmCertKey = Protect-SwmSecret -CertificatePath $Node.CertificateFile -PlainText $SWMCertKey.GetNetworkCredential().Password

      Script MIDDLEWARE_SWMCreateServiceBusFarm {
        DependsOn            = '[MsiPackage]MIDDLEWARE_SWMInstallServer', '[SqlAlias]MIDDLEWARE_SWMSqlAlias'
        PsDscRunAsCredential = $SETUP
        GetScript            = { return @{ Result = 'Service Bus farm' } }
        TestScript           = {
          Import-Module (Join-Path $env:ProgramFiles 'Service Bus\1.1\ServiceBus\ServiceBus.psd1')
          try { $null = Get-SBFarm -SBFarmDBConnectionString $using:sbFarmDb -ErrorAction Stop; return $true } catch { return $false }
        }
        SetScript            = {
          Import-Module (Join-Path $env:ProgramFiles 'Service Bus\1.1\ServiceBus\ServiceBus.psd1')
          $certKey = ConvertTo-SecureString -String (Unprotect-CmsMessage -Content $using:encSwmCertKey) -AsPlainText -Force
          New-SBFarm -SBFarmDBConnectionString $using:sbFarmDb -RunAsAccount $using:swmRunAsAccount -CertificateAutoGenerationKey $certKey -ErrorAction Stop
        }
      }

      Script MIDDLEWARE_SWMAddServiceBusHost {
        DependsOn            = '[Script]MIDDLEWARE_SWMCreateServiceBusFarm'
        PsDscRunAsCredential = $SETUP
        GetScript            = { return @{ Result = 'Service Bus host' } }
        TestScript           = {
          $key = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Service Bus\1.1' -ErrorAction SilentlyContinue
          $state = if ($key) { $key.PSObject.Properties['HostConfigurationState'] }
          return ($null -ne $state -and $state.Value -eq 'Completed')
        }
        SetScript            = {
          Import-Module (Join-Path $env:ProgramFiles 'Service Bus\1.1\ServiceBus\ServiceBus.psd1')
          $password = ConvertTo-SecureString -String (Unprotect-CmsMessage -Content $using:encSwmPassword) -AsPlainText -Force
          $certKey = ConvertTo-SecureString -String (Unprotect-CmsMessage -Content $using:encSwmCertKey) -AsPlainText -Force
          Add-SBHost -SBFarmDBConnectionString $using:sbFarmDb -RunAsPassword $password -EnableFirewallRules $using:swmEnableFirewall -CertificateAutoGenerationKey $certKey -ErrorAction Stop
        }
      }

      Log MIDDLEWARE_SWMServiceBus_Completed {
        Message   = 'Finished running the Service Bus farm creation and host registration'
        DependsOn = '[Script]MIDDLEWARE_SWMAddServiceBusHost'
      }

      $swmNamespace = $ConfigurationData.NonNodeData.SWM.ServiceBus.Namespace
      $wfFarmDb = 'Data Source={0};Initial Catalog={1};Integrated Security=True' -f $swmSqlAlias.ServerAlias, $ConfigurationData.NonNodeData.SWM.WorkflowManager.FarmDatabase
      $swmHttpsPortValue = $swmHttpsPort
      $swmSetupAccount = $SETUP.UserName

      Script MIDDLEWARE_SWMCreateServiceBusNamespace {
        DependsOn            = '[Script]MIDDLEWARE_SWMAddServiceBusHost'
        PsDscRunAsCredential = $SETUP
        GetScript            = { return @{ Result = 'Service Bus namespace' } }
        TestScript           = {
          Import-Module (Join-Path $env:ProgramFiles 'Service Bus\1.1\ServiceBus\ServiceBus.psd1')
          $namespace = @(Get-SBNamespace -ErrorAction Stop) | Where-Object { $_.Name -eq $using:swmNamespace } | Select-Object -First 1
          if (-not $namespace) { return $false }
          $setupName = ($using:swmSetupAccount -split '\\')[-1]
          return [bool](@($namespace.ManageUsers) | Where-Object { $_ -like "$setupName@*" -or $_ -like "*\$setupName" })
        }
        SetScript            = {
          Import-Module (Join-Path $env:ProgramFiles 'Service Bus\1.1\ServiceBus\ServiceBus.psd1')
          $managers = @($using:swmRunAsAccount, $using:swmSetupAccount)
          if (@(Get-SBNamespace -ErrorAction Stop) | Where-Object { $_.Name -eq $using:swmNamespace }) {
            Set-SBNamespace -Name $using:swmNamespace -ManageUsers $managers -ErrorAction Stop
          }
          else {
            New-SBNamespace -Name $using:swmNamespace -AddressingScheme 'Path' -ManageUsers $managers -ErrorAction Stop
          }
        }
      }

      Script MIDDLEWARE_SWMCreateWorkflowFarm {
        DependsOn            = '[Script]MIDDLEWARE_SWMAddServiceBusHost', '[SqlAlias]MIDDLEWARE_SWMSqlAlias'
        PsDscRunAsCredential = $SETUP
        GetScript            = { return @{ Result = 'Workflow Manager farm' } }
        TestScript           = {
          Import-Module (Join-Path $env:ProgramFiles 'Workflow Manager\1.0\WorkflowManager\WorkflowManager.psd1')
          try { $null = Get-WFFarm -WFFarmDBConnectionString $using:wfFarmDb -ErrorAction Stop; return $true } catch { return $false }
        }
        SetScript            = {
          Import-Module (Join-Path $env:ProgramFiles 'Workflow Manager\1.0\WorkflowManager\WorkflowManager.psd1')
          $certKey = ConvertTo-SecureString -String (Unprotect-CmsMessage -Content $using:encSwmCertKey) -AsPlainText -Force
          New-WFFarm -WFFarmDBConnectionString $using:wfFarmDb -RunAsAccount $using:swmRunAsAccount -HttpsPort $using:swmHttpsPortValue -CertificateAutoGenerationKey $certKey -ErrorAction Stop
        }
      }

      Script MIDDLEWARE_SWMAddWorkflowHost {
        DependsOn            = '[Script]MIDDLEWARE_SWMCreateWorkflowFarm', '[Script]MIDDLEWARE_SWMCreateServiceBusNamespace'
        PsDscRunAsCredential = $SETUP
        GetScript            = { return @{ Result = 'Workflow Manager host' } }
        TestScript           = {
          $key = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Workflow Manager\1.0' -ErrorAction SilentlyContinue
          $state = if ($key) { $key.PSObject.Properties['HostConfigurationState'] }
          return ($null -ne $state -and $state.Value -eq 'Completed')
        }
        SetScript            = {
          Import-Module (Join-Path $env:ProgramFiles 'Service Bus\1.1\ServiceBus\ServiceBus.psd1')
          Import-Module (Join-Path $env:ProgramFiles 'Workflow Manager\1.0\WorkflowManager\WorkflowManager.psd1')
          $password = ConvertTo-SecureString -String (Unprotect-CmsMessage -Content $using:encSwmPassword) -AsPlainText -Force
          # Mandatory but not listed by Get-Command: without it the cmdlet prompts, which DSC refuses.
          $certKey = ConvertTo-SecureString -String (Unprotect-CmsMessage -Content $using:encSwmCertKey) -AsPlainText -Force
          $sbClientConfiguration = Get-SBClientConfiguration -Namespaces $using:swmNamespace -ErrorAction Stop
          Add-WFHost -WFFarmDBConnectionString $using:wfFarmDb -RunAsPassword $password -SBClientConfiguration $sbClientConfiguration -EnableFirewallRules $using:swmEnableFirewall -CertificateAutoGenerationKey $certKey -ErrorAction Stop
        }
      }

      $swmCompletedDependsOn = @('[Script]MIDDLEWARE_SWMAddWorkflowHost')
      $swmSslCertName = $ConfigurationData.NonNodeData.SWM.SslCertificateName
      if ($swmSslCertName) {
        $swmSslCert = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object { $_.Name -eq $swmSslCertName }
        if ($null -eq $swmSslCert) {
          throw "NonNodeData.SWM.SslCertificateName is '$swmSslCertName' but no ADC certificate has that name in NonNodeData.ADC.certificates."
        }
        $swmSslThumbprint = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $swmSslCert.CertPath).Thumbprint

        PfxImport MIDDLEWARE_SWMSslCertificateImport {
          DependsOn  = '[Script]MIDDLEWARE_SWMAddWorkflowHost'
          Thumbprint = $swmSslThumbprint
          Path       = $swmSslCert.PfxPath
          Store      = 'My'
          Location   = 'LocalMachine'
          Credential = (Get-Variable -Name $swmSslCertName -ValueOnly)
          Exportable = $true
          Ensure     = 'Present'
        }

        Script MIDDLEWARE_SWMSetSslCertificate {
          DependsOn            = '[PfxImport]MIDDLEWARE_SWMSslCertificateImport'
          PsDscRunAsCredential = $SETUP
          GetScript            = { return @{ Result = 'Workflow Manager SSL certificate' } }
          TestScript           = {
            Import-Module WebAdministration
            $binding = Get-WebBinding -Name 'Workflow Management Site' -Protocol https | Select-Object -First 1
            return ($null -ne $binding -and $binding.certificateHash -eq $using:swmSslThumbprint)
          }
          SetScript            = {
            Import-Module (Join-Path $env:ProgramFiles 'Workflow Manager\1.0\WorkflowManager\WorkflowManager.psd1')
            Set-WFCertificate -WFFarmDBConnectionString $using:wfFarmDb -SslCertificateThumbprint $using:swmSslThumbprint -ErrorAction Stop
            Update-WFHost -WFFarmDBConnectionString $using:wfFarmDb -ErrorAction Stop
          }
        }
        $swmCompletedDependsOn += '[Script]MIDDLEWARE_SWMSetSslCertificate'
      }

      Log MIDDLEWARE_SWM_Completed {
        Message   = 'Finished running the SharePoint Workflow Manager farm creation and host registration'
        DependsOn = $swmCompletedDependsOn
      }

      # Only port documented by Microsoft Learn; the farm cmdlets open the Service Bus ones.
      Firewall MIDDLEWARE_SWMHttpsFirewallRule {
        Name        = 'SWM-Workflow-HTTPS-TCP-In'
        DisplayName = 'SharePoint Workflow Manager (HTTPS TCP-In)'
        Description = 'Inbound rule for SharePoint servers to reach the Workflow Management endpoint over HTTPS.'
        Group       = 'SharePoint Workflow Manager'
        Direction   = 'Inbound'
        Protocol    = 'TCP'
        LocalPort   = "$swmHttpsPort"
        Profile     = 'Domain'
        Enabled     = 'True'
        Action      = 'Allow'
        Ensure      = 'Present'
      }
    }
  }
  #Run the CfgAppSwm configuration with the provided ConfigurationData
  # Note: Import-PowerShellDataFile returns hashtables, so use ForEach-Object
  # (hashtable dot-syntax) instead of Select-Object -ExpandProperty.
  $nodeList = ($configurationData.AllNodes | Where-Object { $_.NodeName -ne '*' } | ForEach-Object { $_.NodeName }) -join ', '
  Write-Host ("[{0}] Compiling CfgAppSwm for node(s) : {1}" -f (Get-Date -Format 'o'), $nodeList)
  Write-Host ("[{0}] MOF output path            : {1}" -f (Get-Date -Format 'o'), $mofOutputPath)
  CfgAppSwm -ConfigurationData $ConfigurationData -OutputPath $mofOutputPath

  #Checksum the generated MOF files
  New-DscChecksum -Force -Path $mofOutputPath -Verbose
  Write-Host ("[{0}] Compilation complete." -f (Get-Date -Format 'o'))
}
catch {
  # Preserve full error context (script, line number, exception message) before rethrowing.
  Write-Error -Message ("CfgAppSwm compilation failed at {0}:{1} - {2}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
  throw
}
