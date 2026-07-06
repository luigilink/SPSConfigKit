# Getting Started

> [!IMPORTANT]
> SPSConfigKit is built for **SharePoint Server Subscription Edition
> installation and configuration** via PowerShell DSC. The `pdc/`, `pull/`
> and `sql/` scripts ship as **reference examples** so the lab is
> self-contained, but you should provision Active Directory, your DSC
> pull server, and SQL Server with your organisation's production tooling.

## Prerequisites

### Authoring host (where you compile the MOFs)

- Windows Server 2019 / 2022 or Windows 10 / 11
- PowerShell 5.1 (Windows PowerShell &mdash; not PowerShell 7+, because DSC
  v1 `Configuration` blocks require WMF 5.1)
- Administrative privileges
- Network access to the file share that hosts the binaries and the DSC
  document-encryption certificate (the share path is set in
  `Initialize-DscNode.psd1`)
- **Pester 5.0.0 or later** &mdash; required by the
  `scripts/test/Invoke-ConfigDataTest.ps1` pre-flight validator. Windows
  PowerShell 5.1 ships with Pester 3.x, so install the newer version
  side-by-side:

  ```powershell
  Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
  ```

### Target nodes (SharePoint servers + OOS)

- Windows Server 2019 or Windows Server 2022
- PowerShell 5.1 with WMF 5.1
- Administrative privileges for the setup account
- CredSSP enabled when applying configurations that cross authentication
  boundaries (see below)
- The DSC document-encryption certificate imported into
  `Cert:\LocalMachine\My` (handled automatically by
  `Initialize-DscNode.ps1`)

## Required DSC modules

`scripts/init/Initialize-DscNode.psd1` is the single source of truth. The
versions below are the ones currently pinned:

| Module                          | Version    |
| ------------------------------- | ---------- |
| ActiveDirectoryDsc              | 6.7.1      |
| ActiveDirectoryCSDsc            | 5.0.0      |
| CertificateDsc                  | 6.0.0      |
| ComputerManagementDsc           | 10.0.0     |
| NetworkingDsc                   | 9.1.0      |
| OfficeOnlineServerDsc           | 1.5.0      |
| PSDscResources                  | 2.12.0.0   |
| SharePointDsc                   | 5.7.0      |
| SqlServerDsc                    | 17.5.1     |
| WebAdministrationDsc            | 4.2.1      |
| xCredSSP                        | 1.4.0      |
| xPSDesiredStateConfiguration    | 9.2.1      |

Documentation for each module is available on the
[DSC Community](https://github.com/dsccommunity) organisation.

## CredSSP

CredSSP is required whenever a DSC resource on a node needs to act under
credentials that aren't its own (for example, the SharePoint setup account
talking to SQL Server during `SPFarm` provisioning).

### Option 1: configure CredSSP manually

Use the cmdlets documented at
[Microsoft Docs &mdash; CredSSP](https://learn.microsoft.com/powershell/module/microsoft.wsman.management/about/about_wsman_cmdlets)
together with a Group Policy that lists the allowed delegate computers.

### Option 2: configure CredSSP via DSC

The `xCredSSP` resource (pinned above) lets every configuration enable
CredSSP as part of its run:

```powershell
xCredSSP CredSSPServer {
    Ensure = 'Present'
    Role   = 'Server'
}

xCredSSP CredSSPClient {
    Ensure            = 'Present'
    Role              = 'Client'
    DelegateComputers = $CredSSPDelegates
}
```

`$CredSSPDelegates` can be a wildcard (`*.contoso.com`) or an explicit list
of servers (`'sp-app-01', 'sp-wfe-01'`).

## Installation workflow

1. **Clone or download the latest release.**

   ```powershell
   git clone https://github.com/luigilink/SPSConfigKit.git
   # — or —
   # download https://github.com/luigilink/SPSConfigKit/releases/latest
   ```

2. **Populate the SoftwarePackages share** (one-time, on the VM that hosts
   the SMB share consumed by every node):

   > [!IMPORTANT]
   > Host this share on a **member server** (the pull server is a good choice),
   > **not on a domain controller**. The DSC `File` resources copy the binaries
   > using the `svcspssetup` credential; because every node already has a machine
   > session to the DC, Windows refuses a second identity to the same server and
   > the apply fails with *"Access is denied"*. Grant `svcspssetup` **Read** on
   > the share and its NTFS path.

   ```powershell
   .\scripts\init\Initialize-SoftwarePackages.ps1
   ```

   The script reads `Initialize-SoftwarePackages.psd1` (next to the
   script), then downloads each entry &mdash; SQL Server 2022 + CU,
   SharePoint Server SE + Language Pack + CU, the SharePoint
   prerequisites (.NET 4.8 and VC++ 2015&ndash;2019), Office Online
   Server CU &mdash; into a folder layout under the configured
   `Repository` root. ISOs are expanded with Windows' built-in
   `Mount-DiskImage` pipeline, so no 7-Zip or other external tool is
   required.

   Re-runs are idempotent: already-extracted ISOs (detected by the
   per-package `Marker` sentinel, default `setup.exe`) and
   already-downloaded payloads are skipped. See the
   [Configuration](./Configuration) page for the manifest schema.

3. **Generate the DSC document-encryption certificate** (one-time, on the
   authoring host or on a designated certificate host):

   > [!IMPORTANT]
   > This step is **mandatory**, not optional. It encrypts every credential the
   > kit compiles into the MOFs. Skipping it leaves service-account passwords and
   > the farm passphrase in clear text inside the MOF files — an unsupported and
   > dangerous configuration. See [Securing Credentials](./Securing-Credentials).

   > [!NOTE]
   > Run this on the **authority host only** — the single machine that owns the
   > key pair. Every other node *imports* the resulting `.pfx` via
   > `Initialize-DscNode.ps1`; it never runs `Initialize-DscEncryption.ps1`
   > itself. Running the generator on a node would mint a **different**
   > certificate and cause *"Decryption failed"* at apply time.

   ```powershell
   $pfxPwd = Read-Host 'PFX password' -AsSecureString
   .\scripts\init\Initialize-DscEncryption.ps1 -PfxPassword $pfxPwd
   ```

   This produces `DscEncryption.cer` and `DscEncryption.pfx`, copies them to the
   share defined in `Initialize-DscNode.psd1` (`SourcePath`), and patches every
   `Cfg*.psd1` so the wildcard node sets `PSDscAllowPlainTextPassword = $false`
   with the certificate's `CertificateFile` / `Thumbprint`. After this,
   compilation **requires** every node to hold the certificate (next step).

4. **Bootstrap every target node** (run on each SharePoint / OOS server):

   ```powershell
   .\scripts\init\Initialize-DscNode.ps1
   ```

   This installs Chocolatey, the listed Chocolatey packages, every DSC
   module at its pinned version, and imports `DscEncryption.pfx` into
   `Cert:\LocalMachine\My`. The Chocolatey and `Install-Module` phases are
   skipped automatically if the node has no outbound internet.

5. **Fill in `scripts/Secrets.psd1`** with the AD service accounts, the
   farm passphrase, the DSRM password, and the PFX passwords for every
   certificate referenced by your configuration. See the
   [Configuration](./Configuration) page for the schema.

6. **Customise `scripts/sps/CfgAppSps.psd1`** to describe your nodes, your
   web applications, your SQL aliases, and your search topology. See the
   [Configuration](./Configuration) page for a walkthrough of each section.

   > [!NOTE]
   > **Data disks** &mdash; the `NonNodeData.Disks` block describes the node's
   > physical data disks (`SYSTEM` / `DATA` / `LOGS`, keyed by disk **Number**).
   > On a brand-new farm, prepare them once per node with the bootstrap helper,
   > which reads this same block and onlines / GPT-partitions / NTFS-formats /
   > letters your raw data disks &mdash; no manual `Get-Disk` / `Format-Volume`
   > step:
   >
   > ```powershell
   > .\scripts\init\Initialize-DscDisks.ps1 -ConfigPath .\scripts\sps\CfgAppSps.psd1
   > ```
   >
   > Run it **after** `Initialize-DscNode.ps1` and **before** compiling / applying
   > the node's MOF (and before `Initialize-SoftwarePackages.ps1`, which writes to
   > `<Data>:\SoftwarePackages`). It is idempotent and non-destructive. Set
   > `ManageDisks = $false` if the customer has already formatted their volumes
   > (the script then does nothing). Adjust each `Id` to match `Get-Disk` on the
   > target node.

7. **Validate your ConfigurationData** before compiling any MOF:

   ```powershell
   .\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sps\CfgAppSps.psd1
   ```

   The Pester v5 suite catches the common mistakes that would otherwise
   surface mid-run on the customer site (placeholder product key,
   duplicate `NodeName`, managed account missing from `Secrets.psd1`,
   mismatched `CertName`, unreachable `\\share\setup.exe`, &hellip;). Add
   `-SkipFilesystem` to skip the share / `.cer` / `.pfx` /
   `setup.exe` reachability checks when the install share isn't mounted
   on the authoring host. The driver exits with code `1` on the first
   failure so it can be wired into CI. See the
   [Configuration](./Configuration#validating-your-configurationdata) page
   for the full check list.

8. **Compile and apply** the MOFs. See the [Usage](./Usage) page.

9. **Verify the MOFs are encrypted** before shipping them, as a post-compile
   security gate:

   ```powershell
   .\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF
   ```

   The Pester guard-rail fails (exit code `1`) if any credential was compiled in
   clear text — the safety net that confirms step 3 actually took effect. See
   [Securing Credentials](./Securing-Credentials).

## Next step

Continue with the [Configuration](./Configuration) page.

## Change log

Full history in
[CHANGELOG.md](https://github.com/luigilink/SPSConfigKit/blob/main/CHANGELOG.md).
