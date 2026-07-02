# SPSConfigKit - Release Notes

## [1.2.2] - 2026-07-02

### Fixed

- LCM decryption certificate (`CertificateID`)
  - Since 1.2.0 made MOF encryption mandatory, every node's MOF carries encrypted
    credentials, but no LCM configuration told the LCM which certificate to
    decrypt them with. `Start-DscConfiguration` / `Test-DscConfiguration` failed
    on the first resource with *"The Local Configuration Manager is not configured
    with a certificate"*. `CfgAppSql.ps1`, `CfgAppSps.ps1` and `CfgAppPdc.ps1` now
    set `LocalConfigurationManager.CertificateID = $Node.Thumbprint`, and
    `CfgLcmPull.ps1` sets `Settings.CertificateID` (resolved from the local
    `CN=DSC Encryption` certificate or the new `-CertificateThumbprint`).
- Share-copy credential harmonised on `$SETUP`
  - The `File` resources that copy binaries from the SoftwarePackages share used
    three different accounts (`$PULLSETUP` in SQL, `$ADSETUP` for the SharePoint
    and OOS copies). They now all use `$SETUP` (svcspssetup), so a single account
    needs Read on the share. Genuine Active Directory operations keep `$ADSETUP`.
- `Initialize-DscEncryption.ps1` certificate drift
  - The script always re-exported the public `.cer` but only exported the private
    `.pfx` when `-PfxPassword` was supplied, so rotating without it left a stale
    `.pfx` and nodes failed with *"Decryption failed"*. `-Force` now requires
    `-PfxPassword`, and the script verifies the `.cer`, the `.pfx` and the active
    certificate all share one thumbprint.

### Added

- `Initialize-DscNode.ps1` hardening
  - Post-import validation that the certificate installed in the node's store
    matches the share's `.cer` thumbprint (and has its private key), flagging the
    mismatch that otherwise surfaces later as *"Decryption failed"*.
  - `-PullMode` / `-SkipModules` switches to skip the local `Install-Module` phase
    (in Pull mode the pull server serves the modules as `.zip` packages).
  - `-ShareAccessCredential` to verify the share-copy account can actually read
    the SoftwarePackages share before the DSC apply does.
- `CfgLcmPull.ps1`: `-CertificateThumbprint` / `-CertificateSubject` parameters to
  control the LCM decryption certificate lookup.

### Changed

- Wiki (`Securing-Credentials`, `Usage`, `Getting-Started`)
  - Document that the LCM `CertificateID` must be set (apply the `*.meta.mof` with
    `Set-DscLocalConfigurationManager` before pushing), the `-Force`/`-PfxPassword`
    rotation guard-rail, hosting the SoftwarePackages share on a member server
    (not a domain controller) with `svcspssetup` Read, and running
    `Initialize-DscEncryption.ps1` on the authority host only. New troubleshooting
    rows for *"LCM is not configured with a certificate"* and *"Decryption failed"*.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
