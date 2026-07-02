# DSC Compliance Dashboard

`SPSDscDashboard.ps1` generates a **self-contained HTML compliance dashboard**
for a classic Windows DSC pull server — in the spirit of Azure Automation State
Configuration — by querying the pull server's OData reporting API and classifying
every node as **Compliant / Non-Compliant / Failed / Unresponsive**.

It is driven by `-Action` and configured by `SPSDscDashboard.psd1` (same folder):

| `-Action` | Does |
| --- | --- |
| `Default` (default) | Generate `Dashboard.html` once. |
| `Install` | Register/update a Scheduled Task that refreshes it on a schedule. |
| `Uninstall` | Remove that Scheduled Task. |

All settings live in `SPSDscDashboard.psd1` (URLs and paths only, no secrets, so
it is tracked — edit it in place). Any value can still be overridden on the
command line; an explicit parameter always wins.

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

The script has just three parameters — `-Action`, `-InstallAccount`, `-InputFile`
— everything else is configured in `SPSDscDashboard.psd1`. Edit the psd1 for your
environment (pull URL, manifest path, output path, schedule), then:

```powershell
# Generate once, using SPSDscDashboard.psd1 for all settings
.\SPSDscDashboard.ps1

# Install the auto-refresh Scheduled Task (settings from the psd1)
.\SPSDscDashboard.ps1 -Action Install

# Install it running under a domain account (needed for a remote manifest share)
.\SPSDscDashboard.ps1 -Action Install -InstallAccount (Get-Credential 'CONTOSO\svcdash')

# Remove the Scheduled Task
.\SPSDscDashboard.ps1 -Action Uninstall
```

For offline testing, set `MockDataPath` in the psd1 (or point `-InputFile` at a
test copy) and run `.\SPSDscDashboard.ps1`.

> The manifest folder is populated by the nodes when they register:
> `.\CfgLcmPull.ps1 -DSCRegistrationKey … -DSCPullServerUrl … -NodeManifestPath '\\pull\DscNodeManifest' -UpdateNow`
> (or via the `NodeManifestPath` key in the `-DomainDefaultsPath` file).

### Parameters

| Parameter | Purpose |
| --- | --- |
| `-Action` | `Default` (generate), `Install` (register the refresh task), `Uninstall` (remove it). Default `Default`. |
| `-InstallAccount` | (Install) Credential the Scheduled Task runs under. Omit for SYSTEM; supply a domain account for a remote manifest share. |
| `-InputFile` | Path to the settings psd1. Defaults to `SPSDscDashboard.psd1` next to the script. |

### Settings (`SPSDscDashboard.psd1`)

| Key | Purpose |
| --- | --- |
| `PullServerUrl` | Base URL of the OData service. No trailing slash. |
| `NodeManifestPath` | Shared folder of `<NodeName>.json` entries published by `CfgLcmPull.ps1`. How the dashboard discovers nodes. |
| `OutputPath` | HTML file to write. Default the pull server IIS site root. |
| `Title` | Dashboard heading. |
| `MaxReportsPerNode` | Cap on reports fetched per node before picking the latest (guards the unbounded ESENT `StatusReport` table). |
| `SkipCertificateCheck` | Ignore TLS validation (self-signed lab certs). |
| `MockDataPath` | Offline mode: render from a JSON file mirroring the OData shape (see `samples/`). `$null` for live. |
| `Schedule.IntervalMinutes` | Install refresh cadence. **Minimum 30** (enforced). |
| `Schedule.TaskName` | Scheduled Task name. |
| `Schedule.RunAfterInstall` | Start the task once immediately after Install. Default `$true`. |

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
"refreshing" it means regenerating the HTML. `-Action Install` registers a
Scheduled Task on the pull server that regenerates it (via `-Action Default`,
same settings file) into the IIS-served folder — the team then just browses
`https://pull.contoso.com/Dashboard.html`:

```powershell
# Elevated, on the pull server. Uses SPSDscDashboard.psd1 (Schedule block).
.\SPSDscDashboard.ps1 -Action Install
```

**Align the interval with your farm's LCM, and never go below 30 minutes.** DSC
nodes only submit a new status report on their consistency interval
(`ConfigurationModeFrequencyMins`, typically 60–120 minutes), so refreshing more
often than every 30 minutes just adds load without surfacing any newer data. The
script enforces a 30-minute floor. Set `Schedule.IntervalMinutes` in the psd1:

| Farm LCM `ConfigurationModeFrequencyMins` | Suggested `Schedule.IntervalMinutes` |
| --- | --- |
| 60 | 30 |
| 120 | 60 |

The task runs as SYSTEM by default (fine for a local manifest folder and a
localhost pull server). If the node manifest is on a **remote** share, run it
under a domain account that can read it:
`-Action Install -InstallAccount (Get-Credential 'CONTOSO\svcdash')`.
`-Action Install` is idempotent — re-running updates the existing task; remove it
with `-Action Uninstall`.

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
the renderer can be exercised without a live pull server. Set `MockDataPath` in
`SPSDscDashboard.psd1` (or a test copy passed with `-InputFile`) to it, then:

```powershell
.\samples\New-MockData.ps1
.\SPSDscDashboard.ps1
```

## Notes & limits (ESENT backend)

- **No server-side filtering.** The classic OData endpoint's `$filter` / `$orderby`
  are unreliable, so the script fetches reports and sorts/filters client-side.
- **`Devices.edb` is never auto-purged.** On busy farms the `StatusReport` table
  grows unbounded; schedule cleanup (e.g. `DSCPullServerAdmin`) if needed.
- **Scale.** The ESENT backend is recommended for ≤ 500 nodes.
