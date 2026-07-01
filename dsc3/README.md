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
(`SharePointDsc`, `SqlServerDsc`, `ActiveDirectoryDsc`, …) through a **PowerShell
adapter**. Two adapters exist, and picking the right one matters:

| Adapter | Hosts resources in | Use for |
| --- | --- | --- |
| `Microsoft.Adapters/WindowsPowerShell` | **Windows PowerShell 5.1** | `SharePointDsc`, `SqlServerDsc`, `ActiveDirectoryDsc` and every other MOF/class-based PSDSC resource this kit already pins |
| `Microsoft.Adapters/PowerShell` | PowerShell 7 | PS7 **class-based** resources only |

> The older adapter names `Microsoft.DSC/PowerShell` and
> `Microsoft.Windows/WindowsPowerShell` still work but are deprecated in DSC 3.2+;
> prefer the `Microsoft.Adapters/*` names above.

> **SharePointDsc requires the `Microsoft.Adapters/WindowsPowerShell` adapter.**
> It is a class/MOF-based module that only loads under Windows PowerShell 5.1, so the
> PowerShell 7 adapter reports `SharePointDsc/SPInstall module not found` (PS7
> cannot see the 5.1 module path). Reusing the adapter lets the v3 line keep the
> same resource logic as the v1/v2 line, so the effort concentrates on the
> **orchestration layer** (the configuration documents) rather than rewriting
> every resource.

### Known constraint — SharePointDsc needs SharePoint present to load

SharePointDsc 5.x is **class-based**. The Windows PowerShell adapter loads and
instantiates the resource class to enumerate it during its cache refresh, and
loading the class triggers a **SharePoint snap-in import**. That import only
succeeds on a host where SharePoint Server is actually installed, so on a bare
authoring host `dsc config get/test/set` fails during the cache refresh with:

```
Import-SPPowerShellSnapIn ... is not recognized as the name of a cmdlet ...
```

This is a genuine difference from the v1/v2 line: **MOF compilation only reads the
resource schema** (works without SharePoint), whereas the **DSC v3 adapter actually
loads the resource** (needs SharePoint present). Run the SharePoint document on a
node that already has the SharePoint binaries installed. To validate the
`dsc.exe → adapter` pipeline itself on a bare host, use the benign smoke-test
document below.

Reference: <https://learn.microsoft.com/en-us/powershell/dsc/>

## Layout

```
dsc3/
├── README.md                 # this file
├── configurations/           # DSC v3 configuration documents (YAML/JSON)
│   ├── sps.dsc.config.yaml    # sample SharePoint SE farm document (starter)
│   └── smoke.dsc.config.yaml  # benign adapter smoke test (no SharePoint required)
└── resources/                # custom resource manifests (as the line grows)
```

## Prerequisites (authoring / target host)

- **DSC v3** (`dsc.exe`) — install from <https://github.com/PowerShell/DSC/releases>
  (on Windows Server, use the `DSC-<ver>-x86_64-pc-windows-msvc.zip` asset).
- **Windows PowerShell 5.1** — required by the `Microsoft.Windows/WindowsPowerShell`
  adapter that hosts SharePointDsc. (`dsc.exe` itself also works with PowerShell 7.4+
  for the class-based adapter, but SharePointDsc runs under 5.1.)
- The same pinned PSDSC modules used by the v1/v2 line, installed in the Windows
  PowerShell 5.1 module path (see
  [`../scripts/init/Initialize-DscNode.psd1`](../scripts/init/Initialize-DscNode.psd1)).

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
