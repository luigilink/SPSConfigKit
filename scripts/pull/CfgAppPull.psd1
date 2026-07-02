@{
  AllNodes    =
  @(
    @{
      NodeName                    = '*'
      PSDscAllowPlainTextPassword = $True
      PSDscAllowDomainUser        = $True
    }
    @{
      NodeName             = 'PULL'
      IsPullServer         = $true
      # Generated with: [guid]::NewGuid() in PowerShell
      RegistrationKey      = '********-****-****-****-************'
    }
  )
  NonNodeData = @{
    # Single share root — host the SoftwarePackages share on a MEMBER server
    # (e.g. this pull server), NOT on a domain controller. The certificate path is
    # derived from this by CfgAppPull.ps1 (SourcePath + CerFileName / PfxFileName).
    SourcePath = '\\PULL\Softwarepackages'
    Drives = @{
      Logs = 'G:'
    }
    ADC        = @{
      certificates = @(
        @{
          Name         = 'DscPullCert'
          FriendlyName = 'DSCPull'
          CerFileName  = 'DscPull.cer'
          PfxFileName  = 'DscPull.pfx'
        }
      )
    }
    IIS        = @{
      LogFolder     = 'LOGS\IIS'
      httpErrFolder = 'LOGS\HTTPERR'
    }
  }
}
