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
  Compiles the SQL Server DSC configuration: stand-alone SQL Server instance
  tuned for the SharePoint farm (engine install, service accounts, sysadmin
  members, TempDB layout, max-memory / MAXDOP, firewall rule).

  .DESCRIPTION
  Imports node + non-node data from a .psd1 file and secret material from
  Secrets.psd1, then compiles MOF files for every node defined in AllNodes.
  The script is idempotent: re-running it simply regenerates the MOFs in
  the output directory and refreshes the checksums.

  .PARAMETER inputFile
  Full path to the ConfigurationData .psd1. Defaults to CfgAppSql.psd1 in
  the same directory as the script.

  .PARAMETER secretsFile
  Full path to the Secrets.psd1. Defaults to ..\Secrets.psd1 relative to
  the script directory.

  .PARAMETER OutputPath
  Directory where the compiled MOF files (and checksums) are written.
  Defaults to <scriptDir>\MOF. The directory is created if missing.

  .EXAMPLE
  .\CfgAppSql.ps1

  .EXAMPLE
  .\CfgAppSql.ps1 -inputFile .\CfgAppSql.psd1 -secretsFile ..\Secrets.psd1 -OutputPath C:\DSC\MOF

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
    Write-Host 'No input file provided. Try to use CfgAppSql.psd1 in the same directory as the script.'
    $inputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppSql.psd1'
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

  Configuration CfgAppSql {
    #Initialize variables
    $dataDrive = $configurationData.NonNodeData.Drives.Data
    $logsDrive = $configurationData.NonNodeData.Drives.Logs
    $tempDrive = $configurationData.NonNodeData.Drives.Temp

    # NOTE: Module versions below MUST stay in sync with
    #       scripts/init/Initialize-DscNode.psd1 (Modules table).
    #Import the required DSC resources
    Import-DscResource -ModuleName CertificateDsc -ModuleVersion 6.0.0
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion 10.0.0
    Import-DscResource -ModuleName NetworkingDsc -ModuleVersion 9.1.0
    Import-DscResource -ModuleName PSDscResources -ModuleVersion 2.12.0.0
    Import-DscResource -ModuleName SqlServerDsc -ModuleVersion 17.5.1
    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 9.2.1

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

    #For all servers with SQL Server Role
    Node $AllNodes.Where{ $_.IsSQLServer }.Nodename {
      #Initialize variables for SQL Source Path.
      # Customers can override NonNodeData.SQL.SourcePath / .DestinationPath in their .psd1
      # without touching the configuration script. Defaults preserve the original layout:
      #   <SourcePath>\SQL  /  <Drives.Data>\SoftwarePackages\SQL
      $sqlConfig = if ($ConfigurationData.NonNodeData.SQL) { $ConfigurationData.NonNodeData.SQL } else { @{} }
      $sqlSourcePath = if ($sqlConfig.SourcePath) {
        $sqlConfig.SourcePath
      }
      else {
        "$($ConfigurationData.NonNodeData.SourcePath)\SQL"
      }
      $sqlDestinationPath = if ($sqlConfig.DestinationPath) {
        $sqlConfig.DestinationPath
      }
      else {
        "$($ConfigurationData.NonNodeData.Drives.Data)\SoftwarePackages\SQL"
      }
      #Copy the SQL installation files from File Share
      File APPLICATION_SqlGetSources {
        Ensure          = 'Present'
        Type            = 'Directory'
        SourcePath      = $sqlSourcePath
        DestinationPath = $sqlDestinationPath
        Recurse         = $true
        MatchSource     = $true
        Force           = $true
        Checksum        = 'modifiedDate'
        Credential      = $SETUP
      }
      #Initialize the SQL Server Instance variable
      $sqlSPInstance = $Node.SQLInstanceName
      $sqlTcpPort = $Node.SQLTcpPort
      # Derive the Windows service names from the instance name. The default
      # instance (MSSQLSERVER) uses the well-known service names; a named instance
      # uses the MSSQL$<Instance> / SQLAgent$<Instance> convention. SQLBrowser is
      # always instance-independent.
      $sqlEngineServiceName = if ($sqlSPInstance -eq 'MSSQLSERVER') { 'MSSQLSERVER' } else { "MSSQL`$$sqlSPInstance" }
      $sqlAgentServiceName = if ($sqlSPInstance -eq 'MSSQLSERVER') { 'SQLSERVERAGENT' } else { "SQLAgent`$$sqlSPInstance" }
      # Default to a universally-declared sentinel resource so the configure-only
      # resources below don't dangle when IsSQLSetup=$False (pre-existing SQL).
      # When IsSQLSetup=$True, the override inside the if-block makes everything
      # wait for SqlSetup instead, preserving the install-then-configure ordering.
      $dependsOnSQLSetup = '[Service]SYSTEM_SvcTWerSvcDisableStopped'

      # Credential the SQL-configuration resources (SqlLogin / SqlRole / SqlMemory
      # / SqlMaxDop / SqlProtocolTcpIP) run under. With Windows authentication the
      # effective SQL login is this RunAs account, so it MUST be a SQL sysadmin.
      # SqlSetup grants sysadmin only to SQLSysAdminAccounts (= SQLSysAdministrators),
      # so use $SETUP (svcspssetup), a member of that list. Do NOT use $ADSETUP here:
      # it is not a SQL sysadmin, so it connects with no rights and every SqlXXX
      # resource fails with 'Failed to connect to SQL instance'.
      $sqlAdminCredential = $SETUP
      if ($Node.IsSQLSetup) {
        $dependsOnSQLSetup = '[SqlSetup]MIDDLEWARE_SqlMSSQLSERVER'
        SqlSetup MIDDLEWARE_SqlMSSQLSERVER {
          DependsOn              = '[File]APPLICATION_SqlGetSources'
          Action                 = 'Install'
          SourcePath             = $sqlDestinationPath
          UpdateEnabled          = $true
          InstanceName           = $sqlSPInstance
          #Feature shortname see https://msdn.microsoft.com/en-us/library/ms144259(v=sql.120).aspx#Feature
          #Engine + Mgt tools basic + Mgt tools advanced
          Features               = 'SQLENGINE'
          SQLSysAdminAccounts    = $Node.SQLSysAdministrators
          SQLSvcAccount          = $SQLSERVER
          AgtSvcAccount          = $SQLSERVER
          InstallSharedDir       = "$($dataDrive)\$($sqlSPInstance)\INSTALL\SQLServer"
          InstallSharedWOWDir    = "$($dataDrive)\$($sqlSPInstance)\INSTALL\SQLServerWOW"
          InstanceDir            = "$($dataDrive)\$($sqlSPInstance)\MSSQL\SPSInstance"
          InstallSQLDataDir      = "$($dataDrive)\$($sqlSPInstance)\MSSQL\SPSInstance\Data"
          SQLUserDBDir           = "$($dataDrive)\$($sqlSPInstance)\MSSQL\DATA"
          SQLUserDBLogDir        = "$($logsDrive)\$($sqlSPInstance)\MSSQL\LOG"
          SQLTempDBDir           = "$($tempDrive)\$($sqlSPInstance)\MSSQL\TEMPDB"
          SQLTempDBLogDir        = "$($tempDrive)\$($sqlSPInstance)\MSSQL\TEMPDB"
          SQLBackupDir           = "$($dataDrive)\$($sqlSPInstance)\MSSQL\BACKUP"
          #Recommended collation for sharepoint https://support.microsoft.com/en-us/kb/2008668
          SQLCollation           = $Node.SQLCollation
          ForceReboot            = $True
          SqlTempdbFileCount     = 8
          SqlTempdbFileSize      = 2048
          SqlTempdbFileGrowth    = 512
          SqlTempdbLogFileSize   = 128
          SqlTempdbLogFileGrowth = 64
        }
      }
      if ($null -ne $sqlTcpPort) {
        # Enable the TCP/IP protocol itself. SqlProtocolTcpIP below only sets the
        # port on the IPAll group; without this the protocol stays DISABLED and
        # the instance listens on no TCP port, so remote clients / the SharePoint
        # SqlAlias fail with "SQL Server does not exist or access denied". The
        # resource restarts the service by default (SuppressRestart defaults to $false)
        # so the change takes effect.
        SqlProtocol MIDDLEWARE_SqlProtocolTcpEnabled {
          DependsOn              = $dependsOnSQLSetup
          PsDscRunAsCredential   = $sqlAdminCredential
          InstanceName           = $sqlSPInstance
          ProtocolName           = 'TcpIp'
          Enabled                = $true
          ListenOnAllIpAddresses = $true
        }
        SqlProtocolTcpIP MIDDLEWARE_SqlProtocolTcpIP {
          DependsOn            = '[SqlProtocol]MIDDLEWARE_SqlProtocolTcpEnabled'
          PsDscRunAsCredential = $sqlAdminCredential
          InstanceName         = $sqlSPInstance
          IpAddressGroup       = 'IPAll'
          TcpPort              = $sqlTcpPort
        }
      }
      #Configure the SQL Server service
      Service MIDDLEWARE_SqlServerSvcAutomaticRunning {
        DependsOn   = $dependsOnSQLSetup
        Name        = $sqlEngineServiceName
        StartupType = 'Automatic'
        State       = 'Running'
      }
      #Configure the SQL Agent service
      Service MIDDLEWARE_SqlAgentSvcAutomaticRunning {
        DependsOn   = $dependsOnSQLSetup
        Name        = $sqlAgentServiceName
        StartupType = 'Automatic'
        State       = 'Running'
      }
      #Configure the SQL Browser service
      Service MIDDLEWARE_SqlBrowserSvcAutomaticRunning {
        DependsOn   = $dependsOnSQLSetup
        Name        = 'SQLBrowser'
        StartupType = 'Automatic'
        State       = 'Running'
      }
      #Configure SQL sysadmin group - Add the SQLSysAdministrators to sqllogins
      foreach ($sqlSysAdministrator in $Node.SQLSysAdministrators) {
        SqlLogin ('MIDDLEWARE_SqlLogin_' + $sqlSysAdministrator.Replace('\', '-')) {
          DependsOn            = $dependsOnSQLSetup
          PsDscRunAsCredential = $sqlAdminCredential
          Ensure               = 'Present'
          Name                 = $sqlSysAdministrator
          LoginType            = 'WindowsUser'
          ServerName           = $Node.NodeName
          InstanceName         = $sqlSPInstance
        }
      }
      #Configure SQL Server sysadmin role
      SqlRole MIDDLEWARE_SqlSpsServerRole {
        DependsOn            = $dependsOnSQLSetup
        Ensure               = 'Present'
        PsDscRunAsCredential = $sqlAdminCredential
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        ServerRoleName       = 'sysadmin'
        MembersToInclude     = $Node.SQLSysAdministrators
      }
      #Add the farm service account to the dbcreator and securityadmin roles.
      # The FARM login may already have been created by the SQLSysAdministrators
      # loop above (when the farm account is also a SQL sysadmin, the default
      # posture). Creating it again here would produce two SqlLogin resources for
      # the same login, which DSC rejects ("conflicting values of
      # PsDscRunAsCredential"). So create MIDDLEWARE_SqlLogin_FARM only when the
      # farm account is NOT in SQLSysAdministrators, and point the role grants at
      # whichever SqlLogin resource actually exists.
      $farmIsSysAdmin = @($Node.SQLSysAdministrators) -contains $FARM.UserName
      if ($farmIsSysAdmin) {
        $farmLoginDependsOn = '[SqlLogin]MIDDLEWARE_SqlLogin_' + $FARM.UserName.Replace('\', '-')
      }
      else {
        $farmLoginDependsOn = '[SqlLogin]MIDDLEWARE_SqlLogin_FARM'
        SqlLogin MIDDLEWARE_SqlLogin_FARM {
          DependsOn            = $dependsOnSQLSetup
          Ensure               = 'Present'
          PsDscRunAsCredential = $sqlAdminCredential
          Name                 = "$($FARM.UserName)"
          LoginType            = 'WindowsUser'
          ServerName           = $Node.NodeName
          InstanceName         = $sqlSPInstance
        }
      }
      SqlRole MIDDLEWARE_SqlSpsServerRoleADMdbcreator {
        DependsOn            = $farmLoginDependsOn
        Ensure               = 'Present'
        PsDscRunAsCredential = $sqlAdminCredential
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        ServerRoleName       = 'dbcreator'
        MembersToInclude     = "$($FARM.UserName)"
      }
      SqlRole MIDDLEWARE_SqlSpsServerRoleADMsecurityadmin {
        DependsOn            = $farmLoginDependsOn
        Ensure               = 'Present'
        PsDscRunAsCredential = $sqlAdminCredential
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        ServerRoleName       = 'securityadmin'
        MembersToInclude     = "$($FARM.UserName)"
      }
      #Configure SQL Server Max Memory
      if ($null -eq $Node.SQLMaxMemory) {
        SqlMemory MIDDLEWARE_SqlMaxMemory {
          DependsOn            = $dependsOnSQLSetup
          Ensure               = 'Present'
          PsDscRunAsCredential = $sqlAdminCredential
          DynamicAlloc         = $true
          ServerName           = $Node.NodeName
          InstanceName         = $sqlSPInstance
        }
      }
      else {
        SqlMemory MIDDLEWARE_SqlMaxMemory {
          DependsOn            = $dependsOnSQLSetup
          Ensure               = 'Present'
          PsDscRunAsCredential = $sqlAdminCredential
          MaxMemory            = $Node.SQLMaxMemory
          ServerName           = $Node.NodeName
          InstanceName         = $sqlSPInstance
        }
      }
      #Configure SQL Server Max Degree of Parallelism
      SqlMaxDop MIDDLEWARE_SqlMaxDopTo1 {
        DependsOn            = $dependsOnSQLSetup
        Ensure               = 'Present'
        PsDscRunAsCredential = $sqlAdminCredential
        DynamicAlloc         = $false
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        MaxDop               = 1
      }
      # Force TLS encryption of SQL Server connections (opt-in via NonNodeData.SQL.ForceEncryption).
      # Existing farms are unaffected while the flag is absent / $false. The certificate is the
      # pre-staged PFX distributed on the SoftwarePackages share (SQLServerCert by default, already
      # declared in ADC.certificates with its password in Secrets.psd1). NOTE: the SharePoint /
      # client side must trust this certificate (its issuing CA present in the client's
      # LocalMachine\Root), otherwise SharePoint connects with "certificate chain not trusted".
      if ($sqlConfig.ForceEncryption) {
        $sqlCertName = if ($sqlConfig.CertificateName) { $sqlConfig.CertificateName } else { 'SQLServerCert' }
        $sqlCertInfo = $ConfigurationData.NonNodeData.ADC.certificates | Where-Object -FilterScript { $_.Name -eq $sqlCertName }
        if ($null -eq $sqlCertInfo) {
          throw ("NonNodeData.SQL.ForceEncryption is enabled but no ADC certificate named '{0}' was found in NonNodeData.ADC.certificates." -f $sqlCertName)
        }
        # Resolve the real thumbprint from the .cer so SqlSecureConnection binds the exact cert
        # (unlike auto-enrollment setups that pass the subject; here the PFX is known in advance).
        $sqlCertThumbprint = Get-CertThumbprint -CertPath "$($sqlCertInfo.CertPath)"
        #Import the SQL TLS certificate into LocalMachine\My
        PfxImport MIDDLEWARE_SqlCertificateImport {
          DependsOn  = $dependsOnSQLSetup
          Thumbprint = $sqlCertThumbprint.Thumbprint
          Path       = "$($sqlCertInfo.PfxPath)"
          Store      = 'My'
          Location   = 'LocalMachine'
          # Per-cert PFX password: resolves the PSCredential auto-materialised by the secrets loader
          # in Secrets.psd1 (Name = $sqlCertInfo.Name, i.e. 'SQLServerCert').
          Credential = (Get-Variable -Name $sqlCertInfo.Name -ValueOnly)
          Exportable = $true
          Ensure     = 'Present'
        }
        #Bind the certificate to the SQL instance and force encryption. SqlSecureConnection grants
        # the ServiceAccount read access to the private key and restarts the engine to apply.
        SqlSecureConnection MIDDLEWARE_SqlForceEncryption {
          DependsOn            = '[PfxImport]MIDDLEWARE_SqlCertificateImport'
          PsDscRunAsCredential = $sqlAdminCredential
          InstanceName         = $sqlSPInstance
          Thumbprint           = $sqlCertThumbprint.Thumbprint
          ForceEncryption      = $true
          Ensure               = 'Present'
          ServiceAccount       = $SQLSERVER.UserName
          ServerName           = $Node.NodeName
        }
      }
      # Open port on the firewall only when everything is ready, as SharePoint DSC is testing it to start creating the farm.
      # Gated on $sqlTcpPort so the DependsOn / LocalPort references stay valid only when SqlProtocolTcpIP is also emitted.
      if ($null -ne $sqlTcpPort) {
        Firewall AddDatabaseEngineFirewallRule {
          DependsOn   = '[SqlProtocolTcpIP]MIDDLEWARE_SqlProtocolTcpIP'
          Direction   = 'Inbound'
          Name        = 'SQL-Server-Database-Engine-TCP-In'
          DisplayName = 'SQL Server Database Engine (TCP-In)'
          Description = 'Inbound rule for SQL Server to allow TCP traffic for the Database Engine.'
          Group       = 'SQL Server'
          Enabled     = 'True'
          Protocol    = 'TCP'
          LocalPort   = $sqlTcpPort
          Ensure      = 'Present'
        }
      }
    }
  }
  #Run the CfgAppSql configuration with the provided ConfigurationData
  # Note: Import-PowerShellDataFile returns hashtables, so use ForEach-Object
  # (hashtable dot-syntax) instead of Select-Object -ExpandProperty.
  $nodeList = ($configurationData.AllNodes | Where-Object { $_.NodeName -ne '*' } | ForEach-Object { $_.NodeName }) -join ', '
  Write-Host ("[{0}] Compiling CfgAppSql for node(s) : {1}" -f (Get-Date -Format 'o'), $nodeList)
  Write-Host ("[{0}] MOF output path            : {1}" -f (Get-Date -Format 'o'), $mofOutputPath)
  CfgAppSql -ConfigurationData $ConfigurationData -OutputPath $mofOutputPath

  #Checksum the generated MOF files
  New-DscChecksum -Force -Path $mofOutputPath -Verbose
  Write-Host ("[{0}] Compilation complete." -f (Get-Date -Format 'o'))
}
catch {
  # Preserve full error context (script, line number, exception message) before rethrowing.
  Write-Error -Message ("CfgAppSql compilation failed at {0}:{1} - {2}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}
