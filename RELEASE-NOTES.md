# SPSConfigKit - Release Notes

## [1.10.0] - 2026-11-26

This release adds **SharePoint Workflow Manager (SWM)** support to the kit: a new `CfgAppSwm` configuration
that builds the SWM server, and an optional block in `CfgAppSps` that installs the SharePoint Workflow Manager
Client on the SharePoint servers and registers the Workflow Manager farm. It also fixes the order in which
non-master SharePoint servers join the farm. Everything new is optional and off by default
(`SharePoint.Workflow.Enabled = $false`), so existing farms are unaffected. The name is `SWM`, not `WFM`: the
legacy Microsoft Workflow Manager is no longer installable and its support ended on 14 July 2026.

### Added

- New `scripts/swm/CfgAppSwm` configuration for the SWM server (#95, #97, #99, #102, #104, #106, #108, #110, #114)
  - Builds the SWM server end to end in pull mode: the IIS prerequisites and firewall, Azure Service Fabric,
    the SharePoint Workflow Manager Client and SharePoint Workflow Manager installs, then the Service Bus
    and Workflow Manager farms with a SQL alias and the Service Bus namespace. The farm secrets are encrypted
    for the DSC certificate at compile time. The Workflow Manager endpoint can use the lab CA certificate
    (`SharePointWorkflowCert`, opt-in through `NonNodeData.SWM.SslCertificateName`).
  - Supporting changes: the `SWM` service account and the `SharePointWorkflowCert` certificate with its DNS
    name in the lab domain controller configuration, the SWM installers staged by
    `Initialize-SoftwarePackages`, and `SWMCertKey` in `Secrets.sample.psd1`.
  - The `SWM` section of the wiki documents the behaviours learned on the lab and the pull deployment.
    `CfgAppSwm` is still marked "In development" in the wiki.

- Register the Workflow Manager farm in `CfgAppSps` (#112)
  - New optional `NonNodeData.SharePoint.Workflow` block. When enabled, every SharePoint server installs the
    SharePoint Workflow Manager Client and the master registers the SWM farm with `SPWorkflowService`, after
    waiting for the SWM server and for the client installs of the other servers.
  - The compilation fails when a setting is missing or when an `http` `HostUri` has no `AllowOAuthHttp`.

- Ship sample modern team and communication sites with dedicated content databases (#93)

### Fixed

- Non-master SharePoint servers now join the farm only once the master has created it (#74)
  - The wait declared on the non-master nodes was not wired to the join. Waiting for the end of the master
    configuration would have deadlocked with the search topology wait (#73), so the master now emits an early
    `SPSFarmCreated_Completed` marker right after the farm creation and the join waits for it.
  - The permanent `PROCESS_SPSWaitForWebApp` drift reported at every consistency check on the non-master
    nodes is gone.

### Validation and known limits

- Validated on the lab Subscription Edition farm (pull mode): the SWM server is compliant, the SharePoint
  servers apply the Workflow block, both waits pass, the Workflow Service Application Proxy exists and the
  Workflow Service status page reports "Workflow is Connected".
- Not tested: running a SharePoint 2013 workflow end to end, and bringing up new (clean) nodes with the #74 fix.
- Not handled yet: updating the SharePoint Workflow Manager Client MSI when its product code changes (#116).
  The Service Bus certificates stay auto-generated. Port 443 for the Workflow Manager endpoint is untested;
  the lab uses 12290.
- To enable the Workflow block on an existing farm, let the master apply the new MOF first: the other
  SharePoint servers wait for the new marker until then.

## Changelog

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
