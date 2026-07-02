# SPSConfigKit - Release Notes

## [1.2.1] - 2026-07-02

### Fixed

- `scripts/pull/CfgAppPull.ps1`
  - Removed the `Script MIDDLEWARE_PullServer_DscServiceAcl` resource that granted
    the pull-server AppPool identity write access to the DSC service folder via
    `Get-Acl` / `Set-Acl`. That folder is owned by `NT SERVICE\TrustedInstaller`
    and grants SYSTEM / Administrators only *Modify* (no Change-Permissions /
    WRITE_DAC), so `Set-Acl` failed at apply time with
    *"Attempted to perform an unauthorized operation"* — breaking the whole PULL
    `Start-DscConfiguration` run. The grant is now a dedicated post-configuration
    script (see Added) that takes ownership first, which the DSC consistency loop
    should not do.

### Added

- `scripts/pull/Set-SPSPullServerPermission.ps1`
  - New one-shot, elevated post-configuration script that grants the pull-server
    AppPool identity Modify on the DSC service folder (`takeown /a` then
    `icacls /grant …:(OI)(CI)M`), so the ESENT repository (`Devices.edb`) can be
    created. The AppPool identity is resolved from `Secrets.psd1` (`IISPULLAPP`)
    by default so it always matches the account `CfgAppPull.ps1` assigns, with
    `-AppPoolIdentity` as an explicit override. Idempotent, `-WhatIf`-aware, and
    parameterised by `-SecretsFile` / `-AppPoolSecretName` / `-DscServicePath` /
    `-TakeOwnership`, with a final verification.
- `scripts/pull/Publish-SPSPullModules.ps1`
  - New script that packages the pinned DSC resource modules as
    `<Name>_<Version>.zip` + checksum into the pull server's `Modules` folder, so
    Pull-mode nodes can download the resources their MOF imports (without them the
    LCM fails at apply time with *"could not find the module"*). Reads the module
    list from `Initialize-DscNode.psd1` by default, or derives it from a
    configuration's `Import-DscResource` lines via the AST with
    `-ConfigurationScriptPath` (replacing the fragile string-matching of the older
    ad-hoc `PrepareModules.ps1`). Idempotent, `-WhatIf`-aware, and parameterised by
    `-ManifestPath` / `-ModulePath` / `-SourceModulesPath`.
- `scripts/pull/README.md`
  - Documents the end-to-end pull workflow (stand up server → grant permission →
    publish modules → publish MOFs → register LCMs with `-UpdateNow` → watch the
    dashboard) and why the ACL grant is a separate privileged step rather than a
    DSC resource.
- `.gitignore`
  - Added a properly tracked `.gitignore` (ignoring `.vscode/`, `**/.DS_Store`,
    and the real `CfgLcmPull.DomainDefaults.psd1`), dropping the historical
    self-ignore line that kept `.gitignore` untracked across branches.

### Changed

- `wiki/Usage.md`
  - The pull-server option now documents the mandatory
    `Set-SPSPullServerPermission.ps1` step and points at `scripts/pull/README.md`.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
