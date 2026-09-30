# SPSConfigKit - Release Notes

## [1.8.0] - 2026-09-30

### Added

- Dashboard header now shows the SPSConfigKit version, and the per-node table shows the last
  check type (#80)
  - The old per-node `Version` column only ever showed the DSC document's
    `MinimumCompatibleVersion` (`2.0.0`), which is constant across the farm and carries no useful
    signal. It is replaced by a **Last check** column showing the type of the node's latest report
    (`Consistency` / `Initial` / …), which actually varies per node and makes the stale-report
    detection below self-explanatory. The kit version is now shown once in the dashboard header,
    read from the new `KitVersion` setting in `SPSDscDashboard.psd1` (bump it at release time).

- Central Administration can be served over HTTPS on a vanity URL (#63)
  - New `NonNodeData.SharePoint.CentralAdministrationUrl`: when set to an HTTPS URL (e.g.
    `https://sharepoint-admin.contoso.com`), `CfgAppSps` provisions Central Administration over
    SSL on that host instead of `http://<node>:<port>`. `CfgAppPdc` issues a new
    `SharePointAdminCert` certificate (SAN `sharepoint-admin.contoso.com`) and publishes a
    matching DNS record. On SharePoint Subscription Edition the certificate is bound through
    SharePoint Certificate Management (never a manual IIS binding): `SPFarm` provisions the
    Central Admin HTTPS binding and host header, the `SPCertificate` loop imports
    `SharePointAdminCert` into the SharePoint certificate store (`EndEntity`) after the farm
    exists, and a new `Script` resource then binds that managed certificate to the Central Admin
    Default zone (`Get-SPCertificate` → `Set-SPWebApplication -Certificate
    -UseServerNameIndication`), mirroring how `SPWebApplicationExtension` binds certificates on
    SPSE. The Central Admin outgoing-email settings are pointed at the HTTPS URL. The sample now
    defaults Central Admin to `https://sharepoint-admin.contoso.com` on port 443, with a
    `SharePointAdminCert` entry added to `Secrets.sample.psd1`. Leave `CentralAdministrationUrl`
    empty to keep Central Admin on plain HTTP. The binding `Script` retries for up to 5 minutes
    (verifying the binding actually carries the certificate) because right after the
    `SPCertificate` import the certificate can briefly not be bindable yet — this avoids a
    transient failure that would otherwise self-heal only on the next pull. Both the `Test` and
    `Set` scripts guard against certificate-less bindings (a binding whose `Certificate` is
    `$null` before the cert is bound): the thumbprint comparison is skipped instead of
    dereferencing a missing property, so `Test` never throws `PropertyNotFoundException` — which
    would otherwise abort the entire configuration run rather than just failing one resource.
- The domain GPO now pushes the Edge `AuthServerAllowlist` policy (#57)
  - `CfgAppPdc` already provisions an `Edge_browser` GPO (linked to the domain) from
    `NonNodeData.EdgePolicies`. An `AuthServerAllowlist` entry is added to that list so the GPO
    enables seamless Integrated Windows Auth (Kerberos/NTLM SSO) from Edge to the intranet on
    **every** domain-joined server, including the SharePoint nodes. This is the GPO-managed
    counterpart to the opt-in `SharePoint.EdgeAuthAllowlist` from #55: with the GPO in place,
    farms leave that key disabled and let the domain policy own it. Sample value `*.contoso.com`
    (adjust to your domain); sample `.psd1` only — the GPO mechanism already existed.

### Changed

- Bumped `SharePointDsc` from 5.7.0 to 5.7.1 (#67)
  - Patch release (no breaking changes): `SPInstallPrereqs` now reboots and retries when a
    prerequisite installer fails to download, and a random `MSFT_SPFarm` event-log error on
    Windows Server 2025 is fixed. Updated the pinned version in `Initialize-DscNode.psd1`, the
    `Import-DscResource` in `CfgAppSps.ps1`, and the dashboard sample mock data.
- `Secrets.psd1` now ships as a tracked `.sample` template with the real file git-ignored (#59)
  - The service-account credentials file used to be tracked directly, which risked committing
    real farm passwords (and a `git checkout` could revert a locally-filled copy back to
    placeholders). Following the repo's existing `.sample.psd1` convention
    (`CfgLcmPull.DomainDefaults`), only `scripts/Secrets.sample.psd1` (placeholder passwords) is
    now tracked; the real `scripts/Secrets.psd1` is git-ignored. Copy the sample once
    (`Copy-Item scripts/Secrets.sample.psd1 scripts/Secrets.psd1`) and fill in your passwords —
    the `Cfg*.ps1`, init, pull and test scripts still default to `scripts/Secrets.psd1` and
    already error clearly when it is missing. Documented in the README and wiki.
- Polished the README and wiki documentation (#61)
  - Enriched the README badge row (latest release/version, license, last commit) and lightened
    the README by moving already-duplicated content to the wiki: the verbose Requirements/WMF
    block and the full DSC-modules list (the Getting-Started page has a pinned-version table),
    and condensed the credential-encryption section to the key statement plus a link (the
    Securing-Credentials page has the full walkthrough). Added a `_Sidebar.md` wiki navigation
    and a `Release-Process.md` page (tag-based release model), and refreshed the `Home` page
    list. Documentation only.

### Removed

- Removed the redundant Chocolatey install logic from `Initialize-SoftwarePackages.ps1` (#65)
  - `Initialize-SoftwarePackages.ps1` (run once on the file-share host to stage/download the
    SharePoint/SQL/OOS binaries) carried a Chocolatey bootstrap + `choco install` block that
    duplicated the logic already owned by `Initialize-DscNode.ps1` (the node-bootstrap script).
    The block was in fact dead code: `Initialize-SoftwarePackages.psd1` never defined a
    `Chocolatey` section, so `$configurationData.Chocolatey.Ensure` was always `$null` and the
    step never ran. Chocolatey is now solely the responsibility of `Initialize-DscNode.ps1`.
    The comment-based help and the outbound-internet check messaging were updated to drop the
    Chocolatey wording (the internet check itself stays — it still gates the downloads).

### Fixed

- Dashboard no longer renders a resource-less report as Compliant (#80)
  - A node whose latest report carried no resources — a `Get-Action` / `Initial` report, or a run
    whose oversized `StatusData` never posted — was shown as a green `Compliant 0/0`. The state
    logic now requires at least one evaluated resource to call a node Compliant; a resource-less
    report is marked **Stale / No data** (a distinct, non-green state that sorts above Compliant),
    so an empty `0/0` can no longer masquerade as healthy. This is the dashboard-side counterpart
    to the pull-server report-size fix (#79).
- Pull server now accepts large consistency reports from the master node (#79)
  - The `web.config` generated by `xDscWebService` set no request-size limits, so the pull server
    ran on framework defaults — in particular the WCF `maxReceivedMessageSize` of **64 KB**. The
    master SharePoint node carries the full farm configuration (SPFarm, every service application,
    search topology, certificates, web applications), so its consistency report (~76 KB) exceeded
    that limit and `SendReport` was rejected with HTTP 413 (`RequestEntityTooLarge`) — the
    consistency check ran fine but the report never posted, leaving the master permanently
    invisible (stale, empty report) on the compliance dashboard. `CfgAppPull` now raises the WCF
    `webHttpBinding` `maxReceivedMessageSize` (the decisive limit) to 30 MB via a `Script` that
    patches the generated `web.config`, and also raises the ASP.NET `maxRequestLength` and IIS
    `maxAllowedContentLength` to 30 MB via two `WebConfigProperty` resources so no other layer
    caps the upload.
- OOS nodes no longer perform the domain join in DSC (#77)
  - The `IsOOSServer` Node block still declared `Computer JoinDomain` and a
    `PendingReboot RebootOnSignalFromJoinDomain`, even though every node is domain-joined by the
    init script (`Add-DscNodeToDomain.ps1`) before the pull runs — as the SharePoint nodes already
    are. `PendingReboot` re-detected a phantom post-join reboot on every consistency check, so the
    OOS node was reported **Non-Compliant** on each pass. Both resources (and the now-unused
    `ComputerManagementDsc` import) were removed, and `Group AddSPSetupAccountToAdminGroup` no
    longer depends on the reboot, matching the SharePoint node blocks.
- Distributed Cache is now provisioned in a deterministic order across cache nodes (#75)
  - On an HA farm with more than one cache node (`IsAFCache`), every cache node emitted
    `SPDistributedCacheService Ensure='Present'` **without** `ServerProvisionOrder`, so each node
    independently ran `Add-SPDistributedCacheServiceInstance` followed by the resource's
    *farm-wide* stop / resize / start sequence at the same time. The nodes raced each other on the
    30-minute *"waiting for distributed cache to stop/start on all servers"* loops, leaving the
    cluster half-provisioned and reporting non-deterministic drift (one node compliant, the other
    stuck). MinRole (`WebFrontEndWithDistributedCache` / `DistributedCache`) flags a stopped cache
    host as non-compliant but does **not** start the Distributed Cache instance itself, so each
    cache node must provision its own instance through DSC. The ordered list of cache nodes is now
    passed to every `SPDistributedCacheService` as `ServerProvisionOrder`, the native SharePointDsc
    mechanism that serialises provisioning: each node waits for the previous cache host to come
    online before it acts. In steady state `Test` short-circuits on the already-provisioned nodes,
    so the farm-wide resize runs only when a host actually needs (re)provisioning. Single-cache-node
    farms are unaffected (the order list contains just that node and the wait loop exits
    immediately).
- Search topology now waits for secondary search nodes to join the farm (#72)
  - On a multi-node search farm, the search master built `SPSearchTopology` (assigning search
    components to every search node) with only a local dependency, so it could run before a
    secondary search node had finished joining the farm — failing with *"the search service
    instance is not online on server &lt;node&gt;"* (a transient Failed state that self-heals on
    the next pull). The search master now emits a `WaitForAll` on the other search nodes'
    farm-join log before the topology runs. Only emitted when a second search node exists, so
    single-search-node farms (the default sample) are unchanged. The search-master role filter
    was also aligned to the explicit `Search` / `ApplicationWithSearch` set used elsewhere
    (previously a `-like "*Search*"` match).
- `CfgAppSql` now adds the setup account to the local Administrators group (#70)
  - The `SqlProtocol`, `SqlProtocolTcpIP` and `SqlSecureConnection` resources run under `$SETUP`
    and perform Windows-level operations (service control, `HKLM` registry, certificate
    private-key ACL) that require local administrator rights. `$SETUP` is a SQL sysadmin but was
    not a local admin, so they failed with *Access is denied* / *Requested registry access is
    not allowed* / missing `SeSecurityPrivilege`. A `Group` resource (RunAs `$ADSETUP`) now adds
    the new `NonNodeData` node `LocalAdmins` accounts to the local `Administrators` group before
    those resources run, mirroring `CfgAppSps`.


## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
