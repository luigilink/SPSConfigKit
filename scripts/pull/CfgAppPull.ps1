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
  Compiles the DSC pull server configuration: WMF 5.1 HTTPS pull server
  (xDscWebService) published on port 443, IIS hardening, registration key file,
  and the firewall rule consumed by every managed node in the sample lab.

  .DESCRIPTION
  Imports node + non-node data from a .psd1 file and secret material from
  Secrets.psd1, then compiles MOF files for every node defined in AllNodes.
  The script is idempotent: re-running it simply regenerates the MOFs in
  the output directory and refreshes the checksums.

  .PARAMETER inputFile
  Full path to the ConfigurationData .psd1. Defaults to CfgAppPull.psd1 in
  the same directory as the script.

  .PARAMETER secretsFile
  Full path to the Secrets.psd1. Defaults to ..\Secrets.psd1 relative to
  the script directory.

  .PARAMETER OutputPath
  Directory where the compiled MOF files (and checksums) are written.
  Defaults to <scriptDir>\MOF. The directory is created if missing.

  .EXAMPLE
  .\CfgAppPull.ps1

  .EXAMPLE
  .\CfgAppPull.ps1 -inputFile .\CfgAppPull.psd1 -secretsFile ..\Secrets.psd1 -OutputPath C:\DSC\MOF

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
    Write-Host 'No input file provided. Try to use CfgAppPull.psd1 in the same directory as the script.'
    $inputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppPull.psd1'
  }
  if (Test-Path $inputFile) {
    Write-Host "Importing configuration data from $inputFile"
    $configurationData = Import-PowerShellDataFile -Path $inputFile
  }
  else {
    throw "Missing $inputFile"
  }

  # DRY: derive certificate paths from the single share root (NonNodeData.SourcePath)
  # + each entry's CerFileName / PfxFileName, so the share host is defined only once.
  # An explicit CertPath / PfxPath on an entry is still honoured (backward compatible).
  $certSourcePath = $configurationData.NonNodeData.SourcePath
  if ($configurationData.NonNodeData.ADC -and $configurationData.NonNodeData.ADC.certificates) {
    foreach ($cert in $configurationData.NonNodeData.ADC.certificates) {
      $certRoot = $certSourcePath.TrimEnd('\\')
      if ([string]::IsNullOrWhiteSpace($cert.CertPath) -and -not [string]::IsNullOrWhiteSpace($cert.CerFileName)) {
        $cert.CertPath = '{0}\{1}' -f $certRoot, $cert.CerFileName
      }
      if ([string]::IsNullOrWhiteSpace($cert.PfxPath) -and -not [string]::IsNullOrWhiteSpace($cert.PfxFileName)) {
        $cert.PfxPath = '{0}\{1}' -f $certRoot, $cert.PfxFileName
      }
    }
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

  Configuration CfgAppPull {
    # NOTE: Module versions below MUST stay in sync with
    #       scripts/init/Initialize-DscNode.psd1 (Modules table).
    #Import the required DSC resources
    Import-DscResource -ModuleName CertificateDsc -ModuleVersion 6.0.0
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion 10.0.0
    Import-DscResource -ModuleName NetworkingDsc -ModuleVersion 9.1.0
    Import-DscResource -ModuleName PSDscResources -ModuleVersion 2.12.0.0
    Import-DscResource -ModuleName WebAdministrationDsc -ModuleVersion 4.2.1
    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 9.2.1

    #For All servers
    Node $AllNodes.Nodename {
      #Set the Local Configuration Manager
      LocalConfigurationManager {
        ConfigurationMode  = 'ApplyOnly'
        RebootNodeIfNeeded = $true
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
    }

    #For All DSC Pull servers
    Node $AllNodes.Where{ $_.IsPullServer }.NodeName {
      # Get certificate information. The cert Name matches the matching Secrets.psd1
      # entry ('DscPullCert') so the per-cert PFX password resolves through the same
      # Get-Variable pattern used by CfgAppPdc.ps1 / CfgAppSps.ps1.
      $getCertInfo = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -eq 'DscPullCert' }
      #Retrieve the certificate Thumprint from CertPath
      try {
        $getSPCertificate = Get-CertThumbprint -CertPath "$($getCertInfo.CertPath)"
      }
      catch {
        Write-Error "Failed to retrieve the certificate: $_"
        throw
      }
      #Import PFX Certificate in My
      PfxImport "APPLICATION_SharePointCert_$($getSPCertificate.BaseName)" {
          Thumbprint = "$($getSPCertificate.Thumbprint)"
          Path       = "$($getCertInfo.PfxPath)"
          Location   = 'LocalMachine'
          Store      = 'My'
          Ensure     = 'Present'
          # Per-cert PFX password: resolves the PSCredential auto-materialised by the
          # secrets loader (Name = $getCertInfo.Name, i.e. 'DscPullCert'). Replaces the
          # removed shared $PFXCred variable, aligning PULL with PDC/SPS.
          Credential = (Get-Variable -Name $getCertInfo.Name -ValueOnly)
          Exportable = $true
      }
      #Install Features
      $requiredFeatures = @(
        'DSC-Service', 'Web-Server', 'Web-WebServer', 'Web-Asp-Net45',
        'Web-Windows-Auth', 'Web-Filtering', 'Web-Mgmt-Tools', 'Web-Scripting-Tools'
      )
      foreach ($feature in $requiredFeatures) {
        WindowsFeature "WindowsFeature-$feature" {
          Ensure = 'Present'
          Name   = $feature
        }
      }
      $prereqDependencies = $RequiredFeatures | ForEach-Object -Process {
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
      # NOTE: granting the pull-server AppPool identity write access to the DSC
      # service folder (so the ESENT repository can create Devices.edb) is done by
      # a dedicated post-configuration script, NOT here. That folder is owned by
      # TrustedInstaller and even SYSTEM/Administrators lack Change-Permissions on
      # it, so the ACL change needs a takeown + icacls sequence that does not belong
      # in the recurring DSC consistency loop. Run, once, after applying this MOF:
      #   scripts\pull\Set-SPSPullServerPermission.ps1
      # See scripts\pull\README.md.
      #Install DscService
      # Note: SqlProvider is intentionally NOT enabled. The inbox
      # Microsoft.Powershell.DesiredStateConfiguration.Service.dll on Windows
      # Server 2019/2022 has long-standing bugs with the SQL provider:
      # `dbprovider = System.Data.SqlClient` is ignored and the code falls
      # back to the JET (ESENT) provider, which then tries to treat the SQL
      # connection string as a filesystem path and fails with
      # "CreateRepositoryInstance: ... folder ... access denied".
      # See dsccommunity/xPSDesiredStateConfiguration#201 (open since 2016).
      # The default JET-backed repository (Devices.edb in RegistrationKeyPath)
      # is well-tested and adequate for a single pull server.
      xDscWebService MIDDLEWARE_IIS-PSDSCPullServer {
        DependsOn                    = $prereqDependencies
        Ensure                       = 'Present'
        EndpointName                 = 'PSDSCPullServer'
        Port                         = 443
        PhysicalPath                 = "$env:SystemDrive\inetpub\PSDSCPullServer"
        CertificateThumbPrint        = "$($getSPCertificate.Thumbprint)"
        ModulePath                   = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Modules"
        ConfigurationPath            = "$env:PROGRAMFILES\WindowsPowerShell\DscService\Configuration"
        State                        = 'Started'
        RegistrationKeyPath          = "$env:PROGRAMFILES\WindowsPowerShell\DscService"
        AcceptSelfSignedCertificates = $false
        UseSecurityBestPractices     = $true
        Enable32BitAppOnWin64        = $false
      }
      File MIDDLEWARE_PullServer_RegistrationKeyFile {
        Ensure          = 'Present'
        Type            = 'File'
        DestinationPath = "$env:ProgramFiles\WindowsPowerShell\DscService\RegistrationKeys.txt"
        Contents        = "$($Node.RegistrationKey)"
      }
      Firewall MIDDLEWARE_PSDSCPullServerRule {
          Ensure      = 'Present'
          Name        = "DSC_PullServer_443"
          DisplayName = "DSC PullServer 443"
          Group       = 'DSC PullServer'
          Enabled     = $true
          Action      = 'Allow'
          Direction   = 'InBound'
          LocalPort   = 443
          Protocol    = 'TCP'
          DependsOn   = '[xDscWebService]MIDDLEWARE_IIS-PSDSCPullServer'
      }
      #Configure IIS appplication pool identity to use the pull service account
      WebAppPool MIDDLEWARE_PullServer_AppPool {
        DependsOn            = '[xDscWebService]MIDDLEWARE_IIS-PSDSCPullServer'
        Ensure               = 'Present'
        Name                 = 'PSWS'
        Credential           = $IISPULLAPP
        IdentityType         = 'SpecificUser'
        ManagedRuntimeVersion = 'v4.0'
        AutoStart             = $true
      }
    }
  }
  #Run the CfgAppPull configuration with the provided ConfigurationData
  # Note: Import-PowerShellDataFile returns hashtables, so use ForEach-Object
  # (hashtable dot-syntax) instead of Select-Object -ExpandProperty.
  $nodeList = ($configurationData.AllNodes | Where-Object { $_.NodeName -ne '*' } | ForEach-Object { $_.NodeName }) -join ', '
  Write-Host ("[{0}] Compiling CfgAppPull for node(s) : {1}" -f (Get-Date -Format 'o'), $nodeList)
  Write-Host ("[{0}] MOF output path            : {1}" -f (Get-Date -Format 'o'), $mofOutputPath)
  CfgAppPull -ConfigurationData $ConfigurationData -OutputPath $mofOutputPath

  #Checksum the generated MOF files
  New-DscChecksum -Force -Path $mofOutputPath -Verbose
  Write-Host ("[{0}] Compilation complete." -f (Get-Date -Format 'o'))
}
catch {
  # Preserve full error context (script, line number, exception message) before rethrowing.
  Write-Error -Message ("CfgAppPull compilation failed at {0}:{1} - {2}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}
