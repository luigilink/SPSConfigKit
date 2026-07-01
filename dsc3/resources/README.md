# DSC v3 custom resource manifests

This folder will hold **DSC v3 resource manifests** (`*.dsc.resource.json`) for any capability
that isn't already covered by an existing PowerShell DSC resource reused through the
`Microsoft.DSC/PowerShell` adapter.

It is intentionally empty for now — the starter
[`../configurations/sps.dsc.config.yaml`](../configurations/sps.dsc.config.yaml) relies entirely
on the adapter. Add manifests here as the v3 line grows.

Reference: <https://learn.microsoft.com/en-us/powershell/dsc/concepts/resources>
