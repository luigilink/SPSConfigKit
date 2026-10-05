# SPSConfigKit - Release Notes

## [1.9.0] - 2026-10-05

This release adds a complete **User Profile AD Import + My Sites** capability to the kit, plus a
reliability fix on the lab domain controller. Every new block is optional and emitted only when its
configuration is present, so farms that do not use these features are unaffected.

### Added

- Provision My Sites (personal sites) and their storage for AD-imported users (#90)
  - Once users are imported (#84/#86), `CfgAppSps` can provision the My Site infrastructure from an
    optional `Services.MySite` block in the `.psd1`. It emits an `SPQuotaTemplate` for personal
    sites and a set of dedicated `SPContentDatabase` resources sized from the expected user base:
    `NumberOfDatabases = max( ceil(UserCount * QuotaMaxMB / MaxDBSizeMB), ceil(UserCount /
    MaximumSiteCount) )`, with `MaximumSiteCount`/`WarningSiteCount` per database derived from the
    quota so no database exceeds the Microsoft-supported content-database size. `UserCount`,
    `QuotaMaxMB`, `QuotaWarningMB` and `MaxDBSizeGB` drive the auto-calculation; `NumberOfDatabases`,
    `MaximumSiteCount` and `WarningSiteCount` can be set explicitly to override it, and the config
    rejects inconsistent overrides (zero/negative counts, warning above maximum, a `WebAppUrl` that
    does not host the configured My Site host). A companion `Invoke-MySiteProvisioning.ps1` script,
    run once from the SharePoint Management Shell as the farm account, enumerates the User Profile
    Service profiles, skips the service accounts declared in `Secrets.psd1` (matched by full
    `DOMAIN\user` identity), creates each missing personal site and applies the quota template. It is
    idempotent (existing sites are re-quota'd, not recreated), supports `-WhatIf`, and terminates
    with an error if any profile fails so automated runs do not report false success.

- Add the User Profile AD Import synchronization connection (#86)
  - With the sync account in place (#84), `CfgAppSps` now declares a native
    `SPUserProfileSyncConnection` so the User Profile Service actually imports users from Active
    Directory. It reads an optional `Services.UserProfile.SyncConnection` block from the `.psd1`
    (`Forest`, `SyncAccount`, `IncludedOUs`), resolves the import credential from the named Secrets
    account (the same `Get-Variable` pattern used for certificate passwords), and sets
    `ConnectionType = 'ActiveDirectory'`. No `SPUserProfileSyncService` is added — that is for legacy
    FIM/MIM sync, not AD Import (`NoILMUsed = $true` stays). Because the kit targets SharePoint
    Subscription Edition, where the resource forces the connection name to the forest with dots as
    dashes and does not reconcile an excluded-OU list, the connection name is derived from `Forest`
    (not exposed) and `ExcludedOUs` is not exposed — the import scope is defined by `IncludedOUs`.

- Provision the User Profile AD Import sync account on the lab domain controller (#84)
  - User Profile AD Import needs a sync account that holds the **Replicate Directory Changes**
    permission on the domain. `Secrets.sample.psd1` gains an `ADSYNC` service account
    (`CONTOSO\svcspsync`), created by the existing `ADUser` loop, and `CfgAppPdc` grants it the
    `DS-Replication-Get-Changes` extended right on the domain root via the native
    `ADObjectPermissionEntry` resource (idempotent, least privilege — not the `-All` variant). The
    grant is emitted only when an `ADSYNC` entry exists in `Secrets.psd1`, and lives inside the
    `IsADSServer` block, so it runs only on the lab domain controller. Real farms rely on the
    customer-provided sync account instead; this is a lab convenience.

### Fixed

- PDC no longer reports a pending reboot on every run because of unrelated file renames (#88)
  - The `RebootOnSignalFromCreateADForest` `PendingReboot` resource reacts to any reboot source,
    so `PendingFileRenameOperations` queued by Microsoft EdgeUpdate (cleaning up an old updater
    version folder on next boot) flagged a pending reboot on every consistency check, even though
    it is unrelated to the AD DS promotion the resource is meant to handle. `SkipPendingFileRename`
    is now set so only the genuine post-promotion reboot (surfaced via Component-Based Servicing)
    triggers the resource.


## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
