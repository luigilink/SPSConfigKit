# SPSConfigKit (DSC v3 line) - Release Notes

> This file is the release body for the **experimental DSC v3 channel** (`dsc3-v*` tags,
> published as GitHub pre-releases). The stable PowerShell DSC v1/v2 line uses
> [`RELEASE-NOTES.md`](RELEASE-NOTES.md).

## [dsc3-v0.1.0] - Unreleased

### Added

- New `dsc3/` folder introducing the experimental **DSC v3** line of SPSConfigKit,
  published on its own release channel so it never affects the stable
  PowerShell DSC v1/v2 line under `scripts/`.
  - `dsc3/README.md` documenting the differences between PowerShell DSC v1/v2 and DSC v3,
    the reuse of existing PSDSC resources through the `Microsoft.DSC/PowerShell` adapter,
    prerequisites and the `dsc config get/test/set` workflow.
  - `dsc3/configurations/sps.dsc.config.yaml`, a starter SharePoint Server SE
    configuration document that drives `SharePointDsc` resources via the PowerShell
    adapter (parameterised binary directory and product key).
  - `dsc3/resources/` placeholder for future DSC v3 resource manifests.
- Root README compatibility matrix describing the two release lines and their tag schemes.
- `.github/workflows/release.yml` extended to a two-channel release workflow: `v*` tags
  package `scripts/` as a normal release; `dsc3-v*` tags package `dsc3/` as a pre-release.
