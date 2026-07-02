@{
    # -----------------------------------------------------------------------
    # CfgLcmPull — per-domain pull-server defaults (SAMPLE / template).
    #
    # Copy this file to CfgLcmPull.DomainDefaults.psd1 and fill in your real
    # values, then pass it to CfgLcmPull.ps1 with -DomainDefaultsPath. The real
    # file holds registration keys and is git-ignored — DO NOT commit it.
    #
    # Each key is a domain FQDN (as returned by the node's IPGlobalProperties
    # DomainName). CfgLcmPull.ps1 auto-selects the entry for the current domain
    # when -DSCRegistrationKey / -DSCPullServerUrl are not passed explicitly.
    #
    # Keep the pull server on HTTPS/443 (SPSConfigKit default posture).
    # -----------------------------------------------------------------------

    'contoso.com' = @{
        RegistrationKey = '00000000-0000-0000-0000-000000000000'
        PullServerUrl   = 'https://pull.contoso.com/PSDSCPullServer.svc'
        # Optional: shared folder where each node publishes its AgentId for the
        # compliance dashboard (New-SPSDscDashboard.ps1 -NodeManifestPath).
        NodeManifestPath = '\\pull.contoso.com\DscNodeManifest'
    }

    'fabrikam.com' = @{
        RegistrationKey = '11111111-1111-1111-1111-111111111111'
        PullServerUrl   = 'https://pull.fabrikam.com/PSDSCPullServer.svc'
        NodeManifestPath = '\\pull.fabrikam.com\DscNodeManifest'
    }
}
