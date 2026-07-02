@{
    # -----------------------------------------------------------------------
    # SPSDscDashboard — settings for scripts/dashboard/SPSDscDashboard.ps1.
    #
    # Loaded automatically (same folder) or via -InputFile. Every value can be
    # overridden on the command line; an explicit parameter always wins.
    # Contains no secrets (URLs / paths only), so it is tracked in git — edit it
    # in place for your environment.
    # -----------------------------------------------------------------------

    # Base URL of the pull server OData service. Use localhost when the dashboard
    # runs ON the pull server. NO trailing slash.
    PullServerUrl        = 'https://localhost/PSDSCPullServer.svc'

    # Shared folder of <NodeName>.json entries published by CfgLcmPull.ps1
    # (-NodeManifestPath). This is how the dashboard discovers which nodes exist,
    # because the pull server's OData API cannot enumerate them.
    NodeManifestPath     = 'F:\DscNodeManifest'

    # Where the generated HTML is written. Default is the pull server IIS site so
    # it is served over HTTPS at https://<pull>/Dashboard.html.
    OutputPath           = 'C:\inetpub\PSDSCPullServer\Dashboard.html'

    # Dashboard heading.
    Title                = 'SharePoint Farm - DSC Compliance'

    # Cap on reports fetched per node before selecting the latest (guards the
    # unbounded ESENT StatusReport table).
    MaxReportsPerNode    = 50

    # Ignore TLS validation when calling the pull server (self-signed lab certs).
    SkipCertificateCheck = $true

    # Offline/testing mode: path to a JSON file mirroring the OData shape
    # (see samples/mock-data.json). Leave $null for live rendering; set it to
    # render the dashboard from the mock file without a pull server.
    MockDataPath         = $null

    # -Action Install settings for the refresh Scheduled Task.
    Schedule = @{
        # Refresh cadence in minutes. MINIMUM 30 (enforced): DSC nodes only report
        # on their LCM consistency interval (ConfigurationModeFrequencyMins,
        # typically 60-120 min), so a shorter refresh adds load without newer data.
        # Align this with your farm's LCM: 30 for a 60-minute LCM, 60 for 120.
        IntervalMinutes = 30

        # Scheduled Task name.
        TaskName        = 'SPSConfigKit-DscDashboard'

        # Start the task once immediately after -Action Install (produces a first
        # dashboard without waiting for the first trigger).
        RunAfterInstall = $true
    }
}
