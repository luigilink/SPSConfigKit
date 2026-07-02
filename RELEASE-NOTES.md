# SPSConfigKit - Release Notes

## [1.3.1] - 2026-07-02

### Changed

- Sample share host moved off the domain controller (#13)
  - Every sample and wiki reference to the `SoftwarePackages` share now points at
    `\\PULL\Softwarepackages` (a member server) instead of `\\PDC1\Softwarepackages`
    (the domain controller). The v1.2.2 docs already required hosting the share on
    a member server — a node holds a machine session to the DC, and Windows refuses
    a second identity to the same server, so a share on the DC fails at apply with
    "Access is denied" — but the samples still pointed at the DC.
- Certificate paths are now DRY (#13)
  - `CfgAppSql`/`CfgAppSps`/`CfgAppPdc`/`CfgAppPull` psd1 cert entries carry only
    the `.cer` / `.pfx` **file name** (`CerFileName` / `PfxFileName`); the full path
    is derived by the Cfg*.ps1 scripts from the single `NonNodeData.SourcePath`.
    The share host is therefore declared exactly once per configuration — changing
    servers is a one-line edit and the `SourcePath`/`CertPath` divergence that
    caused earlier PDC1↔PULL mismatches can no longer happen. An explicit
    `CertPath` / `PfxPath` on an entry is still honoured (backward compatible).
    `NonNodeData.SourcePath` was added to the PDC and PULL configurations, and the
    `ConfigData.Tests.ps1` cert checks accept either the file-name or explicit-path
    form.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
