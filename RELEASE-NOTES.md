# SPSConfigKit - Release Notes

## [1.6.1] - 2026-07-08

### Fixed

- CfgAppSql no longer sets an invalid `RestartService` property on the SQL protocol
  resources (#40)
  - The `SqlProtocol` (`MIDDLEWARE_SqlProtocolTcpEnabled`) and `SqlProtocolTcpIP`
    (`MIDDLEWARE_SqlProtocolTcpIP`) resources set `RestartService = $true`, which is not a
    valid property in SqlServerDsc 17.5.1 — the DSC parser rejects it and MOF compilation
    fails. Both resources expose `SuppressRestart` (default `$false`) and `RestartTimeout`
    instead. The property is removed; the default `SuppressRestart = $false` already
    restarts the service when a protocol change requires it, so TCP/IP enablement still
    takes effect.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
