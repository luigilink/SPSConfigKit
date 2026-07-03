@{
    # -----------------------------------------------------------------------
    # SPSConfigKit — node prerequisites manifest (single source of truth).
    #
    # Consumed by:
    #   * scripts/init/Initialize-DscNode.ps1   (installs everything below)
    #   * scripts/pdc/CfgAppPdc.ps1             ┐
    #   * scripts/pull/CfgAppPull.ps1           │ Module versions MUST stay
    #   * scripts/sql/CfgAppSql.ps1             │ in sync with the
    #   * scripts/sps/CfgAppSps.ps1             ┘ Import-DscResource lines.
    # -----------------------------------------------------------------------

    Drives = @{
        Data = 'F:'
    }

    Chocolatey = @{
        Ensure   = 'Present'
        Packages = @(
            'sql-server-management-studio'
            'notepadplusplus'
            '7zip'
            'ulsviewer'
        )
    }

    # DSC document-encryption certificate. The .cer / .pfx are produced by
    # scripts/init/Initialize-DscEncryption.ps1 and dropped on the share.
    # On each target node the .pfx (private key) MUST be imported so the
    # Local Configuration Manager can decrypt credentials inside MOF files.
    # Set Ensure='Absent' to skip the import step entirely.
    Certificate = @{
        Ensure      = 'Present'
        SourcePath  = '\\PULL\Softwarepackages'
        CerFileName = 'DscEncryption.cer'
        PfxFileName = 'DscEncryption.pfx'
        Subject     = 'CN=DSC Encryption'
        Store       = 'Cert:\LocalMachine\My'
    }

    # DSC resource modules with pinned versions. Initialize-DscNode.ps1
    # calls Install-Module -RequiredVersion for each entry.
    Modules = @(
        @{ Name = 'ActiveDirectoryDsc';           Version = '6.7.1'    }
        @{ Name = 'ActiveDirectoryCSDsc';         Version = '5.0.0'    }
        @{ Name = 'CertificateDsc';               Version = '6.0.0'    }
        @{ Name = 'ComputerManagementDsc';        Version = '10.0.0'   }
        @{ Name = 'NetworkingDsc';                Version = '9.1.0'    }
        @{ Name = 'OfficeOnlineServerDsc';        Version = '1.5.0'    }
        @{ Name = 'PSDscResources';               Version = '2.12.0.0' }
        @{ Name = 'SharePointDsc';                Version = '5.7.0'    }
        @{ Name = 'SqlServerDsc';                 Version = '17.5.1'   }
        @{ Name = 'StorageDsc';                   Version = '6.0.1'    }
        @{ Name = 'WebAdministrationDsc';         Version = '4.2.1'    }
        @{ Name = 'xCredSSP';                     Version = '1.4.0'    }
        @{ Name = 'xPSDesiredStateConfiguration'; Version = '9.2.1'    }
    )
}
