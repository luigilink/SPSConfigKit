# SPSConfigKit - Release Notes

## [1.3.0] - 2026-07-02

### Added

- `scripts/dashboard/New-SPSDscDashboard.ps1`
  - New DSC compliance dashboard generator. Reads the pull server's OData feed
    (`PSDSCPullServer.svc/Nodes` + each node's `Reports`) and renders a
    self-contained, dependency-free HTML page (inline CSS/JS, SVG donut — no CDN)
    that classifies every node as Compliant / Non-Compliant / Failed /
    Unresponsive, shows drift counts, last-report time and a per-node detail view.
    Includes a persisted, OS-aware light/dark theme toggle. Supports
    `-SkipCertificateCheck` for self-signed pull servers and `-MockDataPath` for
    offline rendering.
- `scripts/dashboard/README.md` and `scripts/dashboard/samples/`
  - Dashboard documentation plus a `mock-data.json` fixture and `New-MockData.ps1`
    so the page can be generated and reviewed without a live pull server.

### Changed

- `scripts/pull/CfgLcmPull.ps1`
  - Enriched the LCM pull registration: added `-UpdateNow` (trigger the first pull
    immediately so the node applies its config and sends its first status report
    right away) and `-DomainDefaultsPath`, which resolves `-DSCRegistrationKey` /
    `-DSCPullServerUrl` per Active Directory domain from a git-ignored
    `CfgLcmPull.DomainDefaults.psd1` (template `*.sample.psd1` tracked). HTTPS/443
    and the `ReportServerWeb` block are kept so nodes report to the dashboard.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
