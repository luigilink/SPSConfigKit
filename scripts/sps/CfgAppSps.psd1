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
    SourcePath  = '\\PDC1\Softwarepackages'
    DomainName  = 'contoso.com'
    Drives      = @{
      Data = 'F:'
      Logs = 'G:'
    }
    ADC         = @{
      certificates = @(
        @{
          Name         = 'DscPullCert'
          FriendlyName = 'DSCPull'
          CertPath     = '\\PDC1\Softwarepackages\DscPull.cer'
          PfxPath      = '\\PDC1\Softwarepackages\DscPull.pfx'
        }
        @{
          Name         = 'SharePointCert'
          FriendlyName = 'SharePoint'
          CertPath     = '\\PDC1\Softwarepackages\SharePoint.cer'
          PfxPath      = '\\PDC1\Softwarepackages\SharePoint.pfx'
        }
        @{
          Name         = 'OfficeOnlineCert'
          FriendlyName = 'OOSCertSSL'
          CertPath     = '\\PDC1\Softwarepackages\OfficeOnline.cer'
          PfxPath      = '\\PDC1\Softwarepackages\OfficeOnline.pfx'
        }
        @{
          Name         = 'SQLServerCert'
          FriendlyName = 'SQLCertSSL'
          CertPath     = '\\PDC1\Softwarepackages\SQLServer.cer'
          PfxPath      = '\\PDC1\Softwarepackages\SQLServer.pfx'
        }
      )
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
      AllServers                  = @('OOS')
      # Optional installation-media path overrides. When omitted the script falls back to:
      #   SourcePath      = <NonNodeData.SourcePath>\OOS
      #   DestinationPath = <Drives.Data>\SoftwarePackages\OOS
      # Each Subfolders entry is also optional and defaults to BIN / LP / CU respectively.
      # CUFileName may be a filename (resolved relative to <DestinationPath>\<Subfolders.CumulativeUpdate>)
      # or an absolute path (used as-is).
      # SourcePath                  = '\\PDC1\Softwarepackages\OOS'
      # DestinationPath             = 'F:\SoftwarePackages\OOS'
      # Subfolders                  = @{ Binaries = 'BIN'; LanguagePack = 'LP'; CumulativeUpdate = 'CU' }
      CUFileName                  = 'wacserver2019-kb5002752-fullfile-x64-glb.exe'
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
      # SourcePath                = '\\PDC1\Softwarepackages\SPS'
      # DestinationPath           = 'F:\SoftwarePackages\SPS'
      # Subfolders                = @{ Binaries = 'BIN'; LanguagePack = 'LP'; CumulativeUpdate = 'CU' }
      # Optional list of SharePoint Language Pack locale codes to install (e.g. @('fr-fr','es-es','de-de')).
      # Each entry must match a sub-folder under <DestinationPath>\<Subfolders.LanguagePack>\ that
      # contains the corresponding setup.exe. Leave empty (@()) or omit to skip language pack installation.
      # Reference: https://learn.microsoft.com/en-us/sharepoint/install/install-or-uninstall-language-packs-subscription
      LanguagePacks             = @('fr-fr')
      # CU package: either an absolute path (used as-is, current default) or a relative path
      # resolved under <DestinationPath>\<Subfolders.CumulativeUpdate>.
      UberCumulativeUpdate      = '\\PDC1\Softwarepackages\SPS\CU\uber-subscription-kb5002773-fullfile-x64-glb.exe'
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
