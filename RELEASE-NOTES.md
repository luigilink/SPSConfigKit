# SPSConfigKit - Release Notes

## [1.1.0] - 2026-06-15

### Added

- `scripts/sps/CfgAppSps.psd1` / `scripts/sps/CfgAppSps.ps1`
  - New optional `NonNodeData.SharePoint.LanguagePacks` array (e.g.
    `@('fr-fr','es-es')`) drives a data-driven loop that emits one
    `SPInstallLanguagePack` resource per locale, each chained through
    `DependsOn` so installs stay sequential. Omit the key or set it to `@()`
    to skip Language Pack installation entirely; the SharePoint CU resource
    then depends directly on `SPInstall` (no dangling references).
    Reference:
    <https://learn.microsoft.com/en-us/sharepoint/install/install-or-uninstall-language-packs-subscription>
  - New optional per-product path overrides under `NonNodeData.SharePoint`
    and `NonNodeData.OOS`: `SourcePath`, `DestinationPath`, and a
    `Subfolders = @{ Binaries; LanguagePack; CumulativeUpdate }` hashtable.
    All keys are optional; defaults preserve the previous layout
    (`<SourcePath>\<SPS|OOS>` &rarr;
    `<Drives.Data>\SoftwarePackages\<SPS|OOS>\{BIN,LP,CU}`). Lets
    customers point at non-standard file hierarchies without forking the
    configuration script.
  - New `Resolve-ProductPaths` helper (placed alongside `Get-CertThumbprint`)
    centralises source/destination/sub-folder resolution for SharePoint and
    Office Online Server.
- `scripts/sql/CfgAppSql.psd1` / `scripts/sql/CfgAppSql.ps1`
  - New optional `NonNodeData.SQL.SourcePath` and `NonNodeData.SQL.DestinationPath`
    overrides. SQL doesn't use sub-folders (`setup.exe` is expected at the
    root of `DestinationPath`), so the overrides are resolved with inline
    fallbacks instead of `Resolve-ProductPaths`.
- `scripts/sps/CfgAppSps.psd1` / `scripts/sps/CfgAppSps.ps1`
  - New optional `NonNodeData.SharePoint.ManagedAccounts` array (defaults
    to `@('FARM', 'IISAPP', 'SEARCH')` when omitted) drives the
    `SPManagedAccount` allowlist. Adding a new SharePoint service
    account no longer requires editing the configuration script &mdash;
    just extend the array in the .psd1.
- `scripts/test/ConfigData.Tests.ps1` / `scripts/test/Invoke-ConfigDataTest.ps1`
  - New Pester v5 pre-flight test suite that validates a ConfigurationData
    .psd1 (SPS, OOS, SQL) and cross-references the companion `Secrets.psd1`
    **before** any MOF is compiled. Catches typos in product keys, missing
    or duplicate node names, certificate-name mismatches between
    `WebApplications[*].CertName` / `OOS.CertFriendlyName` and
    `ADC.certificates`, `SharePoint.ManagedAccounts` entries that don't
    exist in `Secrets.psd1`, malformed language-pack locales, out-of-range
    ports, and (when `-SkipFilesystem` is not specified) the reachability
    of source shares, `.cer` / `.pfx` files, `setup.exe`, language-pack
    sub-folders, and CU packages. Uses the same `Resolve-ProductPaths`
    defaults the configuration script uses at compile time so source
    layouts overridden via the new `SourcePath` / `Subfolders` keys are
    validated against their real resolved location.
  - `Invoke-ConfigDataTest.ps1` wraps `Invoke-Pester` with a Pester
    container, requires Pester &ge; 5.0.0, and exits with code 1 on any
    failure so it can be wired into CI or a pre-MOF gate.
- `wiki/Configuration.md`
  - Documents the new `SharePoint.LanguagePacks` key, the per-product path
    overrides for SharePoint and OOS (with a table of defaults), the
    rooted-vs-relative resolution for `SharePoint.UberCumulativeUpdate` and
    `OOS.CUFileName`, the SQL `SourcePath` / `DestinationPath` overrides,
    and the `SharePoint.ManagedAccounts` allowlist override.
  - New **Validating your ConfigurationData** section that documents how
    to run `scripts/test/Invoke-ConfigDataTest.ps1`, the full list of
    checks (file integrity, AllNodes uniqueness, drives, product key,
    ports, certificates, managed accounts, language packs, filesystem
    reachability), the `-SkipFilesystem` workstation shortcut, and the
    Pester &ge; 5.0.0 prerequisite with the matching `Install-Module`
    one-liner.
- `wiki/Getting-Started.md`
  - Lists Pester &ge; 5.0.0 as an authoring-host prerequisite (with the
    `Install-Module` command) and adds a new workflow step — _Validate
    your ConfigurationData_ — between _Customise CfgAppSps.psd1_ and
    _Compile and apply_, recommending `Invoke-ConfigDataTest.ps1` as a
    pre-MOF gate.
- `wiki/Configuration.md`
  - New **Reading the output** sub-section under _Validating your
    ConfigurationData_ documenting the Pester v5 status glyphs
    (`[+]` Passed, `[-]` Failed, `[!]` **Skipped &mdash; not a failure**)
    and showing the wrapper's new `N of M test(s) passed; K skipped`
    summary so a healthy run with gated-off sections no longer looks
    misleadingly green.

### Changed

- `scripts/sps/CfgAppSps.ps1`
  - SPS Node block: the install-time references to
    `prerequisiteinstaller.exe`, the `SPInstall` binary directory, the
    Language Pack binary directories, and the `SPProductUpdate` setup file
    are now built from the resolved `$spPaths` instead of hard-coded
    `\BIN`, `\LP\<locale>`, and `\CU` literals.
  - OOS Node block: `OfficeOnlineServerInstall.Path`,
    `OfficeOnlineServerInstallLanguagePack.BinaryDir`, and
    `OfficeOnlineServerProductUpdate.SetupFile` are now built from the
    resolved `$oosPaths` (with the OOS locale still pinned to `Fr-fr`).
  - `SharePoint.UberCumulativeUpdate` and `OOS.CUFileName` may now be
    either a fully-qualified path (used as-is, backward compatible) or a
    relative path resolved under
    `<DestinationPath>\<Subfolders.CumulativeUpdate>`. Detection uses
    `[System.IO.Path]::IsPathRooted` so existing absolute values keep
    working without change.
- `scripts/test/Invoke-ConfigDataTest.ps1`
  - Final summary now surfaces Pester's `SkippedCount` so a run with
    gated-off sections no longer prints a misleading `All N test(s)
    passed`. Healthy runs print `N of M test(s) passed; K skipped
    (sections not present in this config or filesystem checks disabled)`;
    failure runs additionally report passed / skipped / total counts.
    Exit code semantics are unchanged (`0` on success, `1` on any
    failure).
- `scripts/test/ConfigData.Tests.ps1`
  - `SharePoint.LanguagePacks` diagnostics: each entry is classified
    ahead of the locale-code regex so non-string entries fail with a
    readable test title (`<hashtable Name='fr-fr' -- expected a string>`,
    `<null -- expected a string; check for a stray comma in
    LanguagePacks>`, `<TypeName -- expected a string>`) plus a `-Because`
    hint pointing at the `foreach ($spLanguagePack in $spLanguagePacks)`
    contract in `CfgAppSps.ps1`. The filesystem `LP\<locale>\setup.exe`
    reachability test gets the same treatment.

### Fixed

- `scripts/sps/CfgAppSps.ps1`
  - `SPManagedAccount` filter no longer leaks unrelated Secrets entries
    into the SharePoint farm. The previous blacklist (excluded only
    `SQLSERVER`, `CONTENT`, `SUPERUSER`, `SUPEREADER`, `SETUP`) still
    registered `PULLSETUP` and `IISPULLAPP` &mdash; the DSC pull server's
    setup and IIS-app-pool accounts &mdash; as SharePoint Managed Accounts
    at the customer site. Replaced with an explicit allowlist
    (`FARM`, `IISAPP`, `SEARCH`) so any future addition to `Secrets.psd1`
    (PULL / SQL / OOS / monitoring / ...) stays out of the SPS MOF.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
