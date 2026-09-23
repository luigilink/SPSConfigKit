# SPSConfigKit

![Latest release](https://img.shields.io/github/v/release/luigilink/SPSConfigKit.svg?style=flat)
![Latest release date](https://img.shields.io/github/release-date/luigilink/SPSConfigKit.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/SPSConfigKit/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/SPSConfigKit.svg?style=flat)
![Last commit](https://img.shields.io/github/last-commit/luigilink/SPSConfigKit.svg?style=flat)
![License](https://img.shields.io/github/license/luigilink/SPSConfigKit.svg?style=flat)  
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## Description

SPSConfigKit is a PowerShell script tool designed to install and configure a SharePoint Farm with PowerShell Desired Configuration.

[Download the latest release, Click here!](https://github.com/luigilink/SPSConfigKit/releases/latest)

## Requirements

- Windows PowerShell 5.1 or later (ships with Windows Server 2016 and above).
- A set of DSC modules (ActiveDirectoryDsc, SharePointDsc, SqlServerDsc,
  OfficeOnlineServerDsc, CertificateDsc, xCredSSP, …). The full list with pinned
  versions is on the
  [Getting Started](https://github.com/luigilink/SPSConfigKit/wiki/Getting-Started#required-dsc-modules)
  wiki page.

## Security — credentials are encrypted, plain-text is not supported

SPSConfigKit compiles credentials (service accounts, farm passphrase, PFX
passwords) into the MOF for every node, and **they must be encrypted with a DSC
document-encryption certificate — compiling them in clear text is not a
supported configuration.** The kit ships everything needed
(`scripts/init/Initialize-DscEncryption.ps1` generates the certificate and
patches every `Cfg*.psd1` to forbid plain text) plus a post-compile guard-rail
that fails if any credential slipped through in clear text:

```powershell
.\scripts\test\Invoke-MofEncryptionTest.ps1 -MofPath .\scripts\sps\MOF
```

See the [Securing Credentials](https://github.com/luigilink/SPSConfigKit/wiki/Securing-Credentials)
wiki page for the full walkthrough, certificate rotation, and troubleshooting.

> [!NOTE]
> Only the `scripts/Secrets.sample.psd1` template (placeholder passwords) is
> tracked in git; the real `scripts/Secrets.psd1` you fill in is git-ignored.
> Copy it once with `Copy-Item scripts/Secrets.sample.psd1 scripts/Secrets.psd1`
> before compiling, so your credentials never reach the repository.

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSConfigKit Wiki](https://github.com/luigilink/SPSConfigKit/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
