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
    # SharePoint Workflow Manager settings.
    SWM         = @{
      # HTTPS port of the Workflow Management endpoint (opened in the firewall, and used by the farm
      # creation). 12290 is the default documented by Microsoft Learn.
      HttpsPort = 12290
    }
    # IIS log folders, relative to Drives.Logs.
    IIS         = @{
      LogFolder     = 'LOGS\IIS'
      httpErrFolder = 'LOGS\HTTPERR'
    }
  }
}
