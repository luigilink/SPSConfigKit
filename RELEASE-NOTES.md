# SPSConfigKit - Release Notes

## [1.1.1] - 2026-06-30

### Fixed

- `scripts/pull/CfgAppPull.ps1`
  - Certificate import no longer references the undefined `$PFXCred` variable.
    The shared `$PFXCred` was removed in 1.1.0 when PDC and SPS moved to
    per-certificate PFX passwords, but `CfgAppPull.ps1` was missed and kept
    pointing at it &mdash; so `PfxImport.Credential` compiled to `$null` and the
    pull-server certificate import would fail at apply time. It now resolves the
    per-cert PSCredential via `(Get-Variable -Name $getCertInfo.Name -ValueOnly)`,
    the same pattern used by `CfgAppPdc.ps1` / `CfgAppSps.ps1`.
- `scripts/sps/CfgAppSps.psd1`
  - Added the missing `Services.SearchService.Topology.FirstPartitionDirectory`
    key. `CfgAppSps.ps1` builds `SPSearchTopology.FirstPartitionDirectory` as
    `<Drives.Data>\<...FirstPartitionDirectory>`; with the key absent the search
    index location silently compiled to the bare data-drive root (e.g. `F:\`).
    Defaults to `OfficeServer\Index` (&rarr; `F:\OfficeServer\Index`).

### Changed

- `scripts/pull/CfgAppPull.ps1`
  - Brought in line with the standard configuration-script template already used
    by PDC / SQL / SPS: `#Requires -Version 5.1` + `#Requires -RunAsAdministrator`,
    full comment-based help, `[CmdletBinding()]`, the `-OutputPath` parameter and
    MOF-path override pattern, timestamped compile-progress logging, and an
    enriched `catch` block that surfaces the failing script, line and message.
    Cleared cosmetic drift (`write-host` &rarr; `Write-Host`, `Throw` &rarr;
    `throw`, `-verbose` &rarr; `-Verbose`, doubled `-Path` spacing).
- `scripts/pull/CfgAppPull.psd1`
  - Renamed the pull-server certificate entry `DscPull` &rarr; `DscPullCert` so it
    matches the `Secrets.psd1` entry and the PDC/SPS naming, keeping the per-cert
    PFX-password lookup consistent across the kit.
- `scripts/sql/CfgAppSql.ps1`
  - The SQL Server engine and Agent Windows service names are now derived from
    `SQLInstanceName` (`MSSQLSERVER` / `SQLSERVERAGENT` for the default instance,
    `MSSQL$<Instance>` / `SQLAgent$<Instance>` for a named instance) instead of
    being hard-coded to the default-instance names.
- `scripts/sps/CfgAppSps.ps1`
  - Removed a dead `if ($Node.IsADSServer)` branch in the Office Online Server
    node that referenced `[WaitForADDomain]WaitForDCReady`, a resource not
    declared in that node. OOS servers always domain-join through the existing
    `Computer JoinDomain` / `PendingReboot` path.
- `scripts/test/ConfigData.Tests.ps1`
  - The `NonNodeData common` block now gates the `SourcePath` assertions behind
    the presence of a media-copying product (SPS/OOS/SQL) and validates only the
    drive letters each config actually declares, so the suite runs clean against
    the PDC and PULL configurations (as the suite synopsis already advertised).

### Added

- `scripts/test/ConfigData.Tests.ps1`
  - New **Search service topology** checks: when a `SearchService` is declared,
    `Topology.FirstPartitionDirectory` must be present and must be a relative path
    (it is concatenated onto `<Drives.Data>\`). Catches the bare-drive-root
    regression fixed above before a MOF is compiled.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
