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
    Drives = @{
      Logs = 'G:'
    }
    ADC        = @{
      certificates = @(
        @{
          Name         = 'DscPullCert'
          FriendlyName = 'DSCPull'
          CertPath     = '\\PDC1\Softwarepackages\DscPull.cer'
          PfxPath      = '\\PDC1\Softwarepackages\DscPull.pfx'
        }
      )
    }
    IIS        = @{
      LogFolder     = 'LOGS\IIS'
      httpErrFolder = 'LOGS\HTTPERR'
    }
  }
}
