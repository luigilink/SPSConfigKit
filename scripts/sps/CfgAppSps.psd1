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
      UberCumulativeUpdate      = 'F:\SoftwarePackages\SPS\CU\202508\uber-subscription-kb5002773-fullfile-x64-glb.exe'
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
