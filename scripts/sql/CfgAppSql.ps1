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

    #For all servers with SQL Server Role
    Node $AllNodes.Where{ $_.IsSQLServer }.Nodename {
      #Initialize variables for SQL Source Path
      $sqlSourcePath = "$($ConfigurationData.NonNodeData.SourcePath)\SQL"
      $sqlDestinationPath = "$($ConfigurationData.NonNodeData.Drives.Data)\SoftwarePackages\SQL"
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
        Credential      = $PULLSETUP
      }
      #Initialize the SQL Server Instance variable
      $sqlSPInstance = $Node.SQLInstanceName
      $sqlTcpPort = $Node.SQLTcpPort
      # Default to a universally-declared sentinel resource so the configure-only
      # resources below don't dangle when IsSQLSetup=$False (pre-existing SQL).
      # When IsSQLSetup=$True, the override inside the if-block makes everything
      # wait for SqlSetup instead, preserving the install-then-configure ordering.
      $dependsOnSQLSetup = '[Service]SYSTEM_SvcTWerSvcDisableStopped'
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
        SqlProtocolTcpIP MIDDLEWARE_SqlProtocolTcpIP {
          DependsOn            = $dependsOnSQLSetup
          PsDscRunAsCredential = $ADSETUP
          InstanceName         = $sqlSPInstance
          IpAddressGroup       = 'IPAll'
          TcpPort              = $sqlTcpPort
        }
      }
      #Configure the SQL Server service
      Service MIDDLEWARE_SqlServerSvcAutomaticRunning {
        DependsOn   = $dependsOnSQLSetup
        Name        = 'MSSQLSERVER'
        StartupType = 'Automatic'
        State       = 'Running'
      }
      #Configure the SQL Agent service
      Service MIDDLEWARE_SqlAgentSvcAutomaticRunning {
        DependsOn   = $dependsOnSQLSetup
        Name        = 'SQLSERVERAGENT'
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
          PsDscRunAsCredential = $ADSETUP
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
        PsDscRunAsCredential = $ADSETUP
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        ServerRoleName       = 'sysadmin'
        MembersToInclude     = $Node.SQLSysAdministrators
      }
      #Add the farm service account to the dbcreator and securityadmin roles
      SqlLogin MIDDLEWARE_SqlLogin_FARM {
        DependsOn            = $dependsOnSQLSetup
        Ensure               = 'Present'
        PsDscRunAsCredential = $ADSETUP
        Name                 = "$($FARM.UserName)"
        LoginType            = 'WindowsUser'
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
      }
      SqlRole MIDDLEWARE_SqlSpsServerRoleADMdbcreator {
        DependsOn            = '[SqlLogin]MIDDLEWARE_SqlLogin_FARM'
        Ensure               = 'Present'
        PsDscRunAsCredential = $ADSETUP
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        ServerRoleName       = 'dbcreator'
        MembersToInclude     = "$($FARM.UserName)"
      }
      SqlRole MIDDLEWARE_SqlSpsServerRoleADMsecurityadmin {
        DependsOn            = '[SqlLogin]MIDDLEWARE_SqlLogin_FARM'
        Ensure               = 'Present'
        PsDscRunAsCredential = $ADSETUP
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
          PsDscRunAsCredential = $ADSETUP
          DynamicAlloc         = $true
          ServerName           = $Node.NodeName
          InstanceName         = $sqlSPInstance
        }
      }
      else {
        SqlMemory MIDDLEWARE_SqlMaxMemory {
          DependsOn            = $dependsOnSQLSetup
          Ensure               = 'Present'
          PsDscRunAsCredential = $ADSETUP
          MaxMemory            = $Node.SQLMaxMemory
          ServerName           = $Node.NodeName
          InstanceName         = $sqlSPInstance
        }
      }
      #Configure SQL Server Max Degree of Parallelism
      SqlMaxDop MIDDLEWARE_SqlMaxDopTo1 {
        DependsOn            = $dependsOnSQLSetup
        Ensure               = 'Present'
        PsDscRunAsCredential = $ADSETUP
        DynamicAlloc         = $false
        ServerName           = $Node.NodeName
        InstanceName         = $sqlSPInstance
        MaxDop               = 1
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
