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

  function ConvertTo-SqlStringLiteral {
    param
    (
      [parameter(Mandatory = $true)]
      [System.String]
      $Value
    )
    return "N'" + $Value.Replace("'", "''") + "'"
  }

  function Test-SqlAgentTime {
    param
    (
      [parameter(Mandatory = $true)]
      [AllowNull()]
      $Value
    )
    $number = 0
    if (-not [int]::TryParse("$Value", [ref]$number)) { return $false }
    return ($number -ge 0 -and $number -le 235959 -and ($number % 100) -lt 60 -and ([math]::Floor($number / 100) % 100) -lt 60)
  }

  function New-SqlMaintenanceScheduleScript {
    param
    (
      [parameter(Mandatory = $true)]
      [System.Object[]]
      $Schedule
    )
    $errors = @()
    $seenNames = @{}
    $rows = @()
    $setStatements = @()
    foreach ($item in $Schedule) {
      $label = if ($item.Name) { "'$($item.Name)'" } else { '<unnamed>' }
      $freqType = 0
      $freqInterval = 0
      $subdayType = 1
      $subdayInterval = 0
      $endTime = 235959
      if ([string]::IsNullOrWhiteSpace($item.Name) -or "$($item.Name)".Length -gt 128) {
        $errors += "$label : Name is required (128 characters max)."
      }
      elseif ($seenNames.ContainsKey("$($item.Name)".ToLowerInvariant())) {
        $errors += "$label : Name is declared more than once."
      }
      else {
        $seenNames["$($item.Name)".ToLowerInvariant()] = $true
      }
      if (-not [int]::TryParse("$($item.FreqType)", [ref]$freqType) -or $freqType -notin 4, 8) {
        $errors += "$label : FreqType must be 4 (daily) or 8 (weekly)."
      }
      elseif (-not [int]::TryParse("$($item.FreqInterval)", [ref]$freqInterval) -or $freqInterval -lt 1 -or $freqInterval -gt $(if ($freqType -eq 8) { 127 } else { 365 })) {
        $errors += "$label : FreqInterval must be 1-127 (weekly day bitmask) or 1-365 (daily, every N days)."
      }
      if ($null -ne $item.SubdayType -and (-not [int]::TryParse("$($item.SubdayType)", [ref]$subdayType) -or $subdayType -notin 1, 4, 8)) {
        $errors += "$label : SubdayType must be 1 (once), 4 (minutes) or 8 (hours)."
      }
      if ($subdayType -ne 1) {
        $maxSubday = if ($subdayType -eq 4) { 59 } else { 23 }
        if (-not [int]::TryParse("$($item.SubdayInterval)", [ref]$subdayInterval) -or $subdayInterval -lt 1 -or $subdayInterval -gt $maxSubday) {
          $errors += "$label : SubdayInterval must be 1-$maxSubday when SubdayType is $subdayType."
        }
      }
      if (-not (Test-SqlAgentTime -Value $item.StartTime)) {
        $errors += "$label : StartTime must be a valid HHMMSS value (e.g. 173000)."
      }
      if ($null -ne $item.EndTime) {
        if (Test-SqlAgentTime -Value $item.EndTime) {
          $endTime = [int]$item.EndTime
        }
        else {
          $errors += "$label : EndTime must be a valid HHMMSS value (e.g. 193000)."
        }
      }
      if ($subdayType -ne 1 -and (Test-SqlAgentTime -Value $item.StartTime) -and $endTime -le [int]$item.StartTime) {
        $errors += "$label : EndTime must be later than StartTime when SubdayType is not 1."
      }
      $jobs = @($item.Jobs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
      if ($jobs.Count -eq 0) {
        $errors += "$label : Jobs must list at least one job name."
      }
      if ($errors.Count -gt 0) { continue }

      $scheduleLiteral = ConvertTo-SqlStringLiteral -Value $item.Name
      $recurrence = if ($freqType -eq 8) { 1 } else { 0 }
      $setStatements += @"
IF NOT EXISTS (SELECT 1 FROM dbo.sysschedules WHERE [name] = $scheduleLiteral)
    EXEC dbo.sp_add_schedule @schedule_name = $scheduleLiteral, @enabled = 1, @freq_type = $freqType, @freq_interval = $freqInterval, @freq_subday_type = $subdayType, @freq_subday_interval = $subdayInterval, @freq_relative_interval = 0, @freq_recurrence_factor = $recurrence, @active_start_time = $([int]$item.StartTime), @active_end_time = $endTime;
"@
      foreach ($job in $jobs) {
        $jobLiteral = ConvertTo-SqlStringLiteral -Value $job
        $rows += "($scheduleLiteral, $jobLiteral)"
        $setStatements += @"
IF NOT EXISTS (SELECT 1 FROM dbo.sysjobs WHERE [name] = $jobLiteral)
    PRINT N'Job not found, skipped: ' + $jobLiteral
ELSE IF NOT EXISTS (SELECT 1 FROM dbo.sysjobschedules js JOIN dbo.sysjobs j ON j.job_id = js.job_id JOIN dbo.sysschedules s ON s.schedule_id = js.schedule_id WHERE j.[name] = $jobLiteral AND s.[name] = $scheduleLiteral)
    EXEC dbo.sp_attach_schedule @job_name = $jobLiteral, @schedule_name = $scheduleLiteral;
"@
      }
    }
    if ($errors.Count -gt 0) {
      throw ("NonNodeData.SQL.MaintenanceSolution.Schedules is invalid:`n - " + ($errors -join "`n - "))
    }
    $wanted = $rows -join ",`n    "
    $testScript = @"
USE [msdb];
SET NOCOUNT ON;
DECLARE @Wanted TABLE (ScheduleName sysname, JobName sysname);
INSERT INTO @Wanted (ScheduleName, JobName) VALUES
    $wanted;
SELECT N'Missing schedule' AS Issue, w.ScheduleName, CAST(NULL AS sysname) AS JobName
FROM (SELECT DISTINCT ScheduleName FROM @Wanted) AS w
WHERE NOT EXISTS (SELECT 1 FROM dbo.sysschedules s WHERE s.[name] = w.ScheduleName)
UNION ALL
SELECT N'Missing link', w.ScheduleName, w.JobName
FROM @Wanted AS w
JOIN dbo.sysjobs j ON j.[name] = w.JobName
WHERE NOT EXISTS (SELECT 1 FROM dbo.sysjobschedules js JOIN dbo.sysschedules s ON s.schedule_id = js.schedule_id WHERE js.job_id = j.job_id AND s.[name] = w.ScheduleName);
"@
    $setScript = "USE [msdb];`nSET NOCOUNT ON;`n" + ($setStatements -join "`n")
    $getScript = @"
USE [msdb];
SET NOCOUNT ON;
DECLARE @Wanted TABLE (ScheduleName sysname, JobName sysname);
INSERT INTO @Wanted (ScheduleName, JobName) VALUES
    $wanted;
SELECT s.[name] AS ScheduleName, j.[name] AS JobName, s.[enabled], s.freq_type, s.freq_interval, s.active_start_time
FROM dbo.sysschedules s
LEFT JOIN dbo.sysjobschedules js ON js.schedule_id = s.schedule_id
LEFT JOIN dbo.sysjobs j ON j.job_id = js.job_id
WHERE s.[name] IN (SELECT ScheduleName FROM @Wanted);
"@
    return @{ Test = $testScript; Set = $setScript; Get = $getScript }
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
      # Ensure the Windows-level SQL resources' RunAs account ($SETUP) is a local
      # admin so it can control the service, write HKLM and grant the cert private
      # key. RunAs $ADSETUP (already a local admin). Mirrors CfgAppSps.
      $dependsOnLocalAdmin = @()
      if ($Node.LocalAdmins) {
        Group MIDDLEWARE_AddSetupAccountToAdminGroup {
          GroupName            = 'Administrators'
          Ensure               = 'Present'
          MembersToInclude     = $Node.LocalAdmins
          Credential           = $ADSETUP
          PsDscRunAsCredential = $ADSETUP
        }
        $dependsOnLocalAdmin = @('[Group]MIDDLEWARE_AddSetupAccountToAdminGroup')
      }
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
          DependsOn              = @($dependsOnSQLSetup) + $dependsOnLocalAdmin
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
          DependsOn            = @('[PfxImport]MIDDLEWARE_SqlCertificateImport') + $dependsOnLocalAdmin
          PsDscRunAsCredential = $sqlAdminCredential
          InstanceName         = $sqlSPInstance
          Thumbprint           = $sqlCertThumbprint.Thumbprint
          ForceEncryption      = $true
          Ensure               = 'Present'
          ServiceAccount       = $SQLSERVER.UserName
          ServerName           = $Node.NodeName
        }
      }
      # Install the Ola Hallengren SQL Server Maintenance Solution (opt-in via
      # NonNodeData.SQL.InstallMaintenanceSolution). The MaintenanceSolution.sql is NOT
      # bundled with the kit (respect Ola's licence): Initialize-SoftwarePackages downloads
      # it from https://ola.hallengren.com onto the SoftwarePackages share in the SQL source
      # folder, so the existing APPLICATION_SqlGetSources copy already places it on the node.
      # A SqlScript resource runs it under the SQL sysadmin RunAs; a tiny generated test
      # script makes the apply idempotent (skipped once the CommandExecute procedure exists
      # in the target database).
      if ($sqlConfig.InstallMaintenanceSolution) {
        $maintConfig = if ($sqlConfig.MaintenanceSolution) { $sqlConfig.MaintenanceSolution } else { @{} }
        $maintScriptName = if ($maintConfig.ScriptFileName) { $maintConfig.ScriptFileName } else { 'MaintenanceSolution.sql' }
        $maintDatabase = if ($maintConfig.DatabaseName) { $maintConfig.DatabaseName } else { 'master' }
        # The Ola .sql: an explicit SourcePath wins, otherwise the copy staged by
        # APPLICATION_SqlGetSources under the local SQL destination folder.
        $maintSetFilePath = if ($maintConfig.SourcePath) {
          $maintConfig.SourcePath
        }
        else {
          Join-Path $sqlDestinationPath $maintScriptName
        }
        # Test script (generated on the node): returns a row when the solution is NOT yet
        # installed, so SqlScript runs Set; returns nothing once CommandExecute exists.
        $maintTestFilePath = Join-Path $sqlDestinationPath 'Test-MaintenanceSolutionInstalled.sql'
        $maintTestQuery = @"
USE [$maintDatabase];
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE [name] = N'CommandExecute' AND [type] = N'P')
    SELECT 1 AS NotInstalled;
"@
        File MIDDLEWARE_SqlMaintenanceTestScript {
          DestinationPath = $maintTestFilePath
          Contents        = $maintTestQuery
          Type            = 'File'
          Force           = $true
          Ensure          = 'Present'
        }
        SqlScript MIDDLEWARE_SqlMaintenanceSolution {
          Id                   = 'MIDDLEWARE_SqlMaintenanceSolution'
          DependsOn            = $dependsOnSQLSetup, '[File]APPLICATION_SqlGetSources', '[File]MIDDLEWARE_SqlMaintenanceTestScript'
          PsDscRunAsCredential = $sqlAdminCredential
          InstanceName         = $sqlSPInstance
          ServerName           = $Node.NodeName
          SetFilePath          = $maintSetFilePath
          TestFilePath         = $maintTestFilePath
          GetFilePath          = $maintTestFilePath
          # Local connection; Optional avoids a certificate-validation failure regardless of
          # whether ForceEncryption is enabled on the instance.
          Encrypt              = 'Optional'
          QueryTimeout         = 0
        }
        # Optional create-only SQL Agent schedules for the Ola jobs (NonNodeData.SQL.MaintenanceSolution.Schedules,
        # empty by default). Existing schedules are never modified, see scripts/sql/README.md.
        $maintSchedules = @($maintConfig.Schedules | Where-Object { $_ })
        if ($maintSchedules.Count -gt 0) {
          $scheduleScripts = New-SqlMaintenanceScheduleScript -Schedule $maintSchedules
          $scheduleTestPath = Join-Path $sqlDestinationPath 'Test-MaintenanceSchedules.sql'
          $scheduleSetPath = Join-Path $sqlDestinationPath 'Set-MaintenanceSchedules.sql'
          $scheduleGetPath = Join-Path $sqlDestinationPath 'Get-MaintenanceSchedules.sql'
          File MIDDLEWARE_SqlMaintenanceSchedulesTestScript {
            DestinationPath = $scheduleTestPath
            Contents        = $scheduleScripts.Test
            Type            = 'File'
            Force           = $true
            Ensure          = 'Present'
            DependsOn       = '[File]APPLICATION_SqlGetSources'
          }
          File MIDDLEWARE_SqlMaintenanceSchedulesSetScript {
            DestinationPath = $scheduleSetPath
            Contents        = $scheduleScripts.Set
            Type            = 'File'
            Force           = $true
            Ensure          = 'Present'
            DependsOn       = '[File]APPLICATION_SqlGetSources'
          }
          File MIDDLEWARE_SqlMaintenanceSchedulesGetScript {
            DestinationPath = $scheduleGetPath
            Contents        = $scheduleScripts.Get
            Type            = 'File'
            Force           = $true
            Ensure          = 'Present'
            DependsOn       = '[File]APPLICATION_SqlGetSources'
          }
          SqlScript MIDDLEWARE_SqlMaintenanceSchedules {
            Id                   = 'MIDDLEWARE_SqlMaintenanceSchedules'
            DependsOn            = '[SqlScript]MIDDLEWARE_SqlMaintenanceSolution', '[File]MIDDLEWARE_SqlMaintenanceSchedulesTestScript', '[File]MIDDLEWARE_SqlMaintenanceSchedulesSetScript', '[File]MIDDLEWARE_SqlMaintenanceSchedulesGetScript'
            PsDscRunAsCredential = $sqlAdminCredential
            InstanceName         = $sqlSPInstance
            ServerName           = $Node.NodeName
            SetFilePath          = $scheduleSetPath
            TestFilePath         = $scheduleTestPath
            GetFilePath          = $scheduleGetPath
            Encrypt              = 'Optional'
            QueryTimeout         = 0
          }
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
