# SPSConfigKit - Release Notes

## [1.7.0] - 2026-07-08

### Added

- SQL Server connection encryption (TLS) (#27, #42)
  - `CfgAppSql` can now force TLS encryption of SQL Server connections, opt-in via
    `NonNodeData.SQL.ForceEncryption` (secure-by-default in the sample). It imports the
    pre-staged SQL certificate (`CertificateName`, default `SQLServerCert`) into
    `LocalMachine\My` with `PfxImport` and binds it to the instance with
    `SqlSecureConnection` (`ForceEncryption`, `ServiceAccount`). `CfgAppSps` imports the
    SQL certificate's public `.cer` into `LocalMachine\Root` on every SharePoint node so
    it trusts the SQL TLS chain, and drives the `SPFarm` `DatabaseConnectionEncryption`
    from `NonNodeData.SQL.DatabaseConnectionEncryption`.
  - The default level is `Optional` (traffic is encrypted because the SQL tier forces it;
    robust with the kit's SQL aliases and applies on both new and existing farms).
    `Mandatory` / `Strict` additionally validate the certificate chain and host name and
    require `NonNodeData.SQL.DatabaseServerCertificateHostName` to be set to a name in the
    SQL certificate SAN (the SQL alias never matches it). Note that
    `DatabaseConnectionEncryption` is honoured only when the configuration database is
    first created / joined — SPFarm does not change it on an already-joined farm.
- SQL maintenance plan — Ola Hallengren Maintenance Solution (#31)
  - `CfgAppSql` can install the [SQL Server Maintenance Solution](https://ola.hallengren.com)
    (backups, index maintenance, integrity checks), opt-in via
    `NonNodeData.SQL.InstallMaintenanceSolution`. `Initialize-SoftwarePackages` downloads
    `MaintenanceSolution.sql` into the SQL source folder, so it is staged to the node with
    the rest of the SQL media (no runtime download on offline nodes). A `SqlScript`
    resource runs it under the SQL sysadmin RunAs and is idempotent (skipped once the
    `CommandExecute` procedure exists). The script is not bundled with the kit;
    `scripts/sql/README.md` documents the feature, the tunable `DECLARE` parameters, and
    credits Ola Hallengren. Job schedules are intentionally left to the SQL administrator.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
