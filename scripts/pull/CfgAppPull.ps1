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
param(
  [Parameter()]
  [System.String]
  $inputFile,

  [Parameter()]
  [System.String]
  $secretsFile
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
    write-host "No input file provided. Try to use CfgAppPull.psd1 in the same directory as the script."
    $inputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppPull.psd1'
  }
  if (Test-Path $inputFile) {
    write-host "Importing configuration data from $inputFile"
    $configurationData = Import-PowerShellDataFile -Path  $inputFile
  }
  else {
    Throw "Missing $inputFile"
  }

  if ([string]::IsNullOrWhiteSpace($secretsFile)) {
    write-host "No secrets file provided. Try to use Secrets.psd1 in the parent directory of the script."
    $secretsFile = Join-Path -Path (Split-Path -Path $scriptBasePath -Parent) -ChildPath 'Secrets.psd1'
  }
  if (Test-Path $secretsFile) {
    write-host "Importing secrets data from $secretsFile"
    $secretsData = Import-PowerShellDataFile -Path  $secretsFile
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
    Throw "Missing $secretsFile"
  }

  #Initialization of the output path for the generated MOF files
  $mofOutputPath = Join-Path -Path $scriptBasePath -ChildPath 'MOF'
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
      write-warning $_.Exception.Message
      write-warning "$CertPath was not found"
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
      # Get certificate information
      $getCertInfo = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -eq 'DscPull' }
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
          Credential = $PFXCred
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
      # Grant the pull-server AppPool identity Modify on the DSC service
      # folder so the JET (ESENT) repository can create Devices.edb and its
      # edbtmp / edb log files. Avoids needing local admin on the AppPool
      # identity (which would also be a privilege escalation risk because
      # the same account runs SharePoint).
      $pullServerDscServicePath = "$env:PROGRAMFILES\WindowsPowerShell\DscService"
      $pullServerAppPoolUser    = $IISPULLAPP.UserName
      Script MIDDLEWARE_PullServer_DscServiceAcl {
        DependsOn  = $prereqDependencies
        GetScript  = {
          @{ Result = (Get-Acl -Path $using:pullServerDscServicePath).Access |
              Where-Object { $_.IdentityReference -eq $using:pullServerAppPoolUser } |
              Select-Object -ExpandProperty FileSystemRights -First 1 }
        }
        TestScript = {
          if (-not (Test-Path -Path $using:pullServerDscServicePath)) { return $false }
          $acl   = Get-Acl -Path $using:pullServerDscServicePath
          $match = $acl.Access |
              Where-Object { $_.IdentityReference -eq $using:pullServerAppPoolUser -and
                             $_.AccessControlType -eq 'Allow' -and
                             ($_.FileSystemRights.ToString() -match 'Modify|FullControl') }
          return ($null -ne $match)
        }
        SetScript  = {
          if (-not (Test-Path -Path $using:pullServerDscServicePath)) {
            New-Item -Path $using:pullServerDscServicePath -ItemType Directory -Force | Out-Null
          }
          $acl  = Get-Acl -Path $using:pullServerDscServicePath
          $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $using:pullServerAppPoolUser,
            'Modify',
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow')
          $acl.SetAccessRule($rule)
          Set-Acl -Path $using:pullServerDscServicePath -AclObject $acl
        }
      }
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
  #Run the AppPull configuration with the provided ConfigurationData
  CfgAppPull -ConfigurationData $ConfigurationData -OutputPath $mofOutputPath

  #Checksum to the generated MOF files
  New-DscChecksum -Force -Path $mofOutputPath -verbose
}
catch {
  throw $_
}
