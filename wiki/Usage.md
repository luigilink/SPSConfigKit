# Usage

> [!IMPORTANT]
> The workflow below describes how to compile and apply the **SharePoint
> Server Subscription Edition** farm configuration shipped in
> `scripts/sps/CfgAppSps.ps1`. The PDC, PULL and SQL scripts under
> `scripts/pdc/`, `scripts/pull/`, and `scripts/sql/` follow the same
> commands but are **reference examples only** &mdash; substitute your own
> AD, pull-server, and SQL provisioning tooling in production.

## Overview

The end-to-end flow is:

1. **Bootstrap every node** (once per node) with
   `scripts/init/Initialize-DscNode.ps1`.
2. **Compile** the MOFs on the authoring host with
   `scripts/sps/CfgAppSps.ps1`.
3. **Apply** the MOFs to each node using either:
   - `Start-DscConfiguration` (push), or
   - a DSC pull server with `Get-DscConfiguration` running under the LCM.
4. **Verify** with `Test-DscConfiguration` / `Get-DscConfigurationStatus`.

## Prerequisites checklist

- `scripts/Secrets.psd1` is filled in with real (or wrapped) credentials.
- `scripts/sps/CfgAppSps.psd1` describes your nodes, web app, SQL aliases,
  and search topology (see the [Configuration](./Configuration) page).
- The SoftwarePackages SMB share defined as `NonNodeData.SourcePath`
  (binaries, language packs, CUs, `.cer` / `.pfx`) is populated. The
  bundled `scripts/init/Initialize-SoftwarePackages.ps1` will fetch every
  entry listed in `Initialize-SoftwarePackages.psd1` for you &mdash; run it
  once on the file-share host.
- Every target node has been bootstrapped with
  `Initialize-DscNode.ps1` (modules pinned, document-encryption certificate
  imported into `Cert:\LocalMachine\My`).
- The setup account has read access to the share defined as
  `NonNodeData.SourcePath` (binaries, language packs, CUs, `.cer` / `.pfx`).
- CredSSP is enabled where the configuration requires it.

## 1. Bootstrap a node

Run on every SharePoint and Office Online Server target:

```powershell
# On the target node
.\scripts\init\Initialize-DscNode.ps1
```

To override the manifest path or supply the PFX password non-interactively:

```powershell
$pfxPwd = Read-Host 'PFX password' -AsSecureString
.\scripts\init\Initialize-DscNode.ps1 `
    -InputFile  'C:\Lab\Initialize-DscNode.psd1' `
    -PfxPassword $pfxPwd
```

The script installs Chocolatey + the listed packages, registers the NuGet
provider, installs every DSC module at its pinned version, and imports the
document-encryption `.pfx` into `Cert:\LocalMachine\My`. Internet-dependent
steps are skipped automatically on offline nodes.

## 2. Compile the SharePoint farm MOFs

On the authoring host (Windows PowerShell 5.1, RunAsAdministrator):

```powershell
cd .\scripts\sps
.\CfgAppSps.ps1
```

Default behaviour:

- Reads `CfgAppSps.psd1` from the script directory.
- Reads `..\Secrets.psd1` from the parent directory.
- Writes the MOF files (and checksums) to `.\MOF` next to the script.
- Logs the timestamped list of compiled nodes and the output path.

Override any of the three paths:

```powershell
.\CfgAppSps.ps1 `
    -inputFile   .\CfgAppSps.psd1 `
    -secretsFile ..\Secrets.psd1 `
    -OutputPath  C:\DSC\MOF\SPS
```

On success the output directory contains one `<NodeName>.mof` per node in
`AllNodes` (plus `<NodeName>.mof.checksum` if you publish to a pull
server).

### 2b. Verify the MOFs are encrypted (mandatory gate)

Before applying or publishing, confirm no credential was compiled in clear text:

```powershell
.\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\MOF
```

The guard-rail exits `1` if any `Password` value is not a CMS-encrypted blob, or
if a credential-bearing MOF is missing the `ContentType="PasswordEncrypted"`
marker. If it fails, run `scripts\init\Initialize-DscEncryption.ps1`, import the
`.pfx` on every node, and recompile. See
[Securing Credentials](./Securing-Credentials) for details.

## 3. Apply the MOFs

### Option A &mdash; push with `Start-DscConfiguration`

From the authoring host (or a jump box that can reach every node):

```powershell
Start-DscConfiguration `
    -Path     C:\DSC\MOF\SPS `
    -ComputerName 'APP1', 'WFE1', 'SCH1', 'OOS1' `
    -Credential   (Get-Credential 'CONTOSO\svcspssetup') `
    -Wait `
    -Verbose `
    -Force
```

`-Wait -Verbose` streams every resource invocation so you see exactly which
SharePoint resource is configuring what. Drop `-Wait` to fire-and-forget
and poll later with `Get-DscConfigurationStatus`.

### Option B &mdash; pull from a DSC pull server

1. Stand up the pull server with `scripts/pull/CfgAppPull.ps1`, then run
   `scripts/pull/Set-SPSPullServerPermission.ps1`
   **once, elevated, on the pull server** (it auto-resolves the pull AppPool
   account from `Secrets.psd1`; override with `-AppPoolIdentity` if needed). That
   post-configuration step grants the pull-server AppPool identity write access to
   the DSC service folder so the ESENT repository (`Devices.edb`) can be created
   &mdash; without it, no reports are stored. See `scripts/pull/README.md` for the
   full pull workflow.
2. Publish the resource modules with `scripts/pull/Publish-SPSPullModules.ps1`
   (defaults to every pinned module in `Initialize-DscNode.psd1`). This packages
   each module as `<Name>_<Version>.zip` + checksum in the pull server's `Modules`
   folder so nodes can download the resources their MOF imports.
3. Publish the MOFs (and checksums) to the pull-server's
   `Configuration` folder. The sample pull server in `scripts/pull/`
   exposes `C:\Program Files\WindowsPowerShell\DscService\Configuration`.
4. Register every node's LCM against the pull server with
   `scripts/pull/CfgLcmPull.ps1` (pass `-UpdateNow` to pull immediately). The
   bootstrap step already imports the correct certificate, so registration
   succeeds out of the box.
5. The LCM downloads the MOF on its configured interval (default 30 min)
   and applies it, then reports status back &mdash; which you can watch with the
   [compliance dashboard](./Home) (`scripts/dashboard/New-SPSDscDashboard.ps1`).

> The reference `scripts/pull/CfgAppPull.ps1` is provided so the sample
> lab can stand up a pull server quickly. **Do not deploy it as-is in
> production** &mdash; use your organisation's pull-server pattern, secure
> the registration key, and front it with HTTPS + a hardened LCM
> registration metaconfiguration.

## 4. Verify

```powershell
# Quick pass / fail
Test-DscConfiguration -ComputerName 'APP1'

# Detailed report
Get-DscConfigurationStatus -ComputerName 'APP1' -All | Format-List
```

Combine with `Get-DscConfiguration` to see what the LCM currently
considers the "applied" state of each resource.

## Logging

- The compile script logs every step to the console (input file, secrets
  file, MOF output path, timestamped node list).
- `Start-DscConfiguration -Verbose` surfaces every resource invocation
  including the SharePoint cmdlets that get called under the hood.
- DSC's own event log lives at
  **Microsoft-Windows-DSC/Operational** on each node.

## Re-running the configuration

The compile + apply flow is idempotent:

- Re-running `CfgAppSps.ps1` regenerates the MOFs (and checksums) in
  place.
- Re-running `Start-DscConfiguration` re-evaluates every resource and only
  reconfigures what has drifted.

It is safe to run after every change to `Secrets.psd1`, `CfgAppSps.psd1`,
or after a SharePoint cumulative update lands on the share.

## Error handling

- The compile script wraps everything in a `try { … } catch { … }` that
  surfaces the failing file, line number, and message before re-throwing
  &mdash; broken `.psd1` syntax or missing Secrets entries fail fast.
- `Start-DscConfiguration` failures show up in the DSC operational log;
  use `Get-DscConfigurationStatus -All` to walk the per-resource detail.

## Notes

- **Test in a non-production environment first.** SharePoint resources
  are powerful and several of them are not reversible (`SPFarm` create,
  `SPCertificate` import).
- The sample tenant uses `contoso.com` / `CONTOSO\`. Search and replace
  to your real domain before compiling.
- The sample farm is a single web application at
  `https://sharepoint.contoso.com` with three site collections. Add or
  remove WebApplications entries in `CfgAppSps.psd1` to match your
  topology &mdash; the `foreach ($spWebApp in $spWebApps)` loop in
  `CfgAppSps.ps1` iterates over whatever you provide.

## Support

For issues, feature requests, or documentation gaps, please open an issue
at <https://github.com/luigilink/SPSConfigKit/issues>.
