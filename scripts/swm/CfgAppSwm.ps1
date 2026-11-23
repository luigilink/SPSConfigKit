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
  server, the IIS prerequisites (and IIS logging), the copy of the installers from the share and
  the firewall rule of the Workflow Management endpoint. The installation of Service Fabric and
  SharePoint Workflow Manager, the endpoint certificate and the farm creation are added next.

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
    Import-DscResource -ModuleName NetworkingDsc -ModuleVersion 9.1.0
    Import-DscResource -ModuleName PSDscResources -ModuleVersion 2.12.0.0
    Import-DscResource -ModuleName WebAdministrationDsc -ModuleVersion 4.2.1

    # HTTPS port of the Workflow Management endpoint. 12290 is the default documented by
    # Microsoft Learn; override it with NonNodeData.SWM.HttpsPort (the same value must be used
    # when the farm is created).
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
      # Add the setup account and the SWM service account to the local Administrators group,
      # so the Windows-level resources of the next steps can run. Same pattern as the Office
      # Online Server block of CfgAppSps (the domain join is done by Add-DscNodeToDomain.ps1).
      Group MIDDLEWARE_AddSWMAccountsToAdminGroup {
        GroupName            = 'Administrators'
        Ensure               = 'Present'
        MembersToInclude     = $Node.LocalAdmins
        Credential           = $ADSETUP
        PsDscRunAsCredential = $ADSETUP
      }

      # IIS prerequisites documented for SharePoint Workflow Manager (Web Server, Windows
      # Authentication, .NET Extensibility 4.7, ASP.NET 4.7), plus the IIS management tools
      # to bind the endpoint certificate in IIS Manager.
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

      # Remove the Default Web Site (it holds port 443). The default application pools are kept:
      # nothing documents whether SharePoint Workflow Manager relies on them.
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

      # Get the SWM installation files: <SourcePath>\SWM -> <Drives.Data>\SoftwarePackages\SWM
      File MIDDLEWARE_SWMGetSources {
        SourcePath      = (Join-Path $ConfigurationData.NonNodeData.SourcePath 'SWM')
        DestinationPath = (Join-Path (Join-Path $ConfigurationData.NonNodeData.Drives.Data 'SoftwarePackages') 'SWM')
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

      # Inbound rule for the Workflow Management endpoint (HTTPS 12290 by default). It is the only
      # port Microsoft Learn documents for SharePoint Workflow Manager; the other ports (Service
      # Bus, Service Fabric) are added once they are verified on a configured server.
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
