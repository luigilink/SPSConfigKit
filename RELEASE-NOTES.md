# SPSConfigKit - Release Notes

## [1.3.0] - 2026-07-02

### Added

- `scripts/dashboard/SPSDscDashboard.ps1` + `SPSDscDashboard.psd1` (#6, #8, #9, #10, #11)
  - New DSC compliance dashboard tool, driven by `-Action` and configured by a
    tracked `SPSDscDashboard.psd1` settings file (matching the SPSWakeUp `-Action`
    and SPSUserSync `.psd1` conventions). Actions: `Default` generates a
    self-contained, dependency-free `Dashboard.html` (inline CSS/JS, SVG donut — no
    CDN) classifying every node as Compliant / Non-Compliant / Failed /
    Unresponsive with drift counts, last-report time, a per-node detail view and a
    persisted OS-aware light/dark theme toggle; `Install` registers/updates a
    Scheduled Task that refreshes it on a schedule into the IIS-served folder;
    `Uninstall` removes it. `-MockDataPath` renders offline. The node list comes
    from a shared manifest folder (populated by `CfgLcmPull.ps1`) queried via the
    keyed OData endpoint `Nodes(AgentId='…')/Reports`, because the classic pull
    server's OData API cannot enumerate nodes — `GET /Nodes` returns HTTP 400
    *"resourceKeys is unexpected for MSFT.DSCNode"* (#8). The refresh schedule
    enforces a 30-minute floor: nodes only report on their LCM consistency interval
    (typically 60-120 min), so a shorter refresh adds load without newer data (#10).
    Runs the task as SYSTEM by default; supports a domain `RunAsUser` for remote
    manifests. (Consolidates the earlier `New-SPSDscDashboard.ps1` and
    `Register-SPSDscDashboardTask.ps1` into one `-Action`-driven script (#11).)
    The script exposes only `-Action`, `-InstallAccount` and `-InputFile`; every
    other setting lives in the tracked `SPSDscDashboard.psd1`. The refresh task is
    created in the `\SharePoint\` Task Scheduler folder (configurable via
    `Schedule.TaskPath`), alongside the other SPS* project tasks.
- `scripts/dashboard/README.md` and `scripts/dashboard/samples/`
  - Dashboard documentation plus a `mock-data.json` fixture and `New-MockData.ps1`
    so the page can be generated and reviewed without a live pull server.

### Changed

- `scripts/pull/CfgLcmPull.ps1` (#7, #8)
  - Enriched the LCM pull registration: added `-UpdateNow` (trigger the first pull
    immediately so the node applies its config and sends its first status report
    right away) and `-DomainDefaultsPath`, which resolves `-DSCRegistrationKey` /
    `-DSCPullServerUrl` per Active Directory domain from a git-ignored
    `CfgLcmPull.DomainDefaults.psd1` (template `*.sample.psd1` tracked). HTTPS/443
    and the `ReportServerWeb` block are kept so nodes report to the dashboard.
  - Added `-NodeManifestPath`: after registering, each node publishes a
    `<NodeName>.json` (NodeName + AgentId + ConfigurationNames) to a shared folder
    so the compliance dashboard can enumerate nodes (also resolvable per-domain via
    the `NodeManifestPath` key in the defaults file).

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
