# SPSConfigKit — DSC v3 line (experimental)

> ⚠️ **Experimental / work in progress.** This folder hosts the **DSC v3** implementation of
> SPSConfigKit. It is published on a **separate release channel** (`dsc3-v*` tags, marked as
> GitHub *pre-releases*) and does **not** affect the stable PowerShell DSC v1/v2 line under
> [`../scripts`](../scripts). See the compatibility matrix in the [root README](../README.md).

## Why a separate line?

Microsoft's **DSC v3** (`dsc.exe`) is a ground-up rewrite, not a version bump of PowerShell DSC
v1/v2:

| | PowerShell DSC v1/v2 (`scripts/`) | DSC v3 (`dsc3/`) |
| --- | --- | --- |
| Authoring | `Configuration { }` keyword | YAML / JSON configuration documents |
| Artifact | Compiled **MOF** | No MOF — the document *is* the desired state |
| Engine | Local Configuration Manager (LCM) | `dsc.exe` (cross-platform binary) |
| Distribution | DSC pull server (`xDscWebService`) | Any transport (files, Git, packaging) |
| Resources | Class/MOF-based PowerShell modules | Resource **manifests** (any executable) + adapters |

Because the model is fundamentally different, the two lines live side by side rather than
one replacing the other.

## Reusing existing PSDSC resources

DSC v3 can drive the existing class/MOF-based PowerShell resources
(`SharePointDsc`, `SqlServerDsc`, `ActiveDirectoryDsc`, …) through the built-in
**`Microsoft.DSC/PowerShell`** adapter. This lets the v3 line reuse the same resource logic the
v1/v2 line relies on, so the effort concentrates on the **orchestration layer** (the
configuration documents) rather than rewriting every resource.

Reference: <https://learn.microsoft.com/en-us/powershell/dsc/>

## Layout

```
dsc3/
├── README.md                 # this file
├── configurations/           # DSC v3 configuration documents (YAML/JSON)
│   └── sps.dsc.config.yaml    # sample SharePoint SE farm document (starter)
└── resources/                # custom resource manifests (as the line grows)
```

## Prerequisites (authoring / target host)

- **DSC v3** (`dsc.exe`) — install from <https://github.com/PowerShell/DSC/releases>
- **PowerShell 7.4+**
- For the `Microsoft.DSC/PowerShell` adapter: the same pinned PSDSC modules used by the
  v1/v2 line (see [`../scripts/init/Initialize-DscNode.psd1`](../scripts/init/Initialize-DscNode.psd1)).

## Quick start (once a configuration document exists)

```bash
# Validate the configuration document against the DSC v3 schema
dsc config get   --file dsc3/configurations/sps.dsc.config.yaml

# Preview what would change (what-if)
dsc config test  --file dsc3/configurations/sps.dsc.config.yaml

# Apply the desired state
dsc config set   --file dsc3/configurations/sps.dsc.config.yaml
```

## Status

- [ ] Configuration document schema settled
- [ ] SharePoint SE install/config via the PowerShell adapter
- [ ] SQL / AD reference documents
- [ ] Parity checklist with the v1/v2 line
- [ ] First `dsc3-v0.1.0` pre-release
