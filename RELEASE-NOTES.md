# SPSConfigKit - Release Notes

## [1.4.0] - 2026-07-06

### Added

- Automatic data-disk initialisation during node bootstrap (#15)
  - New `scripts/init/Initialize-DscDisks.ps1` prepares a node's data disks from
    the same `NonNodeData.Disks` block the configuration uses (read via
    `-ConfigPath`). It onlines each raw non-`OS` disk, applies a GPT partition,
    NTFS-formats it with the requested `FSLabel` / `AllocationUnitSize` and
    assigns the drive letter — so a brand-new farm has its volumes before
    anything writes to them, with no manual `Get-Disk` / `Format-Volume` step.
    Disk preparation is a one-time node-prep action, so it runs during bootstrap
    (like the domain join and module install) rather than inside the recurring
    application MOF. The script uses native Windows Storage cmdlets (no extra DSC
    module), is idempotent, and is **non-destructive** — a disk already carrying
    data is reported and left intact, never reformatted.
  - Every configuration (`CfgAppSql` / `CfgAppSps` / `CfgAppPdc` / `CfgAppPull`)
    declares its physical disks in a new authoritative `NonNodeData.Disks` array
    (`Id` / `Letter` / `Type` / `FSLabel` / `AllocationUnitSize`). Disks are keyed
    by disk **Number** (`Get-Disk`), portable across bare-metal, VMware, Hyper-V
    and Azure — not an Azure LUN. The `OS` disk (`Type = 'OS'`) is never touched.
  - New `NonNodeData.ManageDisks` boolean (default `$true`). Set it to `$false`
    when the customer manages their own storage: `Initialize-DscDisks.ps1` then
    does nothing, but the derived `Drives` hashtable is still produced so every
    path resolves.

### Changed

- `NonNodeData.Drives` is now DERIVED, not hand-written (#15)
  - Each `Cfg*.ps1` builds `NonNodeData.Drives = @{ Data; Logs; Temp }` from the
    new `Disks` array (keyed by `Type`) immediately after loading the psd1, so a
    drive letter is declared exactly once (in `Disks`) instead of duplicated.
    All existing `Drives.Data` / `Drives.Logs` / `Drives.Temp` consumers keep
    working unchanged; `Temp` falls back to the `Data` letter when no dedicated
    `Temp` disk is declared. FSLabels follow an UPPERCASE convention
    (`SYSTEM` / `DATA` / `LOGS` / `TEMP`), and every tier declares at least the
    three baseline disks. SQL `DATA` / `LOGS` volumes use a `64KB` allocation
    unit size per SQL Server best practice.
  - `ConfigData.Tests.ps1` derives `Drives` from `Disks` the same way and adds a
    `NonNodeData Disks` check block (required per-disk keys, one `OS` disk,
    unique `Id`s and `Letter`s, `SYSTEM` / `DATA` / `LOGS` present).

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
