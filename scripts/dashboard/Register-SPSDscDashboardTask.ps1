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
  Registers (or updates) a Scheduled Task on the pull server that regenerates the
  DSC compliance dashboard on a schedule.

  .DESCRIPTION
  New-SPSDscDashboard.ps1 produces a point-in-time, self-contained HTML snapshot;
  it has no server-side runtime, so "refreshing" the dashboard means regenerating
  the file. Running it by hand is not viable, so this helper installs a Scheduled
  Task that runs it periodically and writes the HTML into the IIS-served folder
  (by default the pull server's site), so the team just browses
  https://<pull>/Dashboard.html and always sees a current snapshot.

  The task runs as SYSTEM by default, which can reach the local pull server over
  localhost and read a local manifest folder. If the node manifest is on a remote
  share, run the task under a domain account that can read it (-RunAsUser).

  Run this ONCE, in an elevated session, on the pull server. It is idempotent:
  re-running updates the existing task in place.

  .PARAMETER IntervalMinutes
  How often to regenerate the dashboard, in minutes. Minimum 30 (enforced): the
  LCMs only submit a new status report on their consistency interval
  (ConfigurationModeFrequencyMins, typically 60-120 minutes), so refreshing more
  often than every 30 minutes adds load without surfacing any newer data. Align
  this with your farm's LCM interval (e.g. 30 for a 60-minute LCM, 60 for a
  120-minute LCM). Default 30.

  .PARAMETER PullServerUrl
  Base URL of the pull server OData service passed through to
  New-SPSDscDashboard.ps1. Default 'https://localhost/PSDSCPullServer.svc'.

  .PARAMETER NodeManifestPath
  Folder of per-node <NodeName>.json entries (published by CfgLcmPull.ps1) that
  the dashboard reads to discover nodes. Required — passed through to
  New-SPSDscDashboard.ps1.

  .PARAMETER OutputPath
  Where the task writes the HTML. Default the pull server IIS site root
  'C:\inetpub\PSDSCPullServer\Dashboard.html' so it is served over HTTPS.

  .PARAMETER DashboardScriptPath
  Full path to New-SPSDscDashboard.ps1. Defaults to the copy next to this script.

  .PARAMETER TaskName
  Scheduled Task name. Default 'SPSConfigKit-DscDashboard'.

  .PARAMETER RunAsUser
  Account the task runs under. Default 'SYSTEM'. Use a domain account when the
  node manifest or output path is on a remote share the machine account cannot
  reach. When a non-system account is supplied, pass -RunAsPassword too.

  .PARAMETER RunAsPassword
  SecureString password for -RunAsUser when it is not a well-known service account
  (SYSTEM / LOCAL SERVICE / NETWORK SERVICE).

  .PARAMETER SkipCertificateCheck
  Forwarded to New-SPSDscDashboard.ps1 for self-signed pull-server certificates.

  .PARAMETER RunNow
  Also start the task once immediately after registering, to produce a first
  dashboard without waiting for the first trigger.

  .EXAMPLE
  # Refresh every 30 minutes as SYSTEM, served by the pull server IIS site
  .\Register-SPSDscDashboardTask.ps1 -NodeManifestPath 'F:\DscNodeManifest' -SkipCertificateCheck -RunNow

  .EXAMPLE
  # Farm with a 120-minute LCM: refresh every 60 minutes
  .\Register-SPSDscDashboardTask.ps1 -NodeManifestPath 'F:\DscNodeManifest' -IntervalMinutes 60 -SkipCertificateCheck

  .NOTES
  Project : SPSConfigKit
  Requires: PowerShell 5.1, elevated session on the pull server.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter()]
  [ValidateRange(30, 1440)]
  [System.Int32]
  $IntervalMinutes = 30,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $PullServerUrl = 'https://localhost/PSDSCPullServer.svc',

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $NodeManifestPath,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $OutputPath = 'C:\inetpub\PSDSCPullServer\Dashboard.html',

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $DashboardScriptPath,

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $TaskName = 'SPSConfigKit-DscDashboard',

  [Parameter()]
  [ValidateNotNullOrEmpty()]
  [System.String]
  $RunAsUser = 'SYSTEM',

  [Parameter()]
  [System.Security.SecureString]
  $RunAsPassword,

  [Parameter()]
  [switch]
  $SkipCertificateCheck,

  [Parameter()]
  [switch]
  $RunNow
)

$ErrorActionPreference = 'Stop'
$startDate = Get-Date

# Resolve the dashboard script path (defaults to the copy alongside this helper).
$scriptBasePath = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($DashboardScriptPath)) {
  $DashboardScriptPath = Join-Path -Path $scriptBasePath -ChildPath 'New-SPSDscDashboard.ps1'
}
if (-not (Test-Path -LiteralPath $DashboardScriptPath)) {
  throw ("Dashboard script not found at '{0}'. Pass -DashboardScriptPath." -f $DashboardScriptPath)
}
$DashboardScriptPath = (Resolve-Path -LiteralPath $DashboardScriptPath).Path

Write-Host '-----------------------------------------------'
Write-Host '| SPSConfigKit - Register-SPSDscDashboardTask'
Write-Host ("| Started on      {0}" -f $startDate.ToString('o'))
Write-Host ("| Task name       {0}" -f $TaskName)
Write-Host ("| Interval        {0} minute(s)" -f $IntervalMinutes)
Write-Host ("| Dashboard       {0}" -f $DashboardScriptPath)
Write-Host ("| Output          {0}" -f $OutputPath)
Write-Host ("| Run as          {0}" -f $RunAsUser)
Write-Host '-----------------------------------------------'

# Emphasise the 30-minute floor. ValidateRange already blocks < 30, but call out
# why so operators align the cadence with their LCM interval instead of chasing
# a lower number that surfaces no newer data.
if ($IntervalMinutes -lt 60) {
  Write-Host ("[i] Refresh interval is {0} min. This is the practical floor — DSC nodes only report on their LCM consistency interval (ConfigurationModeFrequencyMins, typically 60-120 min), so a shorter refresh adds load without newer data. Align it with your farm's LCM interval." -f $IntervalMinutes)
}

# Build the argument line for New-SPSDscDashboard.ps1.
$scriptArgs = @(
  '-NoProfile'
  '-ExecutionPolicy'; 'Bypass'
  '-File'; ('"{0}"' -f $DashboardScriptPath)
  '-PullServerUrl'; ('"{0}"' -f $PullServerUrl)
  '-NodeManifestPath'; ('"{0}"' -f $NodeManifestPath)
  '-OutputPath'; ('"{0}"' -f $OutputPath)
)
if ($SkipCertificateCheck) { $scriptArgs += '-SkipCertificateCheck' }
$argumentString = $scriptArgs -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentString

# Repeating trigger: start now, repeat every IntervalMinutes indefinitely.
$trigger = New-ScheduledTaskTrigger -Once -At $startDate `
  -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

# Principal: well-known service accounts need no password; a domain account does.
$wellKnown = @('SYSTEM', 'NT AUTHORITY\SYSTEM', 'LOCAL SERVICE', 'NT AUTHORITY\LOCAL SERVICE', 'NETWORK SERVICE', 'NT AUTHORITY\NETWORK SERVICE')
$isWellKnown = $wellKnown -contains $RunAsUser.ToUpperInvariant() -or $wellKnown -contains $RunAsUser

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
  -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

$registerArgs = @{
  TaskName    = $TaskName
  Action      = $action
  Trigger     = $trigger
  Settings    = $settings
  Description = 'SPSConfigKit — regenerates the DSC compliance dashboard (New-SPSDscDashboard.ps1) on a schedule.'
  Force       = $true
}

if ($isWellKnown) {
  $registerArgs.Principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType ServiceAccount -RunLevel Highest
}
else {
  if (-not $RunAsPassword) {
    throw ("-RunAsUser '{0}' is not a well-known service account, so -RunAsPassword is required." -f $RunAsUser)
  }
  $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($RunAsPassword))
  $registerArgs.User = $RunAsUser
  $registerArgs.Password = $plainPassword
  $registerArgs.RunLevel = 'Highest'
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$verb = if ($existing) { 'Updating' } else { 'Registering' }

if ($PSCmdlet.ShouldProcess($TaskName, "$verb scheduled task")) {
  Write-Host ("{0} scheduled task '{1}'..." -f $verb, $TaskName)
  Register-ScheduledTask @registerArgs | Out-Null
  Write-Host ("[+] Scheduled task '{0}' is registered; next run within {1} minute(s)." -f $TaskName, $IntervalMinutes)

  if ($RunNow) {
    Write-Host 'Starting the task once now...'
    Start-ScheduledTask -TaskName $TaskName
    Write-Host ("[+] Task started; '{0}' will be written shortly." -f $OutputPath)
  }
}

$endDate = Get-Date
Write-Host '-----------------------------------------------'
Write-Host '| Register-SPSDscDashboardTask complete'
Write-Host ("| Duration        {0}" -f ($endDate - $startDate))
Write-Host '-----------------------------------------------'
