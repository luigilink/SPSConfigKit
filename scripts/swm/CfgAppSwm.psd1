@{
  AllNodes    =
  @(
    @{
      NodeName                    = '*'
      PSDscAllowPlainTextPassword = $True
      PSDscAllowDomainUser        = $True
    }
    @{
      NodeName    = 'SWM1'
      # Role flag read by CfgAppSwm.ps1. The server runs the SharePoint Workflow Manager (SWM),
      # not the legacy Microsoft Workflow Manager (no longer installable, support ended
      # 14 July 2026).
      IsSWMServer = $True
      # Domain accounts added to the local Administrators group: the setup account that runs
      # the Windows-level resources, and the SWM service account (svcswm).
      LocalAdmins = @('CONTOSO\svcspssetup', 'CONTOSO\svcswm')
    }
  )
  NonNodeData = @{
    # Single share root, the same one as the other bricks (hosted on a MEMBER server, not on
    # a domain controller). Every path of this configuration is derived from it: the SWM
    # installers are staged by Initialize-SoftwarePackages under <SourcePath>\SWM\BIN, and the
    # certificate files are <SourcePath>\<CerFileName / PfxFileName>.
    SourcePath  = '\\PULL\Softwarepackages'
    # Set to $false when the customer manages storage themselves (disks already created, or a
    # different layout): scripts/init/Initialize-DscDisks.ps1 then does nothing, but the
    # Drives.{Data,Logs,Temp} letters are still derived from Disks below, so the rest of the
    # configuration keeps working. Default $true.
    ManageDisks = $true
    # Data disks (keyed by Windows disk NUMBER, see Get-Disk on the node). They are initialised
    # by Initialize-DscDisks.ps1, not by this configuration. An Azure VM with a temporary disk
    # is 0=OS, 1=<temp>, 2=Data, 3=Logs. Drives.{Data,Logs,Temp} are DERIVED from this list by
    # Type, so a drive letter is declared only once.
    Disks       = @(
      @{ Id = '0'; Letter = 'C'; Type = 'OS'  ; FSLabel = 'SYSTEM'; AllocationUnitSize = 4KB  }
      @{ Id = '2'; Letter = 'F'; Type = 'Data'; FSLabel = 'DATA'  ; AllocationUnitSize = 64KB }
      @{ Id = '3'; Letter = 'G'; Type = 'Logs'; FSLabel = 'LOGS'  ; AllocationUnitSize = 64KB }
    )
    ADC         = @{
      certificates = @(
        @{
          Name         = 'SharePointWorkflowCert'
          FriendlyName = 'SharePointWorkflow'
          CerFileName  = 'SharePointWorkflow.cer'
          PfxFileName  = 'SharePointWorkflow.pfx'
        }
      )
    }
    # SQL client alias used by the farms; same shape as SQLAlias in CfgAppSps.psd1.
    SQLAlias    = @(
      @{
        Name         = 'WORKFLOW'
        ServerAlias  = 'SINGLE-SWM-SPSSQL'
        ServerName   = 'SQL1'
        InstanceName = 'MSSQLSERVER'
        Port         = 1433
      }
    )
    # IIS log folders, relative to Drives.Logs.
    IIS         = @{
      LogFolder     = 'LOGS\IIS'
      httpErrFolder = 'LOGS\HTTPERR'
    }
    # SharePoint Workflow Manager settings.
    SWM         = @{
      # HTTPS port of the Workflow Management endpoint (default documented by Microsoft Learn).
      HttpsPort           = 12290
      # ADC certificate set as the SSL certificate of the Workflow Manager farm; remove to keep the auto-generated one.
      SslCertificateName  = 'SharePointWorkflowCert'
      # Let Add-SBHost / Add-WFHost create the firewall rules of the farms.
      EnableFirewallRules = $true
      ServiceBus          = @{
        FarmDatabase = 'SBManagementDB'
        # Name used by the SPWFM configuration wizard.
        Namespace    = 'WorkflowDefaultNamespace'
      }
      WorkflowManager     = @{
        FarmDatabase = 'WFManagementDB'
      }
      # Installation logs, relative to Drives.Logs.
      LogFolder           = 'LOGS\SWM'
      # Installers, relative to <Drives.Data>\SoftwarePackages\SWM\BIN. The MSI ProductId changes with every version.
      ServiceFabric       = @{
        FileName       = 'ServiceFabric\MicrosoftServiceFabric.9.1.1583.9590.exe'
        MinimumVersion = '9.1.1583.9590'
      }
      WorkflowClient      = @{
        FileName  = 'sharepointworkflowmanagerclient_x64.msi'
        ProductId = '{CE257EBF-44F7-4CDD-8AB5-08DDE86FE024}'
      }
      WorkflowServer      = @{
        FileName  = 'sharepointworkflowmanager.msi'
        ProductId = '{04A7199E-565D-4654-88A3-80A9A7BADDD9}'
      }
    }
  }
}
