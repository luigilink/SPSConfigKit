# SPSConfigKit - Release Notes

## [1.3.0] - 2026-07-02

### Added

- `scripts/dashboard/New-SPSDscDashboard.ps1` (#6, #8)
  - New DSC compliance dashboard generator. Discovers nodes from a shared manifest
    folder (`-NodeManifestPath`, populated by `CfgLcmPull.ps1`) and queries the
    pull server's keyed OData endpoint (`Nodes(AgentId='…')/Reports`) for each,
    rendering a self-contained, dependency-free HTML page (inline CSS/JS, SVG donut
    — no CDN) that classifies every node as Compliant / Non-Compliant / Failed /
    Unresponsive, with drift counts, last-report time and a per-node detail view.
    Persisted, OS-aware light/dark theme toggle. `-SkipCertificateCheck` for
    self-signed pull servers, `-MockDataPath` for offline rendering. The node list
    comes from the manifest because the classic pull server's OData API cannot
    enumerate nodes — `GET /Nodes` returns HTTP 400 *"resourceKeys is unexpected
    for MSFT.DSCNode"* (#8).
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
