@{
  AllNodes    =
  @(
    @{
      NodeName                    = '*'
      PSDscAllowPlainTextPassword = $True
      PSDscAllowDomainUser        = $True
    }
    @{
      NodeName          = 'PDC1'
      IsADSServer       = $True
      IsPDCServer       = $True
      IsADCServer       = $True
      ApplyEdgePolicies = $True
      # Optional override for the NIC used by Set-DnsClientServerAddress.
      # Leave blank to auto-detect the NIC that holds the default IPv4 gateway
      # at apply time (works for Azure VMs, Hyper-V and bare metal).
      InterfaceAlias    = ''
    }
  )
  NonNodeData = @{
    # Single share root — host the SoftwarePackages share on a MEMBER server
    # (e.g. the pull server), NOT on a domain controller. Certificate paths are
    # derived from this by CfgAppPdc.ps1 (SourcePath + CerFileName / PfxFileName).
    SourcePath  = '\\PULL\Softwarepackages'
    # Set to $false when the customer manages storage themselves. Default $true.
    ManageDisks = $true
    # Data disks, initialised by scripts/init/Initialize-DscDisks.ps1 (keyed by disk Number).
    # Drives.{Data,Logs} letters are DERIVED from this by Type. Best practice: at
    # least 3 disks (SYSTEM/DATA/LOGS). Disk numbers are environment-specific:
    #   a plain VM is usually 0=OS, 1=Data, 2=Logs; an Azure VM WITH a temp disk
    #   shifts to 0=OS, 1=<temp>, 2=Data, 3=Logs — adjust Id to match 'Get-Disk'.
    Disks       = @(
      @{ Id = '0'; Letter = 'C'; Type = 'OS';   FSLabel = 'SYSTEM' ; AllocationUnitSize = 4KB }
      @{ Id = '2'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'   ; AllocationUnitSize = 4KB }
      @{ Id = '3'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'   ; AllocationUnitSize = 4KB }
    )
    ADS        = @{
      DomainName        = 'contoso.com'
      DomainNetBIOSName = 'CONTOSO'
      DnsServerAddress  = '10.1.1.4'
    }
    # DNS A records the domain controller publishes in the domain zone so the
    # SharePoint web-application and Office Online host names resolve (farm
    # creation binds them and otherwise fails with "The server did not respond").
    # Name is the host label (the domain is appended); IPAddress is the target
    # (WFE/VIP for the web app, the OOS server for Office Online). Omit or leave
    # empty to publish no records.
    DnsRecords = @(
      @{ Name = 'sharepoint'; IPAddress = '10.1.1.27' }
      @{ Name = 'oosweb'     ; IPAddress = '10.1.1.31' }
    )
    ADC        = @{
      certificates = @(
        @{
          Name         = 'DscPullCert'
          FriendlyName = 'DSCPull'
          Subject      = 'pull.contoso.com'
          SubjectAlt   = 'dns=pull.contoso.com'
          CerFileName  = 'DscPull.cer'
          PfxFileName  = 'DscPull.pfx'
        }
        @{
          Name         = 'SharePointCert'
          FriendlyName = 'SharePoint'
          Subject      = 'sharepoint.contoso.com'
          SubjectAlt   = 'dns=sharepoint.contoso.com'
          CerFileName  = 'SharePoint.cer'
          PfxFileName  = 'SharePoint.pfx'
        }
        @{
          Name         = 'OfficeOnlineCert'
          FriendlyName = 'OOSCertSSL'
          Subject      = 'oosweb.contoso.com'
          SubjectAlt   = 'dns=oosweb.contoso.com'
          CerFileName  = 'OfficeOnline.cer'
          PfxFileName  = 'OfficeOnline.pfx'
        }
        @{
          Name         = 'SQLServerCert'
          FriendlyName = 'SQLCertSSL'
          Subject      = 'sql1.contoso.com'
          SubjectAlt   = 'dns=sql1&dns=sql1.contoso.com'
          CerFileName  = 'SQLServer.cer'
          PfxFileName  = 'SQLServer.pfx'
        }
      )
    }
    # Microsoft Edge browser policies pushed via GPO on the AD domain.
    # Reference: https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies
    EdgePolicies = @(
      @{ policyValueName = 'HideFirstRunExperience';           policyCanBeRecommended = $false; policyValueValue = 1 }
      @{ policyValueName = 'TrackingPrevention';               policyCanBeRecommended = $false; policyValueValue = 3 }
      @{ policyValueName = 'AdsTransparencyEnabled';           policyCanBeRecommended = $false; policyValueValue = 0 }
      @{ policyValueName = 'BingAdsSuppression';               policyCanBeRecommended = $false; policyValueValue = 1 }
      @{ policyValueName = 'AdsSettingForIntrusiveAdsSites';   policyCanBeRecommended = $false; policyValueValue = 2 }
      @{ policyValueName = 'AskBeforeCloseEnabled';            policyCanBeRecommended = $true;  policyValueValue = 0 }
      @{ policyValueName = 'BlockThirdPartyCookies';           policyCanBeRecommended = $true;  policyValueValue = 1 }
      @{ policyValueName = 'ConfigureDoNotTrack';              policyCanBeRecommended = $false; policyValueValue = 1 }
      @{ policyValueName = 'DiagnosticData';                   policyCanBeRecommended = $false; policyValueValue = 0 }
      @{ policyValueName = 'HubsSidebarEnabled';               policyCanBeRecommended = $true;  policyValueValue = 0 }
      @{ policyValueName = 'HomepageIsNewTabPage';             policyCanBeRecommended = $true;  policyValueValue = 1 }
      @{ policyValueName = 'HomepageLocation';                 policyCanBeRecommended = $true;  policyValueValue = 'edge://newtab' }
      @{ policyValueName = 'ShowHomeButton';                   policyCanBeRecommended = $true;  policyValueValue = 1 }
      @{ policyValueName = 'NewTabPageLocation';               policyCanBeRecommended = $true;  policyValueValue = 'about://blank' }
      @{ policyValueName = 'NewTabPageQuickLinksEnabled';      policyCanBeRecommended = $false; policyValueValue = 1 }
      @{ policyValueName = 'NewTabPageContentEnabled';         policyCanBeRecommended = $false; policyValueValue = 0 }
      @{ policyValueName = 'NewTabPageAllowedBackgroundTypes'; policyCanBeRecommended = $false; policyValueValue = 3 }
      @{ policyValueName = 'NewTabPageAppLauncherEnabled';     policyCanBeRecommended = $false; policyValueValue = 0 }
    )
  }
}
