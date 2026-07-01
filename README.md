# SPSConfigKit

![Latest release date](https://img.shields.io/github/release-date/luigilink/SPSConfigKit.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/SPSConfigKit/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/SPSConfigKit.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## Description

SPSConfigKit is a PowerShell script tool designed to install and configure a SharePoint Farm with PowerShell Desired Configuration.

[Download the latest release, Click here!](https://github.com/luigilink/SPSConfigKit/releases/latest)

## Requirements

### Windows Management Framework 5.0

Required because this module now implements class-based resources.
Class-based resources can only work on computers with Windows rManagement Framework 5.0 or above.
The preferred version is PowerShell 5.1 or higher, which ships with Windows 10 or Windows Server 2016.
This is discussed further on the [SPSConfigKit Wiki Getting-Started](https://github.com/luigilink/SPSConfigKit/wiki/Getting-Started)

## Modules DSC

This is the list of DSC Modules required for this kit:

- ActiveDirectoryDsc
- ActiveDirectoryCSDsc
- CertificateDsc
- ComputerManagementDsc
- OfficeOnlineServerDsc
- NetworkingDsc
- PSDscResources
- SharePointDsc
- SqlServerDsc
- WebAdministrationDsc
- xCredSSP
- xPSDesiredStateConfiguration

You can find documention for each module on the repository [dsccommunity](https://github.com/dsccommunity)

## Security — credentials are encrypted, plain-text is not supported

SPSConfigKit compiles credentials (service accounts, farm passphrase, PFX
passwords) into the MOF for every node. **These MUST be encrypted with a DSC
document-encryption certificate — compiling them in clear text is not a supported
configuration.** A MOF with clear-text passwords is a credential-theft primitive:
anyone who can read the file on the authoring host, the pull server, or the SMB
share gets domain service-account passwords.

The kit ships everything needed and the workflow makes it mandatory:

1. **Generate the certificate** with `scripts/init/Initialize-DscEncryption.ps1`.
   It exports the `.cer` / `.pfx` to the share and **patches every `Cfg*.psd1`**
   so the wildcard node carries `PSDscAllowPlainTextPassword = $false` plus the
   `CertificateFile` / `Thumbprint` pointing at the encryption cert.
2. **Import the `.pfx`** into `Cert:\LocalMachine\My` on every target node
   (handled by `scripts/init/Initialize-DscNode.ps1`).
3. **Compile** — the resulting MOFs carry CMS-encrypted credential blobs and a
   `ContentType="PasswordEncrypted"` marker, decryptable only by the node holding
   the private key.
4. **Verify** with the post-compile guard-rail, which fails if any credential
   slipped through in clear text:

   ```powershell
   .\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF
   ```

See the [Securing Credentials](https://github.com/luigilink/SPSConfigKit/wiki/Securing-Credentials)
wiki page for the full walkthrough, certificate rotation, and troubleshooting.

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSConfigKit Wiki](https://github.com/luigilink/SPSConfigKit/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
