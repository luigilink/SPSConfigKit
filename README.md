# SPSConfigKit

![Latest release date](https://img.shields.io/github/release-date/luigilink/SPSConfigKit.svg?style=flat)
![Total downloads](https://img.shields.io/github/downloads/luigilink/SPSConfigKit/total.svg?style=flat)  
![Issues opened](https://img.shields.io/github/issues/luigilink/SPSConfigKit.svg?style=flat)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## Description

SPSConfigKit is a PowerShell script tool designed to install and configure a SharePoint Farm with PowerShell Desired Configuration.

[Download the latest release, Click here!](https://github.com/luigilink/SPSConfigKit/releases/latest)

## Release lines

SPSConfigKit ships in two parallel lines, each on its own release channel. The stable line
is unaffected by the experimental one.

| Line | DSC engine | Location | Tag scheme | Release type |
| --- | --- | --- | --- | --- |
| **Stable** | PowerShell DSC v1/v2 (MOF + LCM) | [`scripts/`](scripts) | `v*` (e.g. `v1.1.1`) | Release |
| **Experimental** | DSC v3 (`dsc.exe`) | [`dsc3/`](dsc3) | `dsc3-v*` (e.g. `dsc3-v0.1.0`) | Pre-release |

The DSC v3 line is a ground-up rewrite (YAML/JSON configuration documents, no MOF) that reuses
the existing PowerShell DSC resources through the `Microsoft.DSC/PowerShell` adapter. See
[`dsc3/README.md`](dsc3/README.md) for details. Unless you are specifically evaluating DSC v3,
use the stable line under [`scripts/`](scripts).

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

## Documentation

For detailed usage, configuration, and getting started information, visit the [SPSConfigKit Wiki](https://github.com/luigilink/SPSConfigKit/wiki)

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
