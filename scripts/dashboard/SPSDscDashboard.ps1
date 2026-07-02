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
<#
  .SYNOPSIS
  Generates a self-contained HTML compliance dashboard for a classic Windows DSC
  pull server, and installs/removes a Scheduled Task that keeps it refreshed.

  .DESCRIPTION
  Driven by -Action, backed by a settings file (SPSDscDashboard.psd1):

    * Default   - Generate Dashboard.html once. Queries the pull server's OData
                  reporting API (PSDSCPullServer.svc) for every registered node
                  and its latest status report, classifies each node as
                  Compliant / NonCompliant / Failed / Unresponsive, and renders a
                  single self-contained HTML page (inline CSS + SVG donut, no
                  external framework, no CDN — works on an offline pull server).
    * Install   - Register (or update) a Scheduled Task on the pull server that
                  runs this script with -Action Default on a schedule, writing the
                  HTML into the IIS-served folder so it stays current with no
                  manual run.
    * Uninstall - Remove that Scheduled Task.

  All settings come from SPSDscDashboard.psd1 next to this script (override the
  path with -InputFile). The only runtime inputs are -Action and, for a scheduled
  task that must run under a domain account, -InstallAccount.

  Data source rationale: the classic xDscWebService pull server's OData API
  cannot enumerate nodes — GET /Nodes returns HTTP 400 ("resourceKeys is
  unexpected for MSFT.DSCNode") because the provider exposes only keyed access,
  and Devices.edb is exclusively locked by IIS so it can't be read directly
  either. The node list therefore comes from a manifest folder each node
  populates at registration time (CfgLcmPull.ps1 -NodeManifestPath); this script
  then queries the supported keyed endpoint Nodes(AgentId='...')/Reports for
  each. See scripts/dashboard/README.md.

  .PARAMETER Action
  Default (generate the HTML), Install (register the refresh Scheduled Task) or
  Uninstall (remove it). Default 'Default'.

  .PARAMETER InstallAccount
  (Install) Credential the Scheduled Task runs under. Omit to run as SYSTEM
  (fine for a local manifest folder and a localhost pull server). Supply a domain
  account when the node manifest is on a remote share the machine account cannot
  read.

  .PARAMETER InputFile
  Path to the settings .psd1. Defaults to SPSDscDashboard.psd1 next to this script.
  All other settings (PullServerUrl, NodeManifestPath, OutputPath, Title,
  MaxReportsPerNode, SkipCertificateCheck, MockDataPath and the Schedule block)
  live in that file.

  .EXAMPLE
  # Generate once, using SPSDscDashboard.psd1 for all settings
  .\SPSDscDashboard.ps1

  .EXAMPLE
  # Install the refresh Scheduled Task (settings from the psd1)
  .\SPSDscDashboard.ps1 -Action Install

  .EXAMPLE
  # Install the task running under a domain account (remote manifest share)
  .\SPSDscDashboard.ps1 -Action Install -InstallAccount (Get-Credential 'CONTOSO\svcdash')

  .NOTES
  Project : SPSConfigKit
  Requires: PowerShell 5.1. Install/Uninstall require an elevated session.
  Reporting API: https://learn.microsoft.com/en-us/powershell/dsc/pull-server/reportserver
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Position = 0)]
  [ValidateSet('Default', 'Install', 'Uninstall', IgnoreCase = $true)]
  [System.String]
  $Action = 'Default',

  [Parameter(Position = 1)]
  [System.Management.Automation.PSCredential]
  $InstallAccount,

  [Parameter(Position = 2)]
  [System.String]
  $InputFile
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Settings: everything comes from SPSDscDashboard.psd1 (no per-value parameters,
# same convention as SPSWakeUp / SPSUserSync). -InputFile points at another copy;
# -InstallAccount (a PSCredential) is the only runtime input, used as the
# Scheduled Task principal for -Action Install.
# ---------------------------------------------------------------------------
$scriptBase = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($InputFile)) {
  $InputFile = Join-Path -Path $scriptBase -ChildPath 'SPSDscDashboard.psd1'
}
if (-not (Test-Path -LiteralPath $InputFile)) {
  throw ("Settings file not found at '{0}'. It ships with the kit; pass -InputFile to point at another copy." -f $InputFile)
}
$settings = Import-PowerShellDataFile -Path $InputFile
$schedule = if ($settings.Schedule) { $settings.Schedule } else { @{} }

function Get-SettingValue {
  param($Value, $Default)
  if ($null -ne $Value) { return $Value }
  return $Default
}

$PullServerUrl        = Get-SettingValue $settings.PullServerUrl     'https://localhost/PSDSCPullServer.svc'
$OutputPath           = Get-SettingValue $settings.OutputPath        (Join-Path -Path $scriptBase -ChildPath 'Dashboard.html')
$Title                = Get-SettingValue $settings.Title             'SharePoint Farm — DSC Compliance'
$MaxReportsPerNode    = Get-SettingValue $settings.MaxReportsPerNode 50
$NodeManifestPath     = $settings.NodeManifestPath
$MockDataPath         = $settings.MockDataPath
$SkipCertificateCheck = [bool]$settings.SkipCertificateCheck
$IntervalMinutes      = Get-SettingValue $schedule.IntervalMinutes   30
$TaskName             = Get-SettingValue $schedule.TaskName          'SPSConfigKit-DscDashboard'
$RunAfterInstall      = if ($null -ne $schedule.RunAfterInstall) { [bool]$schedule.RunAfterInstall } else { $true }

if ($IntervalMinutes -lt 30) {
  throw ("Schedule.IntervalMinutes is {0}; the minimum is 30. Nodes only report on their LCM consistency interval (typically 60-120 min), so a shorter refresh adds load without newer data." -f $IntervalMinutes)
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function ConvertTo-HtmlText {
  # Minimal HTML-encode so node names / errors can't break the markup.
  param([System.String] $Text)
  if ($null -eq $Text) { return '' }
  return ($Text -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;')
}

function ConvertFrom-DscStatusData {
  <#
    StatusData is a doubly JSON-encoded array: an OData array whose single element
    is a JSON string that itself parses to the status object. See research report.
  #>
  param($StatusData)
  if ($null -eq $StatusData) { return $null }
  try {
    $first = if ($StatusData -is [System.Array]) { $StatusData[0] } else { $StatusData }
    $parsed = $first | ConvertFrom-Json
    if ($parsed -is [System.String]) { $parsed = $parsed | ConvertFrom-Json }
    return $parsed
  }
  catch {
    Write-Warning "Unable to parse StatusData: $($_.Exception.Message)"
    return $null
  }
}

function Invoke-DscPullApi {
  param([System.String] $Uri)
  $headers = @{ Accept = 'application/json'; ProtocolVersion = '2.0' }
  $splat = @{
    Uri             = $Uri
    Headers         = $headers
    UseBasicParsing = $true
    Method          = 'Get'
  }
  # PS 7 supports -SkipCertificateCheck natively; PS 5.1 needs the callback shim.
  if ($SkipCertificateCheck -and $PSVersionTable.PSEdition -ne 'Core') {
    Add-Type -TypeDefinition @'
using System.Net;
using System.Security.Cryptography.X509Certificates;
public static class SpsCertBypass {
  public static void Enable() {
    ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
  }
}
'@ -ErrorAction SilentlyContinue
    [SpsCertBypass]::Enable()
  }
  elseif ($SkipCertificateCheck) {
    $splat.SkipCertificateCheck = $true
  }
  $resp = Invoke-WebRequest @splat
  return ($resp.Content | ConvertFrom-Json)
}

function Get-DscNodeData {
  <#
    Returns the raw { Nodes = @(); Reports = @{ AgentId = @(reports) } } shape,
    from either the node manifest + live OData API, or the mock file. Both feed
    the same normaliser.

    The classic xDscWebService pull server cannot enumerate nodes over OData:
    GET /Nodes returns HTTP 400 ("resourceKeys is unexpected for MSFT.DSCNode")
    because the provider only exposes keyed access. So the node list comes from
    the manifest folder each node populates at registration time
    (CfgLcmPull.ps1 -NodeManifestPath), and this function then queries the
    supported keyed endpoint Nodes(AgentId='...')/Reports for each one.
  #>
  param()
  if ($MockDataPath) {
    if (-not (Test-Path -LiteralPath $MockDataPath)) { throw "MockDataPath not found: $MockDataPath" }
    $mock = Get-Content -LiteralPath $MockDataPath -Raw | ConvertFrom-Json
    return $mock
  }

  if (-not $NodeManifestPath) {
    throw "Provide -NodeManifestPath (the shared folder where CfgLcmPull.ps1 publishes each node's AgentId) or -MockDataPath. The pull server's OData API cannot enumerate nodes on its own."
  }
  if (-not (Test-Path -LiteralPath $NodeManifestPath)) {
    throw "NodeManifestPath not found: $NodeManifestPath"
  }

  $baseUrl = $PullServerUrl.TrimEnd('/')
  Write-Host "Reading node manifest: $NodeManifestPath"
  $manifestFiles = @(Get-ChildItem -LiteralPath $NodeManifestPath -Filter '*.json' -File -ErrorAction SilentlyContinue)
  if ($manifestFiles.Count -eq 0) {
    Write-Warning "No node manifest entries (*.json) found in '$NodeManifestPath'. Have the nodes run CfgLcmPull.ps1 -NodeManifestPath yet?"
  }

  $nodes = @()
  $reports = @{}
  foreach ($file in $manifestFiles) {
    try {
      $entry = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    }
    catch {
      Write-Warning "Skipping unreadable manifest '$($file.Name)': $($_.Exception.Message)"
      continue
    }
    $agentId = $entry.AgentId
    if (-not $agentId) { continue }
    $nodes += $entry

    Write-Host "Querying reports for $($entry.NodeName) ($agentId)"
    try {
      $rResp = Invoke-DscPullApi -Uri "$baseUrl/Nodes(AgentId='$agentId')/Reports"
      $reports[$agentId] = @($rResp.value)
    }
    catch {
      Write-Warning "No reports for node $($entry.NodeName) ($agentId): $($_.Exception.Message)"
      $reports[$agentId] = @()
    }
  }
  return [pscustomobject]@{ Nodes = $nodes; Reports = $reports }
}

function ConvertTo-NodeCompliance {
  <#
    Normalises one node + its reports into a flat compliance object the renderer
    consumes. Compliance rules per the research report (reportserver docs +
    DSCPullServerAdmin).
  #>
  param($Node, $Reports)

  $agentId = $Node.AgentId
  $nodeName = if ($Node.NodeName) { $Node.NodeName } else { $agentId }
  $configName = if ($Node.ConfigurationNames) { ($Node.ConfigurationNames -join ', ') } else { '' }

  # Compliance-relevant reports only (skip LCM meta-config runs), latest first.
  $relevant = @($Reports | Where-Object { $_.OperationType -ne 'LocalConfigurationManager' })
  $latest = $relevant |
    Sort-Object { if ($_.StartTime) { [DateTime]$_.StartTime } else { [DateTime]::MinValue } } -Descending |
    Select-Object -First 1

  $state = 'Unresponsive'
  $lastSeen = $null
  $inCount = 0
  $notCount = 0
  $duration = $null
  $errors = @()
  $resources = @()
  $configVersion = ''

  if ($latest) {
    $lastSeen = $latest.EndTime
    $configVersion = [string]$latest.ConfigurationVersion
    $errors = @($latest.Errors | Where-Object { $_ })
    $sd = ConvertFrom-DscStatusData -StatusData $latest.StatusData

    if ($sd) {
      $inList = @($sd.ResourcesInDesiredState) | Where-Object { $_ }
      $notList = @($sd.ResourcesNotInDesiredState) | Where-Object { $_ }
      $duration = $sd.DurationInSeconds

      # Tag each resource's compliance by the LIST it came from — that is the
      # authoritative signal. The per-resource InDesiredState property is not
      # reliable in pull consistency reports (a drifted resource can carry a
      # stale True), which previously hid the drifted resource behind an "In
      # state" pill. Drifted resources are added first and win any ResourceId
      # collision so a resource present in both lists renders as drifted.
      $seen = @{}
      foreach ($r in $notList) {
        $rid = [string]$r.ResourceId
        $resources += [pscustomobject]@{
          ResourceId        = $rid
          ModuleName        = [string]$r.ModuleName
          ModuleVersion     = [string]$r.ModuleVersion
          InDesiredState    = $false
          DurationInSeconds = [string]$r.DurationInSeconds
          Error             = [string]$r.Error
        }
        if ($rid) { $seen[$rid] = $true }
      }
      foreach ($r in $inList) {
        $rid = [string]$r.ResourceId
        if ($rid -and $seen.ContainsKey($rid)) { continue }
        $resources += [pscustomobject]@{
          ResourceId        = $rid
          ModuleName        = [string]$r.ModuleName
          ModuleVersion     = [string]$r.ModuleVersion
          InDesiredState    = $true
          DurationInSeconds = [string]$r.DurationInSeconds
          Error             = [string]$r.Error
        }
      }

      # Counts derive from the de-duplicated resource set so the summary, the
      # drift ratio and the detail table always agree.
      $notCount = @($resources | Where-Object { -not $_.InDesiredState }).Count
      $inCount = @($resources | Where-Object { $_.InDesiredState }).Count
    }

    if (($latest.Status -eq 'Failure') -or ($errors.Count -gt 0)) {
      $state = 'Failed'
    }
    elseif ($notCount -gt 0) {
      $state = 'NonCompliant'
    }
    elseif ($latest.Status -eq 'Success') {
      $state = 'Compliant'
    }
    else {
      $state = 'Unknown'
    }
  }

  return [pscustomobject]@{
    NodeName             = $nodeName
    AgentId              = $agentId
    ConfigurationName    = $configName
    ConfigurationVersion = $configVersion
    ComplianceState      = $state
    LastSeen             = $lastSeen
    ResourcesInDesired   = $inCount
    ResourcesNotInDesired = $notCount
    TotalResources       = ($inCount + $notCount)
    DurationInSeconds    = $duration
    Errors               = $errors
    Resources            = $resources
    ReportCount          = $relevant.Count
  }
}

# ---------------------------------------------------------------------------
# HTML rendering
# ---------------------------------------------------------------------------

function New-DashboardHtml {
  param(
    [System.Object[]] $Nodes,
    [System.String]   $Heading
  )

  $stateMeta = @{
    Compliant    = @{ Label = 'Compliant';     Var = '--ok' }
    NonCompliant = @{ Label = 'Non-Compliant'; Var = '--warn' }
    Failed       = @{ Label = 'Failed';        Var = '--err' }
    Unresponsive = @{ Label = 'Unresponsive';  Var = '--muted-fg' }
    Unknown      = @{ Label = 'Unknown';       Var = '--muted-fg' }
    Pending      = @{ Label = 'Pending';       Var = '--muted-fg' }
  }

  $total = $Nodes.Count
  $counts = @{ Compliant = 0; NonCompliant = 0; Failed = 0; Other = 0 }
  foreach ($n in $Nodes) {
    switch ($n.ComplianceState) {
      'Compliant' { $counts.Compliant++ }
      'NonCompliant' { $counts.NonCompliant++ }
      'Failed' { $counts.Failed++ }
      default { $counts.Other++ }
    }
  }
  $compliantPct = if ($total -gt 0) { [math]::Round(($counts.Compliant / $total) * 100) } else { 0 }

  # SVG donut geometry (stroke-dasharray on a circle, no chart library).
  $radius = 80.0
  $circ = 2 * [math]::PI * $radius
  $segCompliant = if ($total -gt 0) { $circ * ($counts.Compliant / $total) } else { 0 }
  $segNon = if ($total -gt 0) { $circ * ($counts.NonCompliant / $total) } else { 0 }
  $segFailed = if ($total -gt 0) { $circ * ($counts.Failed / $total) } else { 0 }
  $segOther = if ($total -gt 0) { $circ * ($counts.Other / $total) } else { 0 }
  # dashoffset stacks the segments around the ring.
  $offNon = -$segCompliant
  $offFailed = -($segCompliant + $segNon)
  $offOther = -($segCompliant + $segNon + $segFailed)

  $generated = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

  # --- rows ---
  $rowsHtml = ''
  $detailsHtml = ''
  foreach ($n in ($Nodes | Sort-Object @{ Expression = {
          switch ($_.ComplianceState) { 'Failed' { 0 } 'NonCompliant' { 1 } 'Unresponsive' { 2 } 'Compliant' { 4 } default { 3 } } }
      }, NodeName)) {
    $meta = $stateMeta[$n.ComplianceState]
    if (-not $meta) { $meta = $stateMeta['Unknown'] }
    $lastSeenTxt = if ($n.LastSeen) { ([DateTime]$n.LastSeen).ToString('yyyy-MM-dd HH:mm') } else { '—' }
    $driftTxt = if ($n.ComplianceState -eq 'Unresponsive') { '—' } else { "$($n.ResourcesNotInDesired) / $($n.TotalResources)" }
    $anchor = 'node-' + ($n.AgentId -replace '[^A-Za-z0-9]', '')

    $rowsHtml += @"
      <tr>
        <td><a class="node-link" href="#$anchor">$(ConvertTo-HtmlText $n.NodeName)</a></td>
        <td><span class="pill" style="--pill: var($($meta.Var));">$($meta.Label)</span></td>
        <td class="mono">$(ConvertTo-HtmlText $n.ConfigurationName)</td>
        <td class="mono">$(ConvertTo-HtmlText ([string]$n.ConfigurationVersion))</td>
        <td>$driftTxt</td>
        <td class="mono">$lastSeenTxt</td>
      </tr>

"@

    # drill-down
    $resRows = ''
    foreach ($r in ($n.Resources | Sort-Object InDesiredState, ResourceId)) {
      $rState = if ($r.InDesiredState) { '<span class="pill sm" style="--pill: var(--ok);">In state</span>' } else { '<span class="pill sm" style="--pill: var(--warn);">Drift</span>' }
      $errCell = if ($r.Error) { ConvertTo-HtmlText $r.Error } else { '' }
      $resRows += @"
          <tr>
            <td class="mono">$(ConvertTo-HtmlText $r.ResourceId)</td>
            <td class="mono">$(ConvertTo-HtmlText $r.ModuleName) $(ConvertTo-HtmlText $r.ModuleVersion)</td>
            <td>$rState</td>
            <td class="mono">$(ConvertTo-HtmlText $r.DurationInSeconds)s</td>
            <td class="err-cell">$errCell</td>
          </tr>

"@
    }
    if (-not $resRows) { $resRows = '<tr><td colspan="5" class="muted">No resource data in the latest report.</td></tr>' }

    $errBanner = ''
    if ($n.Errors.Count -gt 0) {
      $errList = ($n.Errors | ForEach-Object { '<li>' + (ConvertTo-HtmlText ([string]$_)) + '</li>' }) -join ''
      $errBanner = "<div class=`"err-banner`"><strong>Errors</strong><ul>$errList</ul></div>"
    }

    $metaDetail = $stateMeta[$n.ComplianceState]; if (-not $metaDetail) { $metaDetail = $stateMeta['Unknown'] }
    $detailsHtml += @"
    <details class="node-card" id="$anchor">
      <summary>
        <span class="pill" style="--pill: var($($metaDetail.Var));">$($metaDetail.Label)</span>
        <span class="node-name">$(ConvertTo-HtmlText $n.NodeName)</span>
        <span class="agent mono">$(ConvertTo-HtmlText $n.AgentId)</span>
      </summary>
      <div class="node-body">
        <div class="kv">
          <div><span class="k">Configuration</span><span class="v mono">$(ConvertTo-HtmlText $n.ConfigurationName) $(ConvertTo-HtmlText ([string]$n.ConfigurationVersion))</span></div>
          <div><span class="k">Last report</span><span class="v mono">$(if ($n.LastSeen) { ([DateTime]$n.LastSeen).ToString('yyyy-MM-dd HH:mm:ss') } else { '—' })</span></div>
          <div><span class="k">Run duration</span><span class="v mono">$(if ($n.DurationInSeconds) { "$($n.DurationInSeconds)s" } else { '—' })</span></div>
          <div><span class="k">Resources</span><span class="v">$($n.ResourcesInDesired) in state, $($n.ResourcesNotInDesired) drifted</span></div>
        </div>
        $errBanner
        <table class="res-table">
          <thead><tr><th>Resource</th><th>Module</th><th>State</th><th>Duration</th><th>Error</th></tr></thead>
          <tbody>
$resRows
          </tbody>
        </table>
      </div>
    </details>

"@
  }

  $emptyNote = if ($total -eq 0) { '<p class="muted">No registered nodes returned by the pull server.</p>' } else { '' }

  $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>$(ConvertTo-HtmlText $Heading)</title>
<style>
  :root {
    --background: hsl(216 13% 15%);
    --bg-glow: hsl(216 20% 22%);
    --card: hsl(216 13% 13%);
    --card-2: hsl(216 13% 17%);
    --foreground: hsl(219 18% 82%);
    --muted-fg: hsl(216 12% 60%);
    --border: hsl(216 6% 26%);
    --primary: hsl(213 90% 62%);
    --primary-2: hsl(199 89% 55%);
    --ok: hsl(152 58% 45%);
    --warn: hsl(38 92% 55%);
    --err: hsl(3 85% 56%);
    --shadow: 0 10px 30px rgba(0,0,0,.35);
    --card-tint: rgba(255,255,255,.04);
    --card-tint-2: rgba(255,255,255,.01);
    --hover: rgba(255,255,255,.02);
    --radius: 14px;
  }
  html[data-theme="light"] {
    --background: hsl(210 20% 97%);
    --bg-glow: hsl(213 60% 92%);
    --card: hsl(0 0% 100%);
    --card-2: hsl(214 20% 96%);
    --foreground: hsl(216 25% 22%);
    --muted-fg: hsl(216 12% 42%);
    --border: hsl(216 15% 85%);
    --primary: hsl(213 82% 48%);
    --primary-2: hsl(199 85% 42%);
    --ok: hsl(152 55% 38%);
    --warn: hsl(35 85% 44%);
    --err: hsl(3 72% 48%);
    --shadow: 0 8px 24px rgba(20,35,60,.10);
    --card-tint: rgba(255,255,255,0);
    --card-tint-2: rgba(255,255,255,0);
    --hover: rgba(20,40,80,.03);
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 32px;
    background:
      radial-gradient(1200px 600px at 15% -10%, var(--bg-glow) 0%, transparent 60%),
      var(--background);
    color: var(--foreground);
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    -webkit-font-smoothing: antialiased;
    transition: background-color .2s ease, color .2s ease;
  }
  .mono { font-family: 'Cascadia Code', 'Consolas', ui-monospace, monospace; font-size: 12.5px; }
  a { color: inherit; }
  header.page { margin-bottom: 26px; position: relative; }
  .theme-toggle {
    position: absolute; top: 0; right: 0;
    display: inline-flex; align-items: center; gap: 8px;
    background: var(--card-2); color: var(--muted-fg);
    border: 1px solid var(--border); border-radius: 999px;
    padding: 8px 14px; font: inherit; font-size: 13px; cursor: pointer;
    box-shadow: var(--shadow); transition: color .15s ease, border-color .15s ease;
  }
  .theme-toggle:hover { color: var(--foreground); border-color: var(--primary); }
  .theme-toggle .icon { width: 15px; height: 15px; }
  .theme-toggle .icon.moon { display: none; }
  html[data-theme="light"] .theme-toggle .icon.sun { display: none; }
  html[data-theme="light"] .theme-toggle .icon.moon { display: inline; }
  .theme-toggle .lbl-dark { display: none; }
  html[data-theme="light"] .theme-toggle .lbl-dark { display: inline; }
  html[data-theme="light"] .theme-toggle .lbl-light { display: none; }
  header.page .eyebrow {
    font-family: 'Cascadia Code','Consolas',ui-monospace,monospace;
    text-transform: uppercase; letter-spacing: .18em; font-size: 11px;
    color: var(--muted-fg); margin: 0 0 8px;
  }
  header.page h1 {
    margin: 0; font-size: 30px; font-weight: 700; letter-spacing: -.01em;
    background: linear-gradient(92deg, var(--primary), var(--primary-2));
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  header.page .sub { color: var(--muted-fg); margin: 6px 0 0; font-size: 13.5px; }

  .grid-top { display: grid; grid-template-columns: 360px 1fr; gap: 20px; margin-bottom: 22px; }
  @media (max-width: 860px) { .grid-top { grid-template-columns: 1fr; } }

  .card {
    background: linear-gradient(180deg, var(--card-tint), var(--card-tint-2)), var(--card);
    border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow);
  }
  .summary-card { padding: 22px; display: flex; align-items: center; gap: 22px; }
  .donut-wrap { position: relative; width: 150px; height: 150px; flex: 0 0 auto; }
  .donut-wrap .center {
    position: absolute; inset: 0; display: flex; flex-direction: column;
    align-items: center; justify-content: center; text-align: center;
  }
  .donut-wrap .pct { font-size: 30px; font-weight: 700; color: var(--foreground); line-height: 1; }
  .donut-wrap .pct-label { font-size: 10px; color: var(--muted-fg); text-transform: uppercase; letter-spacing: .12em; margin-top: 4px; }
  .legend { display: flex; flex-direction: column; gap: 10px; flex: 1 1 auto; min-width: 0; }
  .legend .row { display: flex; align-items: center; gap: 10px; font-size: 13.5px; white-space: nowrap; }
  .legend .dot { width: 11px; height: 11px; border-radius: 3px; background: var(--dot); flex: 0 0 auto; }
  .legend .n { margin-left: auto; font-weight: 600; font-variant-numeric: tabular-nums; padding-left: 12px; }

  .kpis { padding: 22px; display: grid; grid-template-columns: repeat(4, 1fr); gap: 14px; align-content: start; }
  @media (max-width: 620px) { .kpis { grid-template-columns: repeat(2,1fr); } }
  .kpi { background: var(--card-2); border: 1px solid var(--border); border-radius: 10px; padding: 14px 16px; }
  .kpi .val { font-size: 26px; font-weight: 700; font-variant-numeric: tabular-nums; }
  .kpi .lbl { font-size: 11.5px; color: var(--muted-fg); text-transform: uppercase; letter-spacing: .1em; margin-top: 2px; }
  .kpi.ok .val { color: var(--ok); } .kpi.warn .val { color: var(--warn); }
  .kpi.err .val { color: var(--err); } .kpi.total .val { color: var(--primary); }

  .section-title { font-size: 13px; text-transform: uppercase; letter-spacing: .14em; color: var(--muted-fg); margin: 26px 4px 12px; }

  table.nodes { width: 100%; border-collapse: collapse; overflow: hidden; border-radius: var(--radius); }
  table.nodes thead th {
    text-align: left; font-size: 11.5px; text-transform: uppercase; letter-spacing: .08em;
    color: var(--muted-fg); padding: 12px 16px; background: var(--card-2); border-bottom: 1px solid var(--border);
  }
  table.nodes tbody td { padding: 12px 16px; border-bottom: 1px solid var(--border); font-size: 13.5px; }
  table.nodes tbody tr:last-child td { border-bottom: none; }
  table.nodes tbody tr:hover { background: var(--hover); }
  .node-link { text-decoration: none; font-weight: 600; }
  .node-link:hover { color: var(--primary); }

  .pill {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 12px; font-weight: 600; padding: 3px 10px; border-radius: 999px;
    color: var(--pill); background: color-mix(in srgb, var(--pill) 16%, transparent);
    border: 1px solid color-mix(in srgb, var(--pill) 35%, transparent);
  }
  .pill::before { content: ''; width: 7px; height: 7px; border-radius: 50%; background: var(--pill); }
  .pill.sm { font-size: 11px; padding: 2px 8px; }

  details.node-card { margin-top: 12px; }
  details.node-card > summary {
    list-style: none; cursor: pointer; padding: 14px 18px; display: flex; align-items: center; gap: 14px;
    background: var(--card-2); border: 1px solid var(--border); border-radius: 12px;
  }
  details.node-card[open] > summary { border-bottom-left-radius: 0; border-bottom-right-radius: 0; }
  details.node-card > summary::-webkit-details-marker { display: none; }
  details.node-card .node-name { font-weight: 600; font-size: 14.5px; }
  details.node-card .agent { color: var(--muted-fg); margin-left: auto; }
  .node-body { border: 1px solid var(--border); border-top: none; border-radius: 0 0 12px 12px; padding: 18px; background: var(--card); }
  .kv { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px 24px; margin-bottom: 14px; }
  @media (max-width: 620px) { .kv { grid-template-columns: 1fr; } }
  .kv .k { color: var(--muted-fg); font-size: 12px; display: block; text-transform: uppercase; letter-spacing: .08em; }
  .kv .v { font-size: 13.5px; }
  .err-banner { background: color-mix(in srgb, var(--err) 12%, transparent); border: 1px solid color-mix(in srgb, var(--err) 35%, transparent); border-radius: 10px; padding: 10px 14px; margin-bottom: 14px; font-size: 13px; }
  .err-banner ul { margin: 6px 0 0; padding-left: 18px; }

  table.res-table { width: 100%; border-collapse: collapse; }
  table.res-table th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: var(--muted-fg); padding: 8px 12px; border-bottom: 1px solid var(--border); }
  table.res-table td { padding: 8px 12px; border-bottom: 1px solid var(--border); font-size: 12.5px; vertical-align: top; }
  table.res-table tr:last-child td { border-bottom: none; }
  .err-cell { color: var(--warn); max-width: 360px; }
  .muted { color: var(--muted-fg); }

  footer.page { margin-top: 30px; color: var(--muted-fg); font-size: 12px; display: flex; gap: 16px; flex-wrap: wrap; }
  @media print { body { background: #fff; color: #000; } .card, details .node-body, summary { box-shadow: none; } .theme-toggle { display: none; } }
</style>
</head>
<body>
  <header class="page">
    <button type="button" class="theme-toggle" id="themeToggle" aria-label="Toggle light / dark theme">
      <svg class="icon sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>
      <svg class="icon moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>
      <span class="lbl-light">Light</span><span class="lbl-dark">Dark</span>
    </button>
    <p class="eyebrow">SPSConfigKit · DSC Pull Server</p>
    <h1>$(ConvertTo-HtmlText $Heading)</h1>
    <p class="sub">Compliance snapshot generated $generated · $total node(s)</p>
  </header>

  <div class="grid-top">
    <div class="card summary-card">
      <div class="donut-wrap">
        <svg width="150" height="150" viewBox="0 0 200 200">
          <circle cx="100" cy="100" r="$radius" fill="none" stroke="var(--card-2)" stroke-width="22" />
          <g transform="rotate(-90 100 100)">
            <circle cx="100" cy="100" r="$radius" fill="none" stroke="var(--ok)"   stroke-width="22" stroke-dasharray="$([math]::Round($segCompliant,2)) $([math]::Round($circ,2))" stroke-dashoffset="0" stroke-linecap="butt" />
            <circle cx="100" cy="100" r="$radius" fill="none" stroke="var(--warn)" stroke-width="22" stroke-dasharray="$([math]::Round($segNon,2)) $([math]::Round($circ,2))" stroke-dashoffset="$([math]::Round($offNon,2))" stroke-linecap="butt" />
            <circle cx="100" cy="100" r="$radius" fill="none" stroke="var(--err)"  stroke-width="22" stroke-dasharray="$([math]::Round($segFailed,2)) $([math]::Round($circ,2))" stroke-dashoffset="$([math]::Round($offFailed,2))" stroke-linecap="butt" />
            <circle cx="100" cy="100" r="$radius" fill="none" stroke="var(--muted-fg)" stroke-width="22" stroke-dasharray="$([math]::Round($segOther,2)) $([math]::Round($circ,2))" stroke-dashoffset="$([math]::Round($offOther,2))" stroke-linecap="butt" />
          </g>
        </svg>
        <div class="center">
          <div class="pct">$compliantPct%</div>
          <div class="pct-label">Compliant</div>
        </div>
      </div>
      <div class="legend">
        <div class="row"><span class="dot" style="--dot: var(--ok);"></span>Compliant<span class="n">$($counts.Compliant)</span></div>
        <div class="row"><span class="dot" style="--dot: var(--warn);"></span>Non-Compliant<span class="n">$($counts.NonCompliant)</span></div>
        <div class="row"><span class="dot" style="--dot: var(--err);"></span>Failed<span class="n">$($counts.Failed)</span></div>
        <div class="row"><span class="dot" style="--dot: var(--muted-fg);"></span>Other<span class="n">$($counts.Other)</span></div>
      </div>
    </div>

    <div class="card kpis">
      <div class="kpi total"><div class="val">$total</div><div class="lbl">Nodes</div></div>
      <div class="kpi ok"><div class="val">$($counts.Compliant)</div><div class="lbl">Compliant</div></div>
      <div class="kpi warn"><div class="val">$($counts.NonCompliant)</div><div class="lbl">Drifted</div></div>
      <div class="kpi err"><div class="val">$($counts.Failed)</div><div class="lbl">Failed</div></div>
    </div>
  </div>

  <div class="section-title">Nodes</div>
  $emptyNote
  <div class="card">
    <table class="nodes">
      <thead>
        <tr><th>Node</th><th>Status</th><th>Configuration</th><th>Version</th><th>Drift</th><th>Last report</th></tr>
      </thead>
      <tbody>
$rowsHtml
      </tbody>
    </table>
  </div>

  <div class="section-title">Node details</div>
$detailsHtml

  <footer class="page">
    <span>Generated by SPSConfigKit · SPSDscDashboard.ps1</span>
    <span class="mono">Source: PSDSCPullServer.svc (OData)</span>
  </footer>
  <script>
    (function () {
      var root = document.documentElement;
      var KEY = 'spsconfigkit-dsc-theme';
      function apply(theme) {
        if (theme === 'light') { root.setAttribute('data-theme', 'light'); }
        else { root.removeAttribute('data-theme'); }
      }
      // Initial theme: saved choice, else follow the OS preference.
      var saved = null;
      try { saved = localStorage.getItem(KEY); } catch (e) { }
      if (saved) {
        apply(saved);
      } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
        apply('light');
      }
      var btn = document.getElementById('themeToggle');
      if (btn) {
        btn.addEventListener('click', function () {
          var isLight = root.getAttribute('data-theme') === 'light';
          var next = isLight ? 'dark' : 'light';
          apply(next);
          try { localStorage.setItem(KEY, next); } catch (e) { }
        });
      }
    })();
  </script>
</body>
</html>
"@
  return $html
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Invoke-DashboardGenerate {
  $raw = Get-DscNodeData
  $nodes = @($raw.Nodes)
  $reportsMap = $raw.Reports

  $compliance = foreach ($node in $nodes) {
    $agentId = $node.AgentId
    $nodeReports = @()
    if ($reportsMap) {
      # PSCustomObject (from JSON) exposes AgentId as a note property; hashtable uses the key.
      if ($reportsMap -is [System.Collections.IDictionary]) { $nodeReports = @($reportsMap[$agentId]) }
      else { $nodeReports = @($reportsMap.$agentId) }
    }
    ConvertTo-NodeCompliance -Node $node -Reports $nodeReports
  }

  $html = New-DashboardHtml -Nodes @($compliance) -Heading $Title
  # UTF-8 with BOM so browsers and Windows tooling agree on the encoding.
  $enc = New-Object System.Text.UTF8Encoding($true)
  [System.IO.File]::WriteAllText($OutputPath, $html, $enc)

  Write-Host ("[{0}] Dashboard written: {1} ({2} node(s))" -f (Get-Date -Format 'o'), $OutputPath, @($compliance).Count)
}

function Assert-Elevated {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    throw ("Action '{0}' manages a Scheduled Task and must run in an elevated session." -f $Action)
  }
}

function Invoke-DashboardInstall {
  Assert-Elevated

  $selfPath = $PSCommandPath
  if ([string]::IsNullOrWhiteSpace($selfPath)) { $selfPath = Join-Path -Path $scriptBase -ChildPath 'SPSDscDashboard.ps1' }

  Write-Host '-----------------------------------------------'
  Write-Host '| SPSConfigKit - SPSDscDashboard (Install)'
  Write-Host ("| Task name       {0}" -f $TaskName)
  Write-Host ("| Interval        {0} minute(s)" -f $IntervalMinutes)
  Write-Host ("| Output          {0}" -f $OutputPath)
  Write-Host ("| Run as          {0}" -f $(if ($InstallAccount) { $InstallAccount.UserName } else { 'SYSTEM' }))
  Write-Host '-----------------------------------------------'

  if ($IntervalMinutes -lt 60) {
    Write-Host ("[i] Refresh interval is {0} min. This is the practical floor — DSC nodes only report on their LCM consistency interval (typically 60-120 min), so a shorter refresh adds load without newer data." -f $IntervalMinutes)
  }

  # The task re-invokes THIS script with -Action Default; settings come from the
  # same SPSDscDashboard.psd1, so the task stays in sync with the config file.
  $scriptArgs = @(
    '-NoProfile'
    '-ExecutionPolicy'; 'Bypass'
    '-File'; ('"{0}"' -f $selfPath)
    '-Action'; 'Default'
    '-InputFile'; ('"{0}"' -f $InputFile)
  )
  $argumentString = $scriptArgs -join ' '

  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentString
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
  $settingsSet = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

  $registerArgs = @{
    TaskName    = $TaskName
    Action      = $action
    Trigger     = $trigger
    Settings    = $settingsSet
    Description = 'SPSConfigKit — regenerates the DSC compliance dashboard (SPSDscDashboard.ps1 -Action Default) on a schedule.'
    Force       = $true
  }
  if ($InstallAccount) {
    # Run under the supplied domain account (needed when the node manifest is on a
    # remote share the machine account cannot read).
    $registerArgs.User = $InstallAccount.UserName
    $registerArgs.Password = $InstallAccount.GetNetworkCredential().Password
    $registerArgs.RunLevel = 'Highest'
  }
  else {
    # Default: SYSTEM. Fine for a local manifest folder and a localhost pull server.
    $registerArgs.Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  }

  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  $verb = if ($existing) { 'Updating' } else { 'Registering' }
  if ($PSCmdlet.ShouldProcess($TaskName, "$verb scheduled task")) {
    Register-ScheduledTask @registerArgs | Out-Null
    Write-Host ("[+] Scheduled task '{0}' registered; next run within {1} minute(s)." -f $TaskName, $IntervalMinutes)
    if ($RunAfterInstall) {
      Start-ScheduledTask -TaskName $TaskName
      Write-Host ("[+] Task started; '{0}' will be written shortly." -f $OutputPath)
    }
  }
}

function Invoke-DashboardUninstall {
  Assert-Elevated
  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if (-not $existing) {
    Write-Host ("[=] Scheduled task '{0}' not found. Nothing to do." -f $TaskName)
    return
  }
  if ($PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task')) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host ("[+] Scheduled task '{0}' removed." -f $TaskName)
  }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
  switch ($Action) {
    'Install'   { Invoke-DashboardInstall }
    'Uninstall' { Invoke-DashboardUninstall }
    default     { Invoke-DashboardGenerate }
  }
}
catch {
  Write-Error -Message ("SPSDscDashboard '{0}' failed at {1}:{2} - {3}" -f $Action, $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}
