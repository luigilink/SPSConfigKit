# SPSConfigKit - Release Notes

## [1.6.0] - 2026-07-07

### Changed

- Office Online Server integration is skipped when no OOS node is declared (#37)
  - On the SharePoint master, the OOS trusted root authority (`SPTrustedRootAuthority`
    for the Office Online CA certificate), the WOPI binding
    (`SPOfficeOnlineServerBinding`) and the PDF suppression settings
    (`SPOfficeOnlineServerSupressionSettings`) were provisioned unconditionally.
    On a farm that declares no `IsOOSServer` node this referenced
    `NonNodeData.OOS` / the `OfficeOnlineCert` that such a farm may legitimately
    omit, and pushed a WOPI binding for a server that does not exist. The three
    resources are now gated on the presence of at least one `IsOOSServer` node,
    mirroring the gating already applied to the OOS install Node block.

### Fixed

- `NonNodeData.OOS.AllServers` is validated against the declared OOS nodes (#38)
  - `AllServers` feeds the `Servers` list of the OOS cumulative update
    (`OfficeOnlineServerProductUpdate`). When it did not list every node carrying
    the `IsOOSServer` role, the CU was applied to an incomplete set of machines
    while the farm still reported those nodes (the shipped sample even drifted,
    with `AllServers = @('OOS')` while the node is `OOS1`). `CfgAppSps.ps1` now
    throws at compile time when any `IsOOSServer` NodeName is missing from
    `AllServers` (only when the farm declares an OOS node), a matching Pester
    assertion covers the invariant, and the sample `AllServers` is corrected to
    `@('OOS1')`.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
