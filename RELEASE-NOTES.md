# SPSConfigKit - Release Notes

## [1.7.1] - 2026-08-31

### Fixed

- `SPFarm` no longer fails MOF compilation with an empty
  `DatabaseServerCertificateHostName` (#51)
  - When `NonNodeData.SQL.DatabaseConnectionEncryption` was `Optional` (the default) and no
    `NonNodeData.SQL.DatabaseServerCertificateHostName` was configured, `CfgAppSps` passed the
    resolved empty string to the `SPFarm` resource. SharePointDsc's `MSFT_SPFarm` decorates
    `DatabaseServerCertificateHostName` with `[ValidateNotNullOrEmpty()]`, so compilation
    failed with *"Cannot validate argument on parameter 'DatabaseServerCertificateHostName'
    because it is an empty string"* — even though the parameter is not needed at the
    `Optional` level. Both `SPFarm` blocks (`APPLICATION_SpsCreateSPFarm` and
    `APPLICATION_SpsJoinSPFarm`) now build their properties via splatting and add
    `DatabaseServerCertificateHostName` only when a host name is configured. The
    `Mandatory` / `Strict` fail-fast (which still requires the host name) is unchanged.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
