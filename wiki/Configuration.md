# Configuration

> [!IMPORTANT]
> The kit's first-class deliverable is the SharePoint farm configuration in
> `scripts/sps/`. The PDC, PULL and SQL `.psd1` files documented here are
> reference samples only &mdash; in production you should describe those tiers
> in your own tooling and only keep `Secrets.psd1` + `CfgAppSps.psd1` from
> this kit.

SPSConfigKit is driven by two PowerShell data files:

1. **`scripts/Secrets.psd1`** &mdash; centralised credential material.
2. **`scripts/sps/CfgAppSps.psd1`** &mdash; the SharePoint farm
   `ConfigurationData` consumed by `CfgAppSps.ps1`.

The configuration scripts (`CfgAppSps.ps1`, plus the example PDC / PULL / SQL
scripts) import both files and compile one MOF per node defined in
`AllNodes`.

## File layout

```text
scripts/
├── Secrets.psd1                ← credentials, shared by every config script
├── init/
│   ├── Initialize-DscNode.psd1            ← prerequisite manifest (modules, certs)
│   ├── Initialize-DscNode.ps1
│   ├── Initialize-DscEncryption.ps1
│   ├── Initialize-SoftwarePackages.psd1   ← package manifest (binaries, LPs, CUs)
│   └── Initialize-SoftwarePackages.ps1
├── sps/
│   ├── CfgAppSps.psd1          ← SharePoint farm ConfigurationData
│   └── CfgAppSps.ps1
├── pdc/                        ← REFERENCE EXAMPLE — not for production
├── pull/                       ← REFERENCE EXAMPLE — not for production
└── sql/                        ← REFERENCE EXAMPLE — not for production
```

## `Secrets.psd1`

A single `serviceAccounts` array. Each entry has a stable `Name` (used as
the variable name when the loader materialises a `PSCredential`) and an
optional `IsAdAccount` flag:

| Key           | Required | Description                                                                                          |
| ------------- | -------- | ---------------------------------------------------------------------------------------------------- |
| `Name`        | yes      | Stable identifier, used as the `PSCredential` variable name in the configuration scripts.            |
| `DisplayName` | yes      | Human-readable label, surfaced in logs.                                                              |
| `Description` | yes      | Free-form description.                                                                               |
| `Username`    | yes      | `DOMAIN\sam` for AD accounts; any non-empty value for non-AD containers (the loader requires it).    |
| `Password`    | yes      | Plain-text password. Replace with your own secret-management hook before checking the file in.       |
| `IsAdAccount` | no       | Default `$True`. Set to `$False` for containers that aren't real AD accounts (PFX passwords, DSRM, passphrase). |

Example:

```powershell
@{
    serviceAccounts = @(
        @{  # AD account — IsAdAccount omitted, defaults to $True
            Name        = 'SETUP'
            DisplayName = 'SharePoint SETUP'
            Description = 'SharePoint Setup Account'
            Username    = 'CONTOSO\svcspssetup'
            Password    = '************'
        }
        @{  # Non-AD container — used as a PFX password
            Name        = 'SharePointCert'
            DisplayName = 'SharePoint cert PFX'
            Description = 'PFX password for the SharePoint web-app certificate'
            Username    = 'SharePointCert'
            IsAdAccount = $False
            Password    = '************'
        }
    )
}
```

> [!CAUTION]
> Never commit real passwords to source control. The bundled `Secrets.psd1`
> uses `'******************'` placeholders. Replace it with a wrapper that
> pulls from your secret store (Azure Key Vault, CyberArk, etc.) before the
> file is read in any environment.

### How the loader uses `IsAdAccount`

- `IsAdAccount -ne $false` is the filter that selects AD accounts. Because
  `$null -ne $false` is `$true`, **omitting the key includes the entry**,
  which is the desired default for AD accounts.
- Containers (`ADSETUP`, `ADSAFEMODE`, `DscPullCert`, `SharePointCert`,
  `OfficeOnlineCert`, `SQLServerCert`, ...) must set `IsAdAccount = $False`
  to be excluded from `$spManagedAccounts` and similar AD-only collections.

### Certificate ↔ Secrets naming

Certificate `Name` values in `CfgAppSps.psd1` are intentionally chosen to
**match Secrets entries 1:1** (with a `Cert` suffix to make the intent
obvious). This lets the configuration scripts resolve each cert's PFX
password directly:

```powershell
CertificatePassword = (Get-Variable -Name $spCertificate.Name -ValueOnly)
```

A missing or misnamed Secrets entry fails fast at compile time.

## `scripts/sps/CfgAppSps.psd1`

The file is a single hashtable with two top-level keys: `AllNodes` and
`NonNodeData`.

### `AllNodes`

Per-node settings. The first entry must be the wildcard `'*'` node that
declares the DSC plain-text/domain-user policy:

```powershell
AllNodes = @(
    @{
        NodeName                    = '*'
        PSDscAllowPlainTextPassword = $True
        PSDscAllowDomainUser        = $True
    }
    @{
        NodeName     = 'APP1'
        IsMaster     = $true
        IsSPSServer  = $True
        SPVersion    = 'SE'
        SPServerRole = 'Application'  # ApplicationWithSearch | DistributedCache | Search | …
        LocalAdmins  = @('CONTOSO\svcspssetup', 'CONTOSO\svcspsfarm')
    }
    # WFE1, SCH1, OOS1 …
)
```

Node-selector flags:

| Flag                                | Used by                                                |
| ----------------------------------- | ------------------------------------------------------ |
| `IsSPSServer`                       | All SharePoint Node blocks.                            |
| `IsMaster`                          | Designates the farm-creator (vs. join-farm) node.      |
| `IsOOSServer`, `IsOOSSingle`        | Office Online Server Node block.                       |
| `SPServerRole`                      | `SPFarm.ServerRole` (MinRole).                         |
| `IsSrcAdmin`, `IsSrcCrawl`, `IsCntProc`, `IsSrcAnalyt`, `IsSrcQuery`, `IsIndexPart` | Search topology component placement. |
| `LocalAdmins`                       | `Group BUILTIN\Administrators` membership.             |

> [!NOTE]
> The non-master node selector uses `-not $_.IsMaster`, so you can omit
> `IsMaster` on non-master nodes &mdash; missing key and explicit `$false`
> both work.

### `NonNodeData`

Flat container of farm-wide settings:

```powershell
NonNodeData = @{
    # The share host is defined ONCE here. Host it on a MEMBER server (e.g. the
    # pull server), never on a domain controller (a node already holds a machine
    # session to the DC, and Windows refuses a second identity to the same server,
    # so a share on the DC fails at apply with "Access is denied").
    SourcePath = '\\PULL\Softwarepackages'    # binaries + .cer/.pfx share
    DomainName = 'contoso.com'

    # Set to $false when the customer manages storage themselves. Default $true.
    ManageDisks = $true
    # Data disks, initialised by scripts/init/Initialize-DscDisks.ps1 (keyed by
    # disk Number). This is the single source of truth for storage: the Drives.{Data,Logs,Temp}
    # hashtable consumed everywhere else is DERIVED from it by Type (see below).
    # Disk numbers are environment-specific — a plain VM is usually 0=OS, 1=Data,
    # 2=Logs; an Azure VM WITH a temp disk shifts to 0=OS, 1=<temp>, 2=Data,
    # 3=Logs. Adjust Id to match 'Get-Disk' on the node.
    Disks      = @(
        @{ Id = '0'; Letter = 'C'; Type = 'OS'  ; FSLabel = 'SYSTEM'; AllocationUnitSize = 4KB }
        @{ Id = '2'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'  ; AllocationUnitSize = 4KB }
        @{ Id = '3'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'  ; AllocationUnitSize = 4KB }
    )

    ADC        = @{
        # Each entry carries only the .cer / .pfx FILE NAME; the full path is
        # derived by the Cfg*.ps1 script as SourcePath + CerFileName / PfxFileName.
        # (An explicit CertPath / PfxPath is still honoured for backward compat.)
        certificates = @(
            @{ Name = 'SharePointCert'    ; FriendlyName = 'SharePoint'  ; CerFileName = 'SharePoint.cer'  ; PfxFileName = 'SharePoint.pfx'  }
            @{ Name = 'OfficeOnlineCert'  ; FriendlyName = 'OOSCertSSL'  ; CerFileName = 'OfficeOnline.cer'; PfxFileName = 'OfficeOnline.pfx' }
            @{ Name = 'SQLServerCert'     ; FriendlyName = 'SQLCertSSL'  ; CerFileName = 'SQLServer.cer'   ; PfxFileName = 'SQLServer.pfx'    }
            @{ Name = 'DscPullCert'       ; FriendlyName = 'DSCPull'     ; CerFileName = 'DscPull.cer'     ; PfxFileName = 'DscPull.pfx'      }
        )
    }

    SQLAlias   = @(
        @{ Name = 'ADMIN'   ; ServerAlias = 'SINGLE-ADM-SPSSQL' ; ServerName = 'SQL1' ; InstanceName = 'MSSQLSERVER' ; Port = 1433 }
        @{ Name = 'SEARCH'  ; … }
        @{ Name = 'SERVICES'; … }
        @{ Name = 'CONTENT' ; … }
    )

    IIS        = @{ LogFolder = 'LOGS\IIS' ; httpErrFolder = 'LOGS\HTTPERR' }
    OOS        = @{ AllServers = @('OOS') ; URL = 'oosweb.contoso.com' ; … }
    SharePoint = @{
        ProductKey                = '…'
        FarmConfigDatabaseName    = 'DSPS_Admin_Config'
        CentralAdministrationPort = '5555'
        ServiceAppPoolName        = 'SharePointServiceApplications'
        WebApplications           = @(
            @{
                Name            = 'SharePoint'
                Url             = 'https://sharepoint.contoso.com'
                HostHeader      = 'sharepoint.contoso.com'
                Port            = 443
                CertName        = 'SharePointCert'  # ← indirection into ADC.certificates / Secrets
                ContentDBName   = 'DSPS_CONTENT_MySite'
                ApplicationPool = 'PAMYSITE'
                Path            = 'C:\InetPub\…\SharePoint'
                ManagedPath     = @( @{ Name = 'Search' ; Explicit = $true ; RelativeUrl = 'search' } )
                Sites           = @(
                    @{ Name = 'MySiteHost'   ; Url = 'https://sharepoint.contoso.com'              ; Template = 'SPSMSITEHOST#0' ; Language = 1033 ; ContentDatabase = 'DSPS_CONTENT_MySite' }
                    @{ Name = 'SearchCenter' ; Url = 'https://sharepoint.contoso.com/search'       ; Template = 'SRCHCEN#0'      ; Language = 1033 ; ContentDatabase = 'DSPS_CONTENT_SearchCenter' }
                    @{ Name = 'AppsCatalog'  ; Url = 'https://sharepoint.contoso.com/sites/apps'   ; Template = 'APPCATALOG#0'   ; Language = 1033 ; ContentDatabase = 'DSPS_CONTENT_AppsCatalog' }
                )
            }
        )
        Services                  = @{
            SearchService               = @{ Name = 'SVCSearchService' ; DatabaseName = 'DSPS_SCH_SearchService' ; SearchCenterUrl = 'https://sharepoint.contoso.com/search' ; ContentSources = @{ … } }
            UserProfile                 = @{ … }
            ManagedMetadataService      = @{ … }
            AppManagementService        = @{ … }
            SubscriptionSettingsService = @{ … }
            StateService                = @{ … }
            SessionState                = @{ … }
            UsageService                = @{ … }
        }
    }
}
```

The full reference file lives at
[`scripts/sps/CfgAppSps.psd1`](https://github.com/luigilink/SPSConfigKit/blob/main/scripts/sps/CfgAppSps.psd1)
and is the canonical schema &mdash; treat the snippet above as a map.

### Key conventions

- **Cert names end in `Cert`** and match Secrets entries 1:1.
- **WebApplications carry a `CertName`** field so a friendly `Name` can be
  used in MOF identifiers while the cert lookup still resolves through
  Secrets.
- **`SourcePath`** is the SMB share that hosts every binary, language pack,
  CU, `.cer`, and `.pfx` referenced by the kit. Configure share-level read
  for the setup account on every node.
- **`Disks` is the storage source of truth** &mdash; an ordered array of
  physical data disks the node should own. Each entry declares:

  | Key                  | Required | Description                                                                                     |
  | -------------------- | -------- | ----------------------------------------------------------------------------------------------- |
  | `Id`                 | yes      | The disk **Number** as reported by `Get-Disk`. Portable across bare-metal, VMware, Hyper-V and Azure &mdash; **not** an Azure LUN. Numbers are environment-specific: a plain VM is usually `0=OS, 1=Data, 2=Logs`, but an Azure VM **with a temporary disk** shifts to `0=OS, 1=<temp>, 2=Data, 3=Logs`. Adjust to match the target node. |
  | `Letter`             | yes      | Drive letter to assign (`C`, `F`, `G`, &hellip;). Also the key used to derive `Drives`.          |
  | `Type`               | yes      | Semantic role: `OS`, `Data`, `Logs`, or `Temp`. Drives the derivation and the OS-exclusion filter. |
  | `FSLabel`            | yes      | NTFS volume label (UPPERCASE convention: `SYSTEM` / `DATA` / `LOGS` / `TEMP`).                   |
  | `AllocationUnitSize` | yes      | Cluster size (e.g. `4KB`; SQL data/log volumes use `64KB`).                                      |

  Declaring at least three disks (`SYSTEM` / `DATA` / `LOGS`) is the
  recommended baseline for every tier.
- **`Drives` is DERIVED, never hand-written** &mdash; each `Cfg*.ps1` builds
  `NonNodeData.Drives = @{ Data; Logs; Temp }` from `Disks` (keyed by `Type`)
  right after loading the psd1, so the ~30 existing `Drives.Data` / `Drives.Logs`
  consumers keep working unchanged. `Temp` falls back to the `Data` letter when
  no dedicated `Temp` disk is declared. A drive letter is therefore declared
  **once** (in `Disks`) instead of duplicated. `Drives.Data` / `Drives.Logs`
  prefix every per-node path so each farm role can point at different physical
  drives without editing the script.
- **`ManageDisks` (bool, default `$true`)** gates disk initialisation by the
  **`scripts/init/Initialize-DscDisks.ps1`** bootstrap script. Disk preparation
  is a one-time node-prep step (like joining the domain or installing the DSC
  modules), so it runs during bootstrap &mdash; **not** inside the recurring
  application MOF &mdash; and reads this same `Disks` block via `-ConfigPath`.
  When `$true`, the script onlines each raw non-`OS` disk, applies a GPT
  partition, formats NTFS with the requested `FSLabel` / `AllocationUnitSize`
  and assigns the drive letter, so a brand-new farm has its volumes before
  anything writes to them. The `OS` disk is **never** touched. Set
  `ManageDisks = $false` when the customer has already initialised and formatted
  their volumes: the script exits without touching any disk, but `Drives` is
  still derived by the configuration so every path resolves. The script is
  idempotent and **non-destructive** &mdash; a disk that already carries data is
  reported and left intact, never reformatted.
- **Per-product path overrides (optional)** &mdash; if your customer's file
  hierarchy doesn't match the kit's default
  (`<SourcePath>\SPS` &rarr; `<Drives.Data>\SoftwarePackages\SPS\{BIN,LP,CU}`
  and the same shape for OOS), override any subset of the following keys
  in `NonNodeData.SharePoint` and / or `NonNodeData.OOS` &mdash; defaults
  preserve the original layout:

  | Key                          | Purpose                                                                                  | Default                                                |
  |------------------------------|------------------------------------------------------------------------------------------|--------------------------------------------------------|
  | `SourcePath`                 | Network share holding the product's setup files.                                         | `<NonNodeData.SourcePath>\<SPS\|OOS>`                  |
  | `DestinationPath`            | Local folder the setup files are copied to.                                              | `<Drives.Data>\SoftwarePackages\<SPS\|OOS>`            |
  | `Subfolders.Binaries`        | Sub-folder of `DestinationPath` holding the main installer (`setup.exe` / prereq).       | `BIN`                                                  |
  | `Subfolders.LanguagePack`    | Sub-folder of `DestinationPath` holding per-locale Language Pack installers.             | `LP`                                                   |
  | `Subfolders.CumulativeUpdate`| Sub-folder of `DestinationPath` holding the CU package(s).                               | `CU`                                                   |

  Existing absolute values for `SharePoint.UberCumulativeUpdate` and
  `OOS.CUFileName` keep working unchanged: any rooted path is used as-is,
  otherwise the value is resolved under
  `<DestinationPath>\<Subfolders.CumulativeUpdate>`.
- **`SharePoint.LanguagePacks`** (optional) &mdash; array of SharePoint
  locale codes (e.g. `@('fr-fr','es-es')`). Each entry must match a
  sub-folder under `<DestinationPath>\<Subfolders.LanguagePack>\` that
  contains the corresponding `setup.exe`. Omit or leave as `@()` to skip
  Language Pack installation entirely.
- **`SharePoint.ManagedAccounts`** (optional) &mdash; allowlist of
  `Secrets.psd1` account names that SharePoint should register as
  `SPManagedAccount` resources on the farm master. Defaults to
  `@('FARM', 'IISAPP', 'SEARCH')`. Extend the list when you introduce a
  new dedicated SharePoint service account; leave it untouched to keep
  the historical set. Anything not in the allowlist (`PULLSETUP`,
  `IISPULLAPP`, SQL / OOS / monitoring accounts &hellip;) is intentionally
  ignored and stays out of the SPS MOF.
- **SQL Server path overrides (optional)** &mdash; `scripts/sql/CfgAppSql.psd1`
  exposes the same `SourcePath` / `DestinationPath` keys under
  `NonNodeData.SQL`. Defaults are `<NonNodeData.SourcePath>\SQL` and
  `<Drives.Data>\SoftwarePackages\SQL`. SQL doesn't use `Subfolders` &mdash;
  `setup.exe` is expected at the root of `DestinationPath`.

## Reference example `.psd1`s (PDC / PULL / SQL)

`scripts/pdc/CfgAppPdc.psd1`, `scripts/pull/CfgAppPull.psd1`, and
`scripts/sql/CfgAppSql.psd1` follow the same `AllNodes` + `NonNodeData`
pattern and are meant to be read alongside their `.ps1` counterparts.

Use them to see how the loader, the certificate import pattern, and the
manifest-driven approach work end-to-end &mdash; then **replace them with
your organisation's production AD, pull-server, and SQL provisioning**.

## `scripts/init/Initialize-SoftwarePackages.psd1`

The manifest read by `Initialize-SoftwarePackages.ps1`. It describes the
local file-share repository that backs `\\PULL\SoftwarePackages` (or
whichever SMB share every node downloads binaries from), and the list of
packages the script should fetch into it.

```powershell
@{
    # Root folder of the local SoftwarePackages repository. Every entry
    # below uses a Path RELATIVE to this root.
    Repository = 'F:\SoftwarePackages'

    SoftwarePackages = @(
        @{
            Name        = 'SharePointServerSE'
            Description = 'SharePoint Server Subscription Edition'
            FileName    = 'OfficeServer.iso'
            Url         = 'https://download.microsoft.com/.../OfficeServer.iso'
            Extract     = $true       # mount and copy ISO contents
            Path        = 'SPS\BIN'   # relative to Repository
        }
        @{
            Name        = 'KB5002773'
            Description = 'SharePoint Server SE Cumulative Update'
            FileName    = 'uber-subscription-kb5002773-fullfile-x64-glb.exe'
            Url         = 'https://download.microsoft.com/.../uber-subscription-kb5002773-fullfile-x64-glb.exe'
            Extract     = $false      # direct download to Path
            Path        = 'SPS\CU'
        }
        # …SQL Server 2022 + CU, Language Packs, .NET 4.8, VC++ 2015-2019,
        #   Office Online Server CU…
    )
}
```

### Schema

| Key           | Required | Description                                                                                                                                |
| ------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `Repository`  | yes      | Local root folder backing the SMB share. Every package `Path` is resolved against it.                                                      |
| `Name`        | yes      | Identifier used in log output.                                                                                                             |
| `Description` | yes      | Human-readable label, surfaced in the per-package banner.                                                                                  |
| `FileName`    | yes      | Source file name; for `Extract = $true` packages, this is the temp-file name in `%TEMP%` before mounting.                                  |
| `Url`         | yes      | Download URL (HTTPS).                                                                                                                      |
| `Extract`     | yes      | `$true` to mount the ISO with `Mount-DiskImage` and copy its contents into `Path`; `$false` to download the file directly to `Path`.       |
| `Path`        | yes      | Folder under `Repository` where the file or extracted contents land (e.g. `SPS\BIN`, `SQL\CU`, `SPS\LP\FR-fr`).                            |
| `Marker`      | no       | Sentinel file used to short-circuit re-extraction. Defaults to `setup.exe`, which is correct for the SQL Server, SharePoint, and LP ISOs.  |

### Idempotency

- For `Extract = $true` entries, the script skips the package when
  `<Path>\<Marker>` already exists.
- For `Extract = $false` entries, the script skips the package when
  `<Path>\<FileName>` already exists.
- Downloaded ISOs cached in `%TEMP%` are reused when a previous run was
  interrupted between download and extraction.

### Why no 7-Zip?

ISO expansion uses Windows' built-in `Mount-DiskImage` /
`Copy-Item -Recurse` / `Dismount-DiskImage` pipeline, so the file-share
host has **zero external dependencies** beyond Windows itself. Required
capability: Windows 8 / Server 2012 or newer (for `Mount-DiskImage`).

> [!NOTE]
> The script also detects outbound internet access once at startup and
> skips the download phase entirely on offline hosts. Per-package failures
> are caught and logged so one bad URL does not abort the whole run.

## Validating your ConfigurationData

Before compiling any MOF, run the bundled Pester v5 pre-flight suite
against your `.psd1` files. It catches the mistakes that would otherwise
surface mid-run on the customer site &mdash; placeholder product key,
duplicate `NodeName`, missing `Secrets.psd1` entry for a managed account,
mismatched `CertName` &harr; `ADC.certificates`, malformed Language Pack
locale, unreachable `\\share\setup.exe`, missing `.pfx` &hellip;

```powershell
# Full validation (workstation must have the install share mounted).
.\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sps\CfgAppSps.psd1

# Structure-only (skip every Test-Path on the install share / certificates).
.\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sql\CfgAppSql.psd1 -SkipFilesystem
```

The driver exits with code `1` on the first failure, so it can be wired
into CI or used as a hard gate before `Start-DscConfiguration`:

```powershell
.\scripts\test\Invoke-ConfigDataTest.ps1 -ConfigPath .\scripts\sps\CfgAppSps.psd1
if ($LASTEXITCODE -ne 0) { throw 'Config invalid — refusing to compile MOFs.' }
```

### What the suite checks

Every check is read-only. Sections that don't apply to the file under test
are skipped automatically (e.g. SharePoint checks are not run against
`CfgAppSql.psd1`).

- **File integrity** &mdash; `Import-PowerShellDataFile` succeeds;
  `AllNodes` / `NonNodeData` present; the wildcard `*` node declares
  `PSDscAllowPlainTextPassword` / `PSDscAllowDomainUser`.
- **AllNodes** &mdash; `NodeName` values unique; exactly one `IsMaster`
  per role family (SPS, OOS); at least one `IsSPSServer` / `IsOOSServer`
  / `IsSQLServer` when the matching `NonNodeData` section is present.
- **Disks &amp; Drives** &mdash; `NonNodeData.Disks` is present and each entry
  has `Id` / `Letter` / `Type` / `FSLabel` / `AllocationUnitSize`; disk `Id`s
  and `Letter`s are unique; exactly one `OS` disk; the `SYSTEM` / `DATA` /
  `LOGS` roles are declared. The `Drives.Data` / `Drives.Logs` values derived
  from `Disks` match `^[A-Z]:$`.
- **`SourcePath`** &mdash; `NonNodeData.SourcePath` is a UNC or rooted local
  path.
- **Product key** &mdash; `SharePoint.ProductKey` matches
  `XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` **and** is not the placeholder
  `XXXXX-...`.
- **Ports** &mdash; `CentralAdministrationPort` and `SQLAlias[*].Port`
  are valid integers in `1..65535`.
- **Certificates** &mdash; `ADC.certificates[*].Name` unique; every cert
  has a matching `Secrets.psd1` entry (drives the PFX password);
  `WebApplications[*].CertName` resolves to a known cert `Name`;
  `OOS.CertFriendlyName` resolves to a known `FriendlyName`.
- **Managed accounts** &mdash; `SharePoint.ManagedAccounts` (or the
  default `@('FARM','IISAPP','SEARCH')` when omitted) is a subset of
  `Secrets.psd1`.
- **Language packs** &mdash; each `SharePoint.LanguagePacks` entry
  matches `xx-xx`.
- **Filesystem reachability** *(skipped by `-SkipFilesystem`)* &mdash;
  `SourcePath`, `BIN\setup.exe`, `LP\<locale>\setup.exe`, and the CU
  package for both SPS and OOS; SQL `SourcePath\setup.exe`; every
  `ADC.certificates[*].CertPath` / `PfxPath`.

Filesystem checks reuse the exact same `Resolve-ProductPaths` resolution
as `CfgAppSps.ps1`, so the per-product `SourcePath` / `Subfolders`
overrides documented above are validated against the same paths the MOF
will compile with.

### Reading the output

Pester v5 prefixes each `It` line with a status glyph, and the wrapper
adds a one-line summary that *also* surfaces the number of skipped tests
so a clean run never looks misleadingly green:

| Glyph | Meaning |
| --- | --- |
| `[+]` | Passed |
| `[-]` | **Failed** &mdash; fix before compiling MOFs |
| `[!]` | **Skipped** &mdash; the section / context didn't apply (e.g. SPS checks against `CfgAppSql.psd1`, or filesystem checks under `-SkipFilesystem`). **Not a failure.** |

```text
Tests Passed: 59, Failed: 0, Skipped: 3, Inconclusive: 0, NotRun: 0

59 of 62 test(s) passed; 3 skipped (sections not present in this config
or filesystem checks disabled). ConfigurationData looks healthy.
```

A run with `Failed: 0` is healthy regardless of the skipped count;
sections gate themselves off when the relevant `NonNodeData` sub-tree is
missing. The wrapper still returns exit code `0` so CI / pre-MOF gates
work the same way.

### Prerequisite

The suite requires **Pester 5.0.0 or later** on the authoring host
(Windows PowerShell 5.1 ships with Pester 3.x by default):

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

No other module is needed; the test files use only built-in cmdlets and
Pester v5.

## Next step

Continue with the [Usage](./Usage) page.
