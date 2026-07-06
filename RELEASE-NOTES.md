# SPSConfigKit - Release Notes

## [1.5.0] - 2026-07-06

### Added

- Optional domain-join helper for cloud nodes (#18)
  - New `scripts/init/Add-DscNodeToDomain.ps1` (+ `.psd1`) points a node's DNS at
    the domain controller and joins it to Active Directory before the node's DSC
    configuration is applied. A freshly provisioned cloud VM (e.g. Azure, whose
    default DNS is 168.63.129.16) cannot otherwise resolve or join the domain.
    The helper is idempotent (skips when already a member), sets DNS only when
    `DnsServers` is provided (on-prem nodes with working DNS leave it `@()`),
    waits for the domain LDAP SRV record, joins with the `Secrets.psd1`
    `JoinAccount` credential (`ADSETUP` by default) honouring an optional
    `OUPath`, and restarts after a readable countdown (`RestartDelaySec`).
- The pull server now publishes the SoftwarePackages SMB share (#19)
  - `CfgAppPull.ps1` creates `<Drives.Data>\SoftwarePackages` and publishes it as
    the SMB share named after the last segment of `NonNodeData.SourcePath`
    (native `New-SmbShare`, no new DSC module, idempotent). A new optional
    `NonNodeData.SoftwarePackagesShare.ReadAccess` list (default
    `'Authenticated Users'`) lets production lock the share down. Nodes no longer
    need the share created by hand before they can pull binaries.
- Dashboard `-Action Install` provisions the node manifest share (#23)
  - `SPSDscDashboard.ps1 -Action Install` now creates the `NodeManifestPath`
    folder and publishes it as an SMB share (member nodes write their
    `<NodeName>.json` there at LCM registration via `CfgLcmPull.ps1
    -NodeManifestPath`). Name and write access come from an optional
    `NodeManifestShare` block in `SPSDscDashboard.psd1` (default share name = the
    folder leaf, default `ChangeAccess = 'Authenticated Users'`). A UNC
    `NodeManifestPath` is left untouched. `-Action Default` is unchanged.

### Changed

- Faster software-package downloads (#16)
  - `Initialize-SoftwarePackages.ps1` sets `$ProgressPreference = 'SilentlyContinue'`
    (the Invoke-WebRequest progress bar made multi-GB downloads an order of
    magnitude slower on Windows PowerShell 5.1) and adds an `Invoke-SPSDownload`
    helper that prefers `Start-BitsTransfer` (resumable, faster) and falls back to
    `Invoke-WebRequest` when BITS is unavailable.

### Fixed

- Dashboard renders node errors and timestamps cleanly (#25)
  - Failed-node error banners showed raw report JSON with undecoded `\uXXXX`
    escapes; they now display the human-readable `ErrorMessage`. A node with no
    valid report yet (e.g. mid `Update-DscConfiguration`) showed the sentinel
    date `1899-12-30`; it now renders `—`.
- CfgAppSql no longer creates a duplicate SqlLogin for the FARM account (#24)
  - When the farm account is also a SQL sysadmin (the default posture), the
    `SQLSysAdministrators` loop and the separate `MIDDLEWARE_SqlLogin_FARM` block
    created two `SqlLogin` resources for the same login, which DSC rejected with
    "conflicting values of PsDscRunAsCredential". The FARM login is now created
    only when it is not already in `SQLSysAdministrators`, and the dependent
    dbcreator / securityadmin `SqlRole` grants point at whichever login exists.
- PDC `WaitForADDomain` no longer loops after a new-forest promotion (#17)
  - Removed `Credential = $ADSETUP` / `WaitForValidCredentials = $true` from
    `WaitForADDomain WaitForDCReady`: on the DC itself (running as SYSTEM) that
    impersonated a domain account this configuration has not created yet, so the
    resource never found the DC and looped `WaitTimeout` × `RestartCount`.
- Pull server MOF can now be applied when document encryption is enabled (#20)
  - Added `CertificateID = $Node.Thumbprint` to the pull server's
    `LocalConfigurationManager` block (matching SQL/SPS/PDC), so the LCM can
    decrypt the encrypted MOF instead of failing with "The Local Configuration
    Manager is not configured with a certificate". The pull quick-start now also
    documents the `Set-DscLocalConfigurationManager` meta-config step.
- Pull server resolves its own certificate paths locally (#22)
  - `CfgAppPull.ps1` derives the `DscPull` `.cer` / `.pfx` paths from the local
    Data drive (`<Drives.Data>\<share leaf>`, e.g. `F:\SoftwarePackages`) instead
    of its own UNC share, removing a chicken-and-egg (the share is published by
    the same MOF, so the UNC did not resolve at first apply and `xDscWebService`
    failed on the `0000…` sentinel thumbprint). The other configurations keep
    reading from the UNC share.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
