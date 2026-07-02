# Change log for SPSConfigKit

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
    created. Idempotent, `-WhatIf`-aware, parameterised by `-AppPoolIdentity` /
    `-DscServicePath` / `-TakeOwnership`, with a final verification.
- `scripts/pull/README.md`
  - Documents the end-to-end pull workflow (stand up server → grant permission →
    publish MOFs → register LCMs with `-UpdateNow` → watch the dashboard) and why
    the ACL grant is a separate privileged step rather than a DSC resource.
- `.gitignore`
  - Added a properly tracked `.gitignore` (ignoring `.vscode/`, `**/.DS_Store`,
    and the real `CfgLcmPull.DomainDefaults.psd1`), dropping the historical
    self-ignore line that kept `.gitignore` untracked across branches.

### Changed

- `wiki/Usage.md`
  - The pull-server option now documents the mandatory
    `Set-SPSPullServerPermission.ps1` step and points at `scripts/pull/README.md`.

## [1.2.0] - 2026-07-01

### Added

- `scripts/test/MofEncryption.Tests.ps1` / `scripts/test/Invoke-MofEncryptionTest.ps1`
  - New post-compile Pester v5 guard-rail that scans compiled MOF files and fails
    (exit code 1) if any credential `Password` value is not a CMS-encrypted blob,
    or if a credential-bearing MOF is missing the `ContentType="PasswordEncrypted"`
    marker. Catches the most dangerous DSC mistake — shipping a MOF whose
    credentials were compiled in clear text — and is wired for CI / release gates.
- `wiki/Securing-Credentials.md`
  - New dedicated page documenting why MOF credential encryption is mandatory, the
    end-to-end flow (`Initialize-DscEncryption` → import `.pfx` per node → compile →
    verify), the clear-text-vs-CMS before/after, certificate rotation with `-Force`,
    and a troubleshooting table.
- `.editorconfig`
  - Locks repository encoding and formatting: `*.ps1` / `*.psd1` / `*.psm1` are
    `utf-8-bom` (Windows PowerShell 5.1 reads a BOM-less file as ANSI, corrupting
    non-ASCII characters at runtime); `*.md` / `*.yml` / `*.yaml` / `*.json` stay
    BOM-less (YAML linters and `dsc.exe` reject a BOM).

### Changed

- `scripts/test/ConfigData.Tests.ps1`
  - The wildcard AllNodes baseline check no longer requires
    `PSDscAllowPlainTextPassword = $true` — which wrongly failed a *secured*
    configuration (the state left by `Initialize-DscEncryption.ps1`). It now
    validates the encrypted branch instead: when
    `PSDscAllowPlainTextPassword = $false`, the wildcard must carry a
    `CertificateFile` and a 40-hex-char `Thumbprint`; when the config isn't yet
    encrypted it is skipped with a reminder (the post-compile MofEncryption
    guard-rail is the hard gate).
- **Encoding** — every `*.ps1` / `*.psd1` under `scripts/` is now UTF-8 **with BOM**
  (13 previously BOM-less files converted; the 4 already-BOM files unchanged), so
  Windows PowerShell 5.1 always reads them as UTF-8. No functional content change.
- `README.md`
  - New **Security** section stating that credentials are encrypted and that
    compiling them in clear text is not a supported configuration, with the
    four-step mandatory flow and a link to the new wiki page.
- `wiki/Getting-Started.md`
  - Certificate generation (step 3) is now flagged **mandatory** with a security
    call-out; a new post-compile step runs `Invoke-MofEncryptionTest.ps1` as a gate.
- `wiki/Usage.md`
  - New "Verify the MOFs are encrypted" gate documented right after compilation.


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

## [1.0.0]

### Added

- README.md
  - Add code_of_conduct.md badge
- Add CODE_OF_CONDUCT.md file
- Add Issue Templates files:
  - 1_bug_report.yml
  - 2_feature_request.yml
  - 3_documentation_request.yml
  - 4_improvement_request.yml
  - config.yml
- Add RELEASE-NOTES.md file
- Add CHANGELOG.md file
- Add CONTRIBUTING.md file
- Add release.yml file
- Add scripts folder with first version of SPSConfigKit
- Wiki Documentation in repository - Add :
  - wiki/Configuration.md
  - wiki/Getting-Started.md
  - wiki/Home.md
  - wiki/Usage.md
  - .github/workflows/wiki.yml
- `scripts/init/Initialize-DscNode.ps1` and `Initialize-DscNode.psd1`
  - Single-source-of-truth manifest for node prerequisites (drives, Chocolatey
    packages, pinned DSC module versions, document-encryption certificate).
  - Bootstraps a Windows node so the SharePoint DSC configuration compiles and
    applies cleanly (NuGet provider, pinned `Install-Module`, .pfx import into
    `Cert:\LocalMachine\My`, offline-aware skips).
- `scripts/init/Initialize-DscEncryption.ps1`
  - Generates the DSC document-encryption .cer/.pfx pair on the authoring host
    and drops it on the share consumed by `Initialize-DscNode.ps1`.
- `scripts/init/Initialize-SoftwarePackages.ps1` and `Initialize-SoftwarePackages.psd1`
  - Bootstraps the SMB share consumed by every node in the lab (typically
    `\\PDC1\SoftwarePackages`, backed by a configurable `Repository` root such
    as `F:\SoftwarePackages`). Designed to run **once**, on the file-share host.
  - Downloads every entry in the manifest (SQL Server 2022 Developer + CU,
    SharePoint Server SE + Language Pack + CU, the SharePoint
    prerequisites .NET Framework 4.8 and Visual C++ 2015–2019
    Redistributable, Office Online Server CU) to a per-package `Path`
    relative to the `Repository` root.
  - Uses Windows' native `Mount-DiskImage` / `Copy-Item -Recurse` /
    `Dismount-DiskImage` pipeline to expand ISOs — no 7-Zip or other
    external tool required, no overlap with `Initialize-DscNode.ps1`.
  - Outbound-internet detection skips download steps automatically when the
    host is offline; per-package failures are caught so one bad URL does
    not abort the whole run.
  - Idempotent: an optional `Marker` sentinel file per package
    (defaults to `setup.exe`) short-circuits re-extraction; already-downloaded
    payloads in `%TEMP%` are reused; the target directory is created on
    demand.
- `scripts/Secrets.psd1`
  - Centralised, opt-in credential loader. `serviceAccounts[*].IsAdAccount`
    controls whether the entry is an Active Directory account (default) or a
    container for non-AD secrets (DSRM password, PFX passwords, passphrases).

### Changed

- Standardised the four configuration scripts (`CfgAppPdc.ps1`, `CfgAppPull.ps1`,
  `CfgAppSql.ps1`, `CfgAppSps.ps1`) on a single template:
  - `#Requires -Version 5.1` + `#Requires -RunAsAdministrator`
  - Full comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`)
  - `[CmdletBinding()]` + `[System.String] $OutputPath` parameter
  - Tail compile-progress logging (timestamped node list and MOF path)
  - Enriched `catch` block that surfaces the failing script, line, and message
  - MOF output directory honour-override pattern (CLI > parameter > script default)
- `scripts/sps/CfgAppSps.psd1` simplified and aligned with `scripts/Secrets.psd1`:
  - Flattened `NonNodeData.Services.*` into direct children (`SharePoint`, `OOS`,
    `IIS`, `SQLAlias`) — easier to read, fewer keystrokes in the scripts.
  - Renamed the four certificates with a `Cert` suffix
    (`DscPullCert`, `SharePointCert`, `OfficeOnlineCert`, `SQLServerCert`) so
    they match Secrets entries 1:1 and the per-cert PFX-password lookup pattern
    works without a translation table.
  - Added a `CertName` indirection field on each Web Application, decoupling
    the descriptive WebApp name from the cert / Secrets entry name.
  - Sample tenant rebranded to `contoso.com` / `CONTOSO\`, single-host
    farm topology with `https://sharepoint.contoso.com` as the lone web app.
- `scripts/sps/CfgAppSps.ps1` wired to the simplified `.psd1`:
  - Web Application cert lookup now resolves through `$spWebApp.CertName`
    instead of `$spWebApp.Name`.
  - SharePoint cert-import filter excludes the renamed `*Cert` entries
    (`OfficeOnlineCert`, `SQLServerCert`, `DscPullCert`).
  - OOS cert lookups updated to `OfficeOnlineCert`.
  - `$spManagedAccounts` rebuilt from an intermediate `$IsNotUserAccounts`
    variable so the upstream `IsAdAccount` filter handles container entries
    automatically; the inline exclude list only carries true exceptions.
- Per-certificate PFX password pattern adopted across PDC and SPS:
  - `CertificatePassword = (Get-Variable -Name $certificate.Name -ValueOnly)`
  - Each certificate is decrypted with its own password resolved from
    `Secrets.psd1`, removing the shared `$PFXCred` dependency.

### Fixed

- `scripts/sps/CfgAppSps.ps1`
  - Non-master SharePoint Node selector silently matched zero nodes when the
    `IsMaster` key was missing from a node. `$null -eq $false` is `$False` in
    PowerShell, so `$_.IsMaster -eq $false` filtered out everything. Replaced
    with `-not $_.IsMaster`, which is robust to either missing-key or
    explicit `$false`.
  - `NonNodeData.ADS.DomainName` (which did not exist) replaced by
    `NonNodeData.DomainName`, so the SharePoint nodes' `JoinDomain` block
    actually receives a non-null domain name.
  - `IsWACServer` typo replaced by `IsOOSServer` in the OOS JoinFarm selector.
  - Cleared cosmetic drift (lowercase cmdlet names, double-space `-Path`,
    `Throw` capitalisation, `PsDscRunAscredential` typo, orphan block
    comment, `$RequiredFeatures` casing).

### Documentation

- Refreshed all wiki pages (`Home.md`, `Getting-Started.md`,
  `Configuration.md`, `Usage.md`) to make the project scope explicit:
  SPSConfigKit is a **SharePoint Server Subscription Edition** installation
  and configuration kit driven by PowerShell DSC. The PDC, PULL, and SQL
  scripts are bundled **as reference examples only** to make the sample
  environment self-contained — they are not intended for production use.
