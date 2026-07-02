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

## Why a node manifest + the keyed OData API (not `GET /Nodes`, not `Devices.edb`)

The classic `xDscWebService` pull server has two hard constraints:

- **OData cannot enumerate nodes.** `GET /PSDSCPullServer.svc/Nodes` (and every
  collection form: `/Nodes()`, `?$top=…`, `?$filter=…`) returns **HTTP 400**
  *"resourceKeys is unexpected for MSFT.DSCNode"*. The provider only answers
  **keyed** queries — `Nodes(AgentId='…')` and `Nodes(AgentId='…')/Reports`.
- **`Devices.edb` is exclusively locked by IIS** while the pull server runs, so it
  can't be read from another process without stopping the app pool (downtime).

So the dashboard needs the node **AgentIds** from a third source. Registration is
the one moment each node knows its own AgentId, so `CfgLcmPull.ps1` publishes a
per-node `<NodeName>.json` (NodeName + AgentId + ConfigurationNames) into a shared
manifest folder (`-NodeManifestPath`). The dashboard reads that folder to discover
the nodes, then queries the supported keyed endpoint
`Nodes(AgentId='…')/Reports` for each — no lock, no downtime.

## Usage

```powershell
# Against the live pull server (run on the pull server, localhost)
.\New-SPSDscDashboard.ps1 `
    -PullServerUrl     'https://localhost/PSDSCPullServer.svc' `
    -NodeManifestPath  '\\pull\DscNodeManifest' `
    -SkipCertificateCheck `
    -OutputPath        'C:\inetpub\PSDSCPullServer\Dashboard.html'

# Offline render from mock data (no pull server needed — for testing / demos)
.\New-SPSDscDashboard.ps1 -MockDataPath .\samples\mock-data.json -OutputPath .\Dashboard.html
```

> The manifest folder is populated by the nodes when they register:
> `.\CfgLcmPull.ps1 -DSCRegistrationKey … -DSCPullServerUrl … -NodeManifestPath '\\pull\DscNodeManifest' -UpdateNow`
> (or via the `NodeManifestPath` key in the `-DomainDefaultsPath` file).

### Parameters

| Parameter | Purpose |
| --- | --- |
| `-PullServerUrl` | Base URL of the OData service. Default `https://localhost/PSDSCPullServer.svc`. |
| `-NodeManifestPath` | Shared folder of `<NodeName>.json` entries published by `CfgLcmPull.ps1`. Required for live rendering (how the dashboard discovers nodes). |
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

The dashboard is a point-in-time snapshot with no server-side runtime, so
"refreshing" it means regenerating the HTML. Use the bundled helper to install a
Scheduled Task on the pull server that regenerates it into the IIS-served folder
— the team then just browses `https://pull.contoso.com/Dashboard.html`:

```powershell
# Elevated, on the pull server. Refresh every 30 minutes as SYSTEM, run once now.
.\Register-SPSDscDashboardTask.ps1 `
    -NodeManifestPath 'F:\DscNodeManifest' `
    -SkipCertificateCheck `
    -RunNow
```

**Align the interval with your farm's LCM, and never go below 30 minutes.** DSC
nodes only submit a new status report on their consistency interval
(`ConfigurationModeFrequencyMins`, typically 60–120 minutes), so refreshing more
often than every 30 minutes just adds load without surfacing any newer data. The
helper enforces a 30-minute floor. Examples:

| Farm LCM `ConfigurationModeFrequencyMins` | Suggested `-IntervalMinutes` |
| --- | --- |
| 60 | 30 |
| 120 | 60 |

```powershell
# Farm with a 120-minute LCM consistency interval
.\Register-SPSDscDashboardTask.ps1 -NodeManifestPath 'F:\DscNodeManifest' -IntervalMinutes 60 -SkipCertificateCheck
```

The task runs as SYSTEM by default (fine for a local manifest folder and a
localhost pull server). If the node manifest is on a **remote** share, run the
task under a domain account that can read it: `-RunAsUser 'CONTOSO\svcdash'
-RunAsPassword (Read-Host 'pwd' -AsSecureString)`. The helper is idempotent —
re-running updates the existing task.

### `Register-SPSDscDashboardTask.ps1` parameters

| Parameter | Purpose |
| --- | --- |
| `-IntervalMinutes` | Refresh cadence. **Minimum 30** (enforced). Align with the LCM interval. Default 30. |
| `-NodeManifestPath` | Manifest folder passed to the dashboard (required). |
| `-PullServerUrl` | Pull server OData URL. Default `https://localhost/PSDSCPullServer.svc`. |
| `-OutputPath` | Where the task writes the HTML. Default `C:\inetpub\PSDSCPullServer\Dashboard.html`. |
| `-DashboardScriptPath` | Path to `New-SPSDscDashboard.ps1`. Defaults next to this helper. |
| `-TaskName` | Scheduled Task name. Default `SPSConfigKit-DscDashboard`. |
| `-RunAsUser` / `-RunAsPassword` | Account for the task. Default `SYSTEM` (no password). Domain account needs a password. |
| `-SkipCertificateCheck` | Forwarded to the dashboard for self-signed certs. |
| `-RunNow` | Also start the task once immediately after registering. |

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
