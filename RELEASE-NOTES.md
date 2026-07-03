# SPSConfigKit - Release Notes

## [1.4.0] - 2026-07-03

### Added

- Automatic data-disk initialisation on first boot (#15)
  - Every configuration (`CfgAppSql` / `CfgAppSps` / `CfgAppPdc` / `CfgAppPull`)
    now declares its physical disks in a new authoritative `NonNodeData.Disks`
    array (`Id` / `Letter` / `Type` / `FSLabel` / `AllocationUnitSize`) and emits
    StorageDsc `WaitForDisk` + `Disk` resources so a brand-new farm onlines,
    GPT-partitions, NTFS-formats and letters its raw data disks automatically —
    no manual `Get-Disk` / `Format-Volume` step before the first apply. Disks are
    keyed by disk **Number** (StorageDsc's default `DiskIdType`), portable across
    bare-metal, VMware, Hyper-V and Azure — not an Azure LUN. The `OS` disk
    (`Type = 'OS'`) is never touched.
  - `StorageDsc` `6.0.1` is pinned in `scripts/init/Initialize-DscNode.psd1` (so
    `Initialize-DscNode.ps1` installs it and `Publish-SPSPullModules.ps1` stages
    it on the pull server) and imported by each `Cfg*.ps1`.
  - New `NonNodeData.ManageDisks` boolean (default `$true`) gates the disk
    resources. Set it to `$false` when the customer manages their own storage:
    the `WaitForDisk` / `Disk` resources are skipped, but the derived `Drives`
    hashtable is still produced so every path resolves. `AllowDestructive` stays
    at its safe default (`$false`), so an already-correct disk is left intact.

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
