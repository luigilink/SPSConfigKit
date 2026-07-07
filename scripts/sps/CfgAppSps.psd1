@{
  AllNodes    =
  @(
    @{
      NodeName                    = '*'
      PSDscAllowPlainTextPassword = $True
      PSDscAllowDomainUser        = $True
    }
    @{
      NodeName     = 'APP1'
      IsMaster     = $true
      CacheSize    = 2048
      IsSPSServer  = $True
      SPVersion    = 'SE'
      IsSPSSingle  = $False
      #MinRole Valid: "ApplicationWithSearch","Custom","DistributedCache","Search","SingleServerFarm","WebFrontEnd","WebFrontEndWithDistributedCache"
      SPServerRole = 'Application'
      LocalAdmins  = @('CONTOSO\svcspssetup', 'CONTOSO\svcspsfarm', 'CONTOSO\svcspsearch')
    }
    @{
      NodeName     = 'WFE1'
      IsAFCache    = $true
      CacheSize    = 2048
      IsSPSServer  = $True
      SPVersion    = 'SE'
      IsSPSSingle  = $False
      #MinRole Valid: "ApplicationWithSearch","Custom","DistributedCache","Search","SingleServerFarm","WebFrontEnd","WebFrontEndWithDistributedCache"
      SPServerRole = 'WebFrontEndWithDistributedCache'
      LocalAdmins  = @('CONTOSO\svcspssetup', 'CONTOSO\svcspsfarm')
    }
    @{
      NodeName     = 'SCH1'
      IsSPSServer  = $True
      SPVersion    = 'SE'
      IsSPSSingle  = $False
      #MinRole Valid: "ApplicationWithSearch","Custom","DistributedCache","Search","SingleServerFarm","WebFrontEnd","WebFrontEndWithDistributedCache"
      SPServerRole = 'Search'
      IsSrcAdmin   = $True
      IsSrcCrawl   = $True
      IsCntProc    = $True
      IsSrcAnalyt  = $True
      IsSrcQuery   = $True
      IsIndexPart  = $True
      LocalAdmins  = @('CONTOSO\svcspssetup', 'CONTOSO\svcspsfarm', 'CONTOSO\svcspsearch')
    }
    @{
      NodeName    = 'OOS1'
      IsMaster    = $True
      IsOOSServer = $True
      IsOOSSingle = $True
      LocalAdmins = @('CONTOSO\svcspssetup')
    }
  )
  NonNodeData = @{
    # Single share root — host the SoftwarePackages share on a MEMBER server
    # (e.g. the pull server), NOT on a domain controller: a node already has a
    # machine session to the DC, and Windows refuses a second identity to the same
    # server, so a share on the DC fails at apply with "Access is denied".
    # The certificate paths below are derived from this by CfgAppSps.ps1
    # (SourcePath + CerFileName / PfxFileName), so the host is defined only here.
    SourcePath  = '\\PULL\Softwarepackages'
    DomainName  = 'contoso.com'
    # Set to $false when the customer manages storage themselves. Default $true.
    ManageDisks = $true
    # Data disks, initialised by scripts/init/Initialize-DscDisks.ps1 (keyed by disk Number).
    # Drives.{Data,Logs} letters consumed elsewhere are DERIVED from this by Type.
    # NOTE: disk numbers are environment-specific. These defaults match a VM with
    #   NO temp disk (0=OS, 1=Data, 2=Logs) — the SharePoint VM sizes used here.
    #   An Azure VM WITH a temp disk shifts to 0=OS, 1=<temp>, 2=Data, 3=Logs (as
    #   the PDC/PULL/SQL samples use) — adjust Id to match 'Get-Disk'.
    Disks       = @(
      @{ Id = '0'; Letter = 'C'; Type = 'OS'  ; FSLabel = 'SYSTEM'; AllocationUnitSize = 4KB   }
      @{ Id = '1'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'  ; AllocationUnitSize = 4KB   }
      @{ Id = '2'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'  ; AllocationUnitSize = 4KB   }
    )
    ADC         = @{
      certificates = @(
        @{
          Name         = 'DscPullCert'
          FriendlyName = 'DSCPull'
          CerFileName  = 'DscPull.cer'
          PfxFileName  = 'DscPull.pfx'
        }
        @{
          Name         = 'SharePointCert'
          FriendlyName = 'SharePoint'
          CerFileName  = 'SharePoint.cer'
          PfxFileName  = 'SharePoint.pfx'
        }
        @{
          Name         = 'OfficeOnlineCert'
          FriendlyName = 'OOSCertSSL'
          CerFileName  = 'OfficeOnline.cer'
          PfxFileName  = 'OfficeOnline.pfx'
        }
        @{
          Name         = 'SQLServerCert'
          FriendlyName = 'SQLCertSSL'
          CerFileName  = 'SQLServer.cer'
          PfxFileName  = 'SQLServer.pfx'
        }
      )
    }
    # SQL Server connection encryption. Must stay in sync with CfgAppSql.psd1's
    # NonNodeData.SQL block: when the SQL tier forces encryption, SharePoint imports the
    # SQL certificate (CertificateName, an ADC.certificates entry) into LocalMachine\Root
    # so it trusts the SQL TLS chain. Set both sides to $false together to disable.
    # DatabaseConnectionEncryption is applied to the SPFarm resource (required by the
    # SharePoint SE 2025-08 PU): Optional encrypts without validating the SQL certificate;
    # Mandatory / Strict also validate the chain (they rely on the Root import above).
    SQL        = @{
      ForceEncryption              = $true
      CertificateName              = 'SQLServerCert'
      DatabaseConnectionEncryption = 'Mandatory'
    }
    SQLAlias   = @(
      @{
        Name         = 'ADMIN'
        ServerAlias  = 'SINGLE-ADM-SPSSQL'
        ServerName   = 'SQL1'
        InstanceName = 'MSSQLSERVER'
        Port         = 1433
      }
      @{
        Name         = 'SEARCH'
        ServerAlias  = 'SINGLE-SCH-SPSSQL'
        ServerName   = 'SQL1'
        InstanceName = 'MSSQLSERVER'
        Port         = 1433
      }
      @{
        Name         = 'SERVICES'
        ServerAlias  = 'SINGLE-SVC-SPSSQL'
        ServerName   = 'SQL1'
        InstanceName = 'MSSQLSERVER'
        Port         = 1433
      }
      @{
        Name         = 'CONTENT'
        ServerAlias  = 'SINGLE-WEB-SPSSQL'
        ServerName   = 'SQL1'
        InstanceName = 'MSSQLSERVER'
        Port         = 1433
      }
    )
    IIS        = @{
      LogFolder     = 'LOGS\IIS'
      httpErrFolder = 'LOGS\HTTPERR'
    }
    OOS        = @{
      AllServers                  = @('OOS1')
      # Optional installation-media path overrides. When omitted the script falls back to:
      #   SourcePath      = <NonNodeData.SourcePath>\OOS
      #   DestinationPath = <Drives.Data>\SoftwarePackages\OOS
      # Each Subfolders entry is also optional and defaults to BIN / LP / CU respectively.
      # CUFileName may be a filename (resolved relative to <DestinationPath>\<Subfolders.CumulativeUpdate>)
      # or an absolute path (used as-is).
      # SourcePath                  = '\\PULL\Softwarepackages\OOS'
      # DestinationPath             = 'F:\SoftwarePackages\OOS'
      # Subfolders                  = @{ Binaries = 'BIN'; LanguagePack = 'LP'; CumulativeUpdate = 'CU' }
      CUFileName                  = 'wacserver2019-kb5002871-fullfile-x64-glb.exe'
      URL                         = 'oosweb.contoso.com'
      CertFriendlyName            = 'OOSCertSSL'
      LogLocation                 = 'LOGS\OOS'
      CacheLocation               = 'OOS\Cache'
      RenderingLocalCacheLocation = 'OOS\RenderingCache'
    }
    SharePoint = @{
      # Replace with your own SharePoint Server SE product key (format: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX).
      # DO NOT commit a real key — keep this placeholder in source control.
      ProductKey                = 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
      DiagnosticLogs            = 'LOGS\SPS'
      UsageLogs                 = 'LOGS\USAGE'
      # Optional installation-media path overrides for customers whose file hierarchy
      # differs from the kit's defaults. When omitted the script falls back to:
      #   SourcePath      = <NonNodeData.SourcePath>\SPS
      #   DestinationPath = <Drives.Data>\SoftwarePackages\SPS
      # Each Subfolders entry is also optional and defaults to BIN / LP / CU respectively.
      # SourcePath                = '\\PULL\Softwarepackages\SPS'
      # DestinationPath           = 'F:\SoftwarePackages\SPS'
      # Subfolders                = @{ Binaries = 'BIN'; LanguagePack = 'LP'; CumulativeUpdate = 'CU' }
      # Optional list of SharePoint Language Pack locale codes to install (e.g. @('fr-fr','es-es','de-de')).
      # Each entry must match a sub-folder under <DestinationPath>\<Subfolders.LanguagePack>\ that
      # contains the corresponding setup.exe. Leave empty (@()) or omit to skip language pack installation.
      # Reference: https://learn.microsoft.com/en-us/sharepoint/install/install-or-uninstall-language-packs-subscription
      LanguagePacks             = @('fr-fr')
      # CU package: either an absolute path (used as-is, current default) or a relative path
      # resolved under <DestinationPath>\<Subfolders.CumulativeUpdate>.
      UberCumulativeUpdate      = '\\PULL\Softwarepackages\SPS\CU\uber-subscription-kb5002863-fullfile-x64-glb.exe'
      FarmConfigDatabaseName    = 'DSPS_Admin_Config'
      AdminContentDatabaseName  = 'DSPS_Admin_Content'
      CentralAdministrationPort = '5555'
      MailSettings              = @{
        SMTPServer     = 'smtp.contoso.com'
        FromAddress    = 'noreply@contoso.com'
        ReplyToAddress = 'noreply@contoso.com'
        CharacterSet   = '65001'
      }
      ServiceAppPoolName        = 'SharePointServiceApplications'
      # Optional allowlist of Secrets.psd1 account names that SharePoint owns as Managed Accounts.
      # Defaults to @('FARM', 'IISAPP', 'SEARCH') when omitted (the historical set). Add an entry
      # here when a new SharePoint Managed Account is introduced (e.g. a dedicated Workflow or
      # Custom Service Application service account). Accounts not listed here are NOT registered
      # as SPManagedAccount resources, which keeps unrelated entries (PULLSETUP, IISPULLAPP, SQL,
      # OOS, monitoring, ...) out of the SPS MOF.
      ManagedAccounts           = @('FARM', 'IISAPP', 'SEARCH')
      WebApplications           = @(
        @{
          Name            = 'SharePoint'
          ApplicationPool = 'PAMYSITE'
          Path            = 'C:\InetPub\wwwRoot\wss\virtualDirectories\SharePoint'
          ContentDBName   = 'DSPS_CONTENT_MySite'
          Url             = 'https://sharepoint.contoso.com'
          HostHeader      = 'sharepoint.contoso.com'
          Port            = 443
          CertName        = 'SharePointCert'
          ManagedPath     = @(
            @{
              Name        = 'Search'
              Explicit    = $true
              HostHeader  = $false
              RelativeUrl = 'search'
            }
          )
          Sites           = @(
            @{
              Name            = 'MySiteHost'
              Url             = 'https://sharepoint.contoso.com'
              Template        = 'SPSMSITEHOST#0'
              Language        = 1033
              ContentDatabase = 'DSPS_CONTENT_MySite'
            }
            @{
              Name            = 'SearchCenter'
              Url             = 'https://sharepoint.contoso.com/search'
              Template        = 'SRCHCEN#0'
              Language        = 1033
              ContentDatabase = 'DSPS_CONTENT_SearchCenter'
            }
            @{
              Name            = 'AppsCatalog'
              Url             = 'https://sharepoint.contoso.com/sites/apps'
              Template        = 'APPCATALOG#0'
              Language        = 1033
              ContentDatabase = 'DSPS_CONTENT_AppsCatalog'
            }
          )
        }
      )
      Services                  = @{
        StateService                = @{
          Name         = 'SVCStateService'
          DatabaseName = 'DSPS_SVC_StateService'
        }
        SessionState                = @{
          Name         = 'SVCSessionState'
          DatabaseName = 'DSPS_SVC_SessionState'
        }
        UsageService                = @{
          Name         = 'SVCUsageService'
          DatabaseName = 'DSPS_SVC_UsageService'
        }
        SearchService               = @{
          Name            = 'SVCSearchService'
          DatabaseName    = 'DSPS_SCH_SearchService'
          SearchCenterUrl = 'https://sharepoint.contoso.com/search'
          # First search index partition directory. Resolved at compile time as
          # <Drives.Data>\<Topology.FirstPartitionDirectory> (e.g. F:\OfficeServer\Index)
          # and fed to SPSearchTopology.FirstPartitionDirectory. Keep it on the data
          # drive, NOT the system drive, so the index doesn't fill C:.
          Topology        = @{
            FirstPartitionDirectory = 'OfficeServer\Index'
          }
          ContentSources  =
          @{
            LocalSharePointsites =
            @{
              ContinuousCrawl = $true
              Name            = 'Local SharePoint sites'
              StartAddresses  = @('https://sharepoint.contoso.com')
            }
            SharePointProfile    =
            @{
              ContinuousCrawl = $false
              Name            = 'SharePoint Profiles'
              StartAddresses  = @('sps3s://sharepoint.contoso.com')
            }
          }
        }
        UserProfile                 = @{
          Name               = 'SVCUserProfileService'
          ProfileDBName      = 'DSPS_SVC_UserProfile_Profile'
          SocialDBName       = 'DSPS_SVC_UserProfile_Social'
          SyncDBName         = 'DSPS_SVC_UserProfile_Sync'
          MySiteHostLocation = 'https://sharepoint.contoso.com'
        }
        ManagedMetadataService      = @{
          Name         = 'SVCManagedMetadataService'
          DatabaseName = 'DSPS_SVC_ManagedMetadataService'
        }
        AppManagementService        = @{
          Name          = 'SVCAppManagementService'
          DatabaseName  = 'DSPS_SVC_AppManagementService'
          AppCatalogUrl = 'https://sharepoint.contoso.com/sites/apps'
        }
        SubscriptionSettingsService = @{
          Name         = 'SVCSubscriptionSettingsService'
          DatabaseName = 'DSPS_SVC_SubscriptionSettingsService'
        }
      }
    }
  }
}
