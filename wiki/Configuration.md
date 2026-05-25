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
│   ├── Initialize-DscNode.psd1     ← prerequisite manifest (modules, certs)
│   ├── Initialize-DscNode.ps1
│   └── Initialize-DscEncryption.ps1
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
    SourcePath = '\\PDC1\Softwarepackages'    # binaries + .cer/.pfx share
    DomainName = 'contoso.com'
    Drives     = @{ Data = 'F:'; Logs = 'G:' }

    ADC        = @{
        certificates = @(
            @{ Name = 'SharePointCert'    ; FriendlyName = 'SharePoint'  ; CertPath = '\\PDC1\…\SharePoint.cer'  ; PfxPath = '\\PDC1\…\SharePoint.pfx'  }
            @{ Name = 'OfficeOnlineCert'  ; FriendlyName = 'OOSCertSSL'  ; CertPath = '\\PDC1\…\OfficeOnline.cer'; PfxPath = '\\PDC1\…\OfficeOnline.pfx' }
            @{ Name = 'SQLServerCert'     ; FriendlyName = 'SQLCertSSL'  ; CertPath = '\\PDC1\…\SQLServer.cer'   ; PfxPath = '\\PDC1\…\SQLServer.pfx'    }
            @{ Name = 'DscPullCert'       ; FriendlyName = 'DSCPull'     ; CertPath = '\\PDC1\…\DscPull.cer'     ; PfxPath = '\\PDC1\…\DscPull.pfx'      }
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
- **`Drives.Data` / `Drives.Logs`** prefix every per-node path so each
  farm role can point at different physical drives without editing the
  script.

## Reference example `.psd1`s (PDC / PULL / SQL)

`scripts/pdc/CfgAppPdc.psd1`, `scripts/pull/CfgAppPull.psd1`, and
`scripts/sql/CfgAppSql.psd1` follow the same `AllNodes` + `NonNodeData`
pattern and are meant to be read alongside their `.ps1` counterparts.

Use them to see how the loader, the certificate import pattern, and the
manifest-driven approach work end-to-end &mdash; then **replace them with
your organisation's production AD, pull-server, and SQL provisioning**.

## Next step

Continue with the [Usage](./Usage) page.
