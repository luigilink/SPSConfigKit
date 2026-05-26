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
   the SMB share consumed by every node &mdash; typically the PDC, exposing
   `\\PDC1\SoftwarePackages` backed by `F:\SoftwarePackages`):

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

   ```powershell
   .\scripts\init\Initialize-DscEncryption.ps1
   ```

   This produces `DscEncryption.cer` and `DscEncryption.pfx` and copies them
   to the share defined in `Initialize-DscNode.psd1` (`SourcePath`).

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

7. **Compile and apply** the MOFs. See the [Usage](./Usage) page.

## Next step

Continue with the [Configuration](./Configuration) page.

## Change log

Full history in
[CHANGELOG.md](https://github.com/luigilink/SPSConfigKit/blob/main/CHANGELOG.md).
