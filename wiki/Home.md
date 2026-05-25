# SPSConfigKit

**SPSConfigKit** is a PowerShell Desired State Configuration (DSC) toolkit for
installing and configuring a **SharePoint Server Subscription Edition** farm
end-to-end &mdash; binaries, language packs, cumulative updates, service
applications, web applications, the search topology, and the co-located
Office Online Server farm used for in-browser document rendering.

The deliverable of the kit is a single compiled MOF file per node that
SharePoint administrators can push (or have an LCM pull) onto every server in
the farm to bring it to a known, reproducible state.

## Scope

| Script                          | Purpose                                          | Intended use      |
| ------------------------------- | ------------------------------------------------ | ----------------- |
| `scripts/sps/CfgAppSps.ps1`     | SharePoint Server SE farm + Office Online Server | **Production**    |
| `scripts/init/Initialize-DscNode.ps1` | Node bootstrap (modules, certificate, packages) | **Production**    |
| `scripts/init/Initialize-DscEncryption.ps1` | DSC document-encryption certificate generator | **Production**    |
| `scripts/pdc/CfgAppPdc.ps1`     | Sample primary domain controller + AD CS         | _Reference only_  |
| `scripts/pull/CfgAppPull.ps1`   | Sample DSC pull server                           | _Reference only_  |
| `scripts/sql/CfgAppSql.ps1`     | Sample SQL Server instance for the farm DBs      | _Reference only_  |

> [!IMPORTANT]
> **PDC, PULL and SQL scripts ship as examples** so the sample lab environment
> is self-contained and reproducible. They are **not** hardened for production
> deployment. Replace them with your organisation's own AD, pull-server, and
> SQL provisioning (Group Policy, ARM, Terraform, dbatools, etc.) before
> using the kit on a real farm.

## Key Features

- **Single source of truth** &mdash; node prerequisites (Chocolatey packages,
  pinned DSC module versions, document-encryption certificate) live in
  `scripts/init/Initialize-DscNode.psd1` and are reused by every
  configuration script.
- **Pinned DSC modules** &mdash; every `Import-DscResource` line locks to an
  exact version, so a node bootstrapped today produces the same MOFs as a
  node bootstrapped six months from now.
- **Encrypted MOFs by default** &mdash; credentials are encrypted by a DSC
  document-encryption certificate, and the LCM is configured to decrypt them
  on the node.
- **Centralised, opt-in secrets** &mdash; `scripts/Secrets.psd1` is the only
  place credentials live. AD service accounts and non-AD containers (PFX
  passwords, DSRM password, farm passphrase) share the same schema, with an
  `IsAdAccount` flag controlling auto-materialisation as `PSCredential`s.
- **Per-certificate PFX passwords** &mdash; each certificate is imported with
  its own password resolved by name from `Secrets.psd1`, removing shared-key
  exposure.

## Documentation

- [Getting Started](./Getting-Started) &mdash; prerequisites, dependencies,
  node bootstrap workflow.
- [Configuration](./Configuration) &mdash; the `.psd1` schema, the
  `Secrets.psd1` schema, and how the two are stitched together at compile
  time.
- [Usage](./Usage) &mdash; compiling the MOFs, applying them with
  `Start-DscConfiguration` (push) or registering an LCM (pull), and
  day-to-day operations.

## Change log

The full history of changes is tracked in
[CHANGELOG.md](https://github.com/luigilink/SPSConfigKit/blob/main/CHANGELOG.md).
