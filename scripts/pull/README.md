# DSC Pull Server (reference)

> [!IMPORTANT]
> `CfgAppPull.ps1` and `CfgLcmPull.ps1` ship as **reference examples** so the
> sample lab can stand up a working pull server quickly. Do **not** deploy them
> as-is in production — front the pull server with a hardened HTTPS configuration,
> secure the registration key, and use your organisation's pull-server pattern.

This folder configures the two halves of a classic Windows DSC pull deployment:

| Script | Runs on | Purpose |
| --- | --- | --- |
| `CfgAppPull.ps1` | the pull server | Compiles the MOF that stands up the DSC Web Service (endpoint `PSDSCPullServer`, HTTPS/443, ESENT/`Devices.edb` backend), IIS hardening, registration-key file, firewall rule. |
| `Set-SPSPullServerPermission.ps1` | the pull server | **Post-configuration, one-shot.** Grants the pull-server AppPool identity write access to the DSC service folder so the ESENT repository (`Devices.edb`) can be created. See below. |
| `CfgLcmPull.ps1` | every managed node | Configures the LCM in Pull mode (`ConfigurationRepositoryWeb` + `ResourceRepositoryWeb` + `ReportServerWeb`) so the node pulls, applies, and **reports** its configuration. |
| `CfgLcmPull.DomainDefaults.sample.psd1` | authoring | Template for per-domain pull-server defaults consumed by `CfgLcmPull.ps1 -DomainDefaultsPath`. Copy to `CfgLcmPull.DomainDefaults.psd1` (git-ignored) and fill in real values. |

## End-to-end workflow

1. **Stand up the pull server** — on the pull server, compile and apply:

   ```powershell
   .\CfgAppPull.ps1
   Start-DscConfiguration -Path .\MOF -Wait -Verbose -Force
   ```

2. **Grant the AppPool write access to the DSC service folder** — once, elevated,
   on the pull server:

   ```powershell
   .\Set-SPSPullServerPermission.ps1 -AppPoolIdentity 'CONTOSO\svcpulliisapp'
   ```

   > **Why this is a separate step, not a DSC resource.** The DSC service folder
   > (`C:\Program Files\WindowsPowerShell\DscService`) is owned by
   > `NT SERVICE\TrustedInstaller` and grants SYSTEM / Administrators only *Modify*
   > on the folder object — **not** Change-Permissions (WRITE_DAC). So the ACL
   > can't be edited in place: `Set-Acl` (as SYSTEM) fails with *"Attempted to
   > perform an unauthorized operation"* and `icacls /grant` fails with *"Access is
   > denied"*. The script takes ownership first (`takeown /a`) and then grants
   > (`icacls /grant …:(OI)(CI)M`) — a privileged, one-shot sequence that does not
   > belong in the recurring DSC consistency loop. Without this grant the AppPool
   > cannot create `Devices.edb`, so no reports are stored and the compliance
   > dashboard stays empty.

3. **Publish the node MOFs** (compiled by `CfgAppSps.ps1`, one `<NodeName>.mof`
   per node) plus their `.mof.checksum` into the pull server's `Configuration`
   folder (`C:\Program Files\WindowsPowerShell\DscService\Configuration`).

4. **Register each node's LCM in Pull mode** — on every SharePoint / OOS node:

   ```powershell
   .\CfgLcmPull.ps1 -DSCRegistrationKey '<guid>' `
                    -DSCPullServerUrl 'https://pull.contoso.com/PSDSCPullServer.svc' `
                    -UpdateNow
   ```

   `-UpdateNow` triggers the first pull immediately, so the node applies its
   configuration and sends its first status report right away — which populates
   `Devices.edb` and the [compliance dashboard](../dashboard/README.md).

5. **Watch compliance** — generate the dashboard on the pull server:

   ```powershell
   ..\dashboard\New-SPSDscDashboard.ps1 -PullServerUrl 'https://localhost/PSDSCPullServer.svc' -SkipCertificateCheck -OutputPath .\Dashboard.html
   ```

## `Set-SPSPullServerPermission.ps1` parameters

| Parameter | Purpose |
| --- | --- |
| `-AppPoolIdentity` | **Required.** The IIS AppPool identity that runs the pull server (the `IISPULLAPP` account from `Secrets.psd1`), e.g. `CONTOSO\svcpulliisapp`. |
| `-DscServicePath` | DSC service folder to grant on. Default `"$env:PROGRAMFILES\WindowsPowerShell\DscService"`. |
| `-TakeOwnership` | Take ownership before granting (default `$true`). Set to `$false` if the folder is already owned by Administrators / SYSTEM. |

The script is idempotent (re-running re-asserts the grant and exits 0), supports
`-WhatIf`, and requires an elevated session.
