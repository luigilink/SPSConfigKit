# SPSConfigKit - Release Notes

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

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
