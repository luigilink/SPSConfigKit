# SPSConfigKit - Release Notes

## [1.7.3] - 2026-08-31

### Changed

- The Edge `AuthServerAllowlist` registry key is now optional and opt-in (#55)
  - `CfgAppSps` used to write the Microsoft Edge Integrated Windows Auth policy
    `HKLM\SOFTWARE\Policies\Microsoft\Edge\AuthServerAllowlist` unconditionally on every
    SharePoint node, with a hardcoded `*app1*` host pattern. This is a browser policy normally
    owned centrally by GPO / Intune. It is now driven by an optional
    `NonNodeData.SharePoint.EdgeAuthAllowlist` block: omitted by default (not emitted, so
    GPO/Intune stays authoritative), written only when `Enabled = $true`. Host patterns come
    from the optional `Hosts` list and default to `*<DomainName>*`; the value is written with
    `Force` so it overwrites an existing (e.g. GPO-set) value.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
