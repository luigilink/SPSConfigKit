# SPSConfigKit - Release Notes

## [1.5.0] - 2026-07-06

### Added

- The domain controller publishes DNS A records for the farm host names (#33)
  - `CfgAppPdc` gains an optional `NonNodeData.DnsRecords` list
    (`@{ Name; IPAddress }`) and creates each A record in the domain zone with
    `Add-DnsServerResourceRecordA`, so the SharePoint web-application and Office
    Online host names (`sharepoint.<domain>`, `oosweb.<domain>`) resolve.
    Without them, farm creation fails at the WOPI binding step with
    "The server did not respond". Native DnsServer module (no new dependency),
    idempotent per record.
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

- Remote Event Log Management firewall rule no longer drifts every pass (#35)
  - The `SYSTEM_EnableRemoteEventLogManagement` Script tested the `Domain` profile
    but enabled the rule with `-Profile Any`, so its Test never matched its Set and
    the resource re-ran every consistency check (a permanent, error-free drift on
    all four configs). The Test now checks the `Any` profile.
- CfgAppSps default disk Ids match the SharePoint VMs (no temp disk) (#32)
  - `CfgAppSps.psd1` shipped the temp-disk layout (0/2/3), but the SharePoint VM
    sizes (APP / SCH / WFE) have no Azure temp disk, so their real layout is 0/1/2.
    Defaulted DATA to disk Number 1 and LOGS to Number 2; a VM with a temp disk
    still shifts to 0/2/3 (as PDC/PULL/SQL use).
- Extracted ISO content is now unblocked (Mark-of-the-Web) (#30)
  - `Initialize-SoftwarePackages` unblocked directly-downloaded files but not
    content extracted from ISOs. Mounting a downloaded ISO propagates the
    Mark-of-the-Web to the copied files, so `prerequisiteinstaller.exe` stayed
    blocked and SharePoint's `SPInstallPrereqs` failed. The extracted content is
    now unblocked recursively.
- SQL Server TCP/IP protocol is now enabled, not just its port (#29)
  - `CfgAppSql` set the IPAll TCP port but never enabled the TCP/IP protocol, so
    Configuration Manager showed TCP/IP = Disabled and the instance listened on no
    TCP port — SharePoint and remote clients failed with "SQL Server does not exist
    or access denied". A `SqlProtocol` resource now enables TcpIp (with a service
    restart) before the port is set.
- CfgAppSps CU references now match the package manifest (#28)
  - The SharePoint (`UberCumulativeUpdate`) and OOS (`CUFileName`) cumulative
    updates referenced by `CfgAppSps.psd1` pointed at older KBs than
    `Initialize-SoftwarePackages.psd1` downloads, so a fresh farm's patch step
    looked for a CU that was never fetched. Aligned to the downloaded CUs
    (SharePoint `kb5002863`, OOS `kb5002871`).
- Dashboard shows a node's last real state while a run is in flight (#34)
  - A node whose LCM is mid-consistency-check has an in-progress report on top
    (no Status, sentinel `EndTime`); the dashboard picked it and showed `Unknown`,
    hiding the real state. It now selects the most recent report with a definitive
    Status (Success/Failure).
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
- SQL configuration resources run under a SQL sysadmin account (#26)
  - `SqlLogin` / `SqlRole` / `SqlMemory` / `SqlMaxDop` / `SqlProtocolTcpIP` ran
    with `PsDscRunAsCredential = $ADSETUP`, which `SqlSetup` never grants sysadmin,
    so every SQL resource failed with "Failed to connect to SQL instance"
    (SQLCOMMON0019). They now run under `$SETUP` (a member of the default
    `SQLSysAdministrators`, so a sysadmin from install).
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
