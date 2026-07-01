# DSC Compliance Dashboard

`New-SPSDscDashboard.ps1` generates a **self-contained HTML compliance dashboard**
for a classic Windows DSC pull server — in the spirit of Azure Automation State
Configuration — by querying the pull server's OData reporting API and classifying
every node as **Compliant / Non-Compliant / Failed / Unresponsive**.

The output is a single `Dashboard.html` with **inline CSS + an SVG donut, no
external framework and no CDN**, so it renders on an **offline** pull server (the
common case for on-premises SharePoint farms).

## Prerequisites — nodes MUST report to the pull server

> [!IMPORTANT]
> The dashboard only shows data the pull server actually has. It is empty until
> every SharePoint / OOS node's **LCM is registered in Pull mode with reporting
> enabled**. Configure each node with the bundled
> [`../pull/CfgLcmPull.ps1`](../pull/CfgLcmPull.ps1), which sets up
> `ConfigurationRepositoryWeb` **and** `ReportServerWeb` so the LCM pushes its
> status reports back to the pull server:
>
> ```powershell
> .\scripts\pull\CfgLcmPull.ps1 `
>     -DSCRegistrationKey '<registration-guid>' `
>     -DSCPullServerUrl   'https://pull.contoso.com/PSDSCPullServer.svc'
> ```
>
> Run it on **every** managed node (APP/WFE/SCH/OOS). Reports appear after the
> next LCM consistency pass (default every 15–30 min, or force one with
> `Update-DscConfiguration` / `Invoke-CimMethod ... PerformRequiredConfigurationChecks`).

Other prerequisites:

- The pull server is stood up (see [`../pull/CfgAppPull.ps1`](../pull/CfgAppPull.ps1)),
  endpoint `PSDSCPullServer` on HTTPS/443, JET/ESENT backend (`Devices.edb`).
- The dashboard runs **on the pull server itself** (localhost) so it can reach the
  OData endpoint without extra firewall rules.
- PowerShell 5.1.

## Why the OData API (not `Devices.edb` directly)

The ESENT database `Devices.edb` is **exclusively locked by IIS** while the pull
server is running — you cannot open it from another process without stopping the
app pool (downtime). The OData reporting endpoint
(`PSDSCPullServer.svc/Nodes(AgentId='…')/Reports`) exposes the same data over HTTP
with **no lock and no downtime**, so the dashboard uses it. See the research notes
for the full API shape, the `StatusData` double-encoding, and the compliance rules.

## Usage

```powershell
# Against the live pull server (run on the pull server, localhost)
.\New-SPSDscDashboard.ps1 `
    -PullServerUrl 'https://localhost/PSDSCPullServer.svc' `
    -OutputPath    'C:\inetpub\PSDSCPullServer\Dashboard.html'

# Self-signed lab certificate on the pull server
.\New-SPSDscDashboard.ps1 -PullServerUrl 'https://localhost/PSDSCPullServer.svc' -SkipCertificateCheck

# Offline render from mock data (no pull server needed — for testing / demos)
.\New-SPSDscDashboard.ps1 -MockDataPath .\samples\mock-data.json -OutputPath .\Dashboard.html
```

### Parameters

| Parameter | Purpose |
| --- | --- |
| `-PullServerUrl` | Base URL of the OData service. Default `https://localhost/PSDSCPullServer.svc`. |
| `-OutputPath` | HTML file to write. Default `Dashboard.html` next to the script. |
| `-Title` | Dashboard heading. |
| `-MaxReportsPerNode` | Cap on reports fetched per node before picking the latest (guards the unbounded ESENT `StatusReport` table). Default 50. |
| `-MockDataPath` | Offline mode: render from a JSON file mirroring the OData shape (see `samples/`). |
| `-SkipCertificateCheck` | Ignore TLS validation (self-signed lab certs). |

## Serving the dashboard
Put the generated `Dashboard.html` where it can be viewed:

- **On the pull server's IIS site** (already present): write it into the pull
  server's physical path (e.g. `C:\inetpub\PSDSCPullServer\Dashboard.html`) and
  browse `https://pull.contoso.com/Dashboard.html`, **or**
- **On a file share** the team can open directly.

## Light / dark theme

The dashboard ships with a **light / dark theme toggle** (top-right button). It
follows the viewer's OS preference (`prefers-color-scheme`) on first load and
**remembers the chosen theme** in the browser's `localStorage` for subsequent
visits. Like everything else it is self-contained — a few lines of inline CSS/JS,
no framework, no CDN — so it works on an offline pull server. The toggle is hidden
when printing.

## Scheduling a periodic refresh

The dashboard is a point-in-time snapshot; regenerate it on a schedule. Example
Scheduled Task that refreshes every 15 minutes on the pull server:

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\SPSConfigKit\scripts\dashboard\New-SPSDscDashboard.ps1" -PullServerUrl "https://localhost/PSDSCPullServer.svc" -OutputPath "C:\inetpub\PSDSCPullServer\Dashboard.html" -SkipCertificateCheck'
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'SPSConfigKit-DscDashboard' -Action $action -Trigger $trigger -Principal $principal
```

## Compliance rules

For each node, the **latest** compliance report (by `StartTime`, excluding
`OperationType = LocalConfigurationManager` meta runs) drives the state:

| Condition | State |
| --- | --- |
| `Status = "Failure"` or `Errors` non-empty | **Failed** |
| `ResourcesNotInDesiredState` ≥ 1 (and `Status = Success`) | **Non-Compliant** |
| `ResourcesNotInDesiredState` = 0 (and `Status = Success`) | **Compliant** |
| No compliance report on the pull server | **Unresponsive** |

## Testing offline

`samples/New-MockData.ps1` regenerates `samples/mock-data.json` (5 nodes covering
every state, with the same doubly-encoded `StatusData` the real API returns), so
the renderer can be exercised without a live pull server:

```powershell
.\samples\New-MockData.ps1
.\New-SPSDscDashboard.ps1 -MockDataPath .\samples\mock-data.json -OutputPath .\Dashboard.html
```

## Notes & limits (ESENT backend)

- **No server-side filtering.** The classic OData endpoint's `$filter` / `$orderby`
  are unreliable, so the script fetches reports and sorts/filters client-side.
- **`Devices.edb` is never auto-purged.** On busy farms the `StatusReport` table
  grows unbounded; schedule cleanup (e.g. `DSCPullServerAdmin`) if needed.
- **Scale.** The ESENT backend is recommended for ≤ 500 nodes.
