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
| `Microsoft.Windows/WindowsPowerShell` | **Windows PowerShell 5.1** | `SharePointDsc`, `SqlServerDsc`, `ActiveDirectoryDsc` and every other MOF/class-based PSDSC resource this kit already pins |
| `Microsoft.DSC/PowerShell` | PowerShell 7 | PS7 **class-based** resources only |

> **Adapter naming (as of DSC 3.2.2):** `dsc.exe` prints a deprecation warning
> steering you toward `Microsoft.Adapters/WindowsPowerShell` /
> `Microsoft.Adapters/PowerShell`, **but those renamed adapters are not shipped in
> 3.2.2** — using them fails with `Resource not found: Microsoft.Adapters/WindowsPowerShell`.
> Until a build ships them, use the working (deprecated) names above.

> **SharePointDsc requires the `Microsoft.Windows/WindowsPowerShell` adapter.**
> It is a class/MOF-based module that only loads under Windows PowerShell 5.1, so the
> PowerShell 7 adapter reports `SharePointDsc/SPInstall module not found` (PS7
> cannot see the 5.1 module path).

### Known blocker — SharePointDsc + the Windows PowerShell adapter cache refresh

SharePointDsc 5.x is **class-based**, and the Windows PowerShell adapter runs a
**global cache refresh** that loads and instantiates *every* installed PSDSC
resource class to enumerate it — not only the ones referenced in the document.
Loading a SharePointDsc class triggers a **SharePoint snap-in import**, which only
succeeds on a host where SharePoint Server is actually installed. On a bare
authoring host, `dsc config get/test/set` therefore fails during the cache refresh
with:

```
Import-SPPowerShellSnapIn ... is not recognized as the name of a cmdlet ...
    at Invoke-DscCacheRefresh, win_psDscAdapter.psm1
```

Two consequences, confirmed on a fresh farm node (SharePointDsc installed by
`Initialize-DscNode`, SharePoint not yet applied):

1. The `sps.dsc.config.yaml` document cannot be planned/read on a host without
   SharePoint installed — unlike the v1/v2 line, where **MOF compilation only reads
   the resource schema** and works fine on a bare authoring host.
2. Because the refresh is **global**, *any* document routed through the Windows
   PowerShell adapter fails on such a host as soon as SharePointDsc is present —
   including the benign `smoke.dsc.config.yaml` below.

**Where this leaves the v3 line:** driving SharePointDsc through the DSC v3 Windows
PowerShell adapter is only viable on a node that already has SharePoint installed,
which breaks the "author/plan on a clean host" workflow the v1/v2 line supports.
This looks like an upstream limitation worth reporting to the
[PowerShell/DSC](https://github.com/PowerShell/DSC) and/or
[SharePointDsc](https://github.com/dsccommunity/SharePointDsc) projects (the
adapter should tolerate a resource that fails to load; the resource should not
import the SharePoint snap-in at class-load time). Tracked as a v3-line open
question.

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
