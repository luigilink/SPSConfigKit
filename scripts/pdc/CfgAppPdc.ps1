<#
  ---------------------------------------------------------------------------------
  The sample scripts are not supported under any Microsoft standard support
  program or service. The sample scripts are provided AS IS without warranty
  of any kind. Microsoft further disclaims all implied warranties including,
  without limitation, any implied warranties of merchantability or of fitness for
  a particular purpose. The entire risk arising out of the use or performance of
  the sample scripts and documentation remains with you. In no event shall
  Microsoft, its authors, or anyone else involved in the creation, production, or
  delivery of the scripts be liable for any damages whatsoever (including,
  without limitation, damages for loss of business profits, business interruption,
  loss of business information, or other pecuniary loss) arising out of the use
  of or inability to use the sample scripts or documentation, even if Microsoft
  has been advised of the possibility of such damages
  ---------------------------------------------------------------------------------
#>
#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
  .SYNOPSIS
  Compiles the PDC1 DSC configuration: Active Directory Domain Services,
  Active Directory Certificate Services, service / user account provisioning
  and (optionally) Microsoft Edge browser policies pushed via GPO.

  .DESCRIPTION
  Imports node + non-node data from a .psd1 file and secret material from
  Secrets.psd1, then compiles MOF files for every node defined in AllNodes.
  The script is idempotent: re-running it simply regenerates the MOFs in
  the output directory and refreshes the checksums.

  .PARAMETER inputFile
  Full path to the ConfigurationData .psd1. Defaults to CfgAppPdc.psd1 in
  the same directory as the script.

  .PARAMETER secretsFile
  Full path to the Secrets.psd1. Defaults to ..\Secrets.psd1 relative to
  the script directory.

  .PARAMETER OutputPath
  Directory where the compiled MOF files (and checksums) are written.
  Defaults to <scriptDir>\MOF. The directory is created if missing.

  .EXAMPLE
  .\CfgAppPdc.ps1

  .EXAMPLE
  .\CfgAppPdc.ps1 -inputFile .\CfgAppPdc.psd1 -secretsFile ..\Secrets.psd1 -OutputPath C:\DSC\MOF

  .NOTES
  Project : SPSConfigKit
  Requires: PowerShell 5.1, RunAsAdministrator, and the DSC modules listed in the Import-DscResource calls below.
#>

[CmdletBinding()]
param(
  [Parameter()]
  [System.String]
  $inputFile,

  [Parameter()]
  [System.String]
  $secretsFile,

  [Parameter()]
  [System.String]
  $OutputPath
)

try {
  #Resolve a reliable base path even when $PSScriptRoot is empty (for example when executed interactively)
  [System.String]$scriptBasePath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
  }
  elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
  }
  else {
    (Get-Location).Path
  }

  #Import configuration data from the specified .psd1 file
  if ([string]::IsNullOrWhiteSpace($inputFile)) {
    write-host "No input file provided. Try to use CfgAppPdc.psd1 in the same directory as the script."
    $inputFile = Join-Path -Path $scriptBasePath -ChildPath 'CfgAppPdc.psd1'
  }
  if (Test-Path $inputFile) {
    write-host "Importing configuration data from $inputFile"
    $configurationData = Import-PowerShellDataFile -Path  $inputFile
  }
  else {
    Throw "Missing $inputFile"
  }

  # DRY: derive certificate paths from the single share root (NonNodeData.SourcePath)
  # + each entry's CerFileName / PfxFileName, so the share host is defined only once.
  # An explicit CertPath / PfxPath on an entry is still honoured (backward compatible).
  $certSourcePath = $configurationData.NonNodeData.SourcePath
  if ($configurationData.NonNodeData.ADC -and $configurationData.NonNodeData.ADC.certificates) {
    foreach ($cert in $configurationData.NonNodeData.ADC.certificates) {
      $certRoot = $certSourcePath.TrimEnd('\\')
      if ([string]::IsNullOrWhiteSpace($cert.CertPath) -and -not [string]::IsNullOrWhiteSpace($cert.CerFileName)) {
        $cert.CertPath = '{0}\{1}' -f $certRoot, $cert.CerFileName
      }
      if ([string]::IsNullOrWhiteSpace($cert.PfxPath) -and -not [string]::IsNullOrWhiteSpace($cert.PfxFileName)) {
        $cert.PfxPath = '{0}\{1}' -f $certRoot, $cert.PfxFileName
      }
    }
  }

  # DRY: derive the semantic Drives hashtable (Data/Logs/Temp -> letter) from the
  # authoritative NonNodeData.Disks list, so a drive letter is declared only once.
  # Temp falls back to the Data drive when no dedicated Temp disk is declared.
  if ($configurationData.NonNodeData.Disks) {
    $byType = @{}
    foreach ($disk in $configurationData.NonNodeData.Disks) {
      if (-not [string]::IsNullOrWhiteSpace($disk.Type) -and -not [string]::IsNullOrWhiteSpace($disk.Letter)) {
        $byType[$disk.Type] = ($disk.Letter.TrimEnd(':')) + ':'
      }
    }
    $drives = @{}
    if ($byType.Data) { $drives.Data = $byType.Data }
    if ($byType.Logs) { $drives.Logs = $byType.Logs }
    $drives.Temp = if ($byType.Temp) { $byType.Temp } elseif ($byType.Data) { $byType.Data } else { $null }
    $configurationData.NonNodeData.Drives = $drives
  }

  if ([string]::IsNullOrWhiteSpace($secretsFile)) {
    write-host "No secrets file provided. Try to use Secrets.psd1 in the parent directory of the script."
    $secretsFile = Join-Path -Path (Split-Path -Path $scriptBasePath -Parent) -ChildPath 'Secrets.psd1'
  }
  if (Test-Path $secretsFile) {
    write-host "Importing secrets data from $secretsFile"
    $secretsData = Import-PowerShellDataFile -Path  $secretsFile
    #Initialize each secret as a variable
    $serviceAccounts = $secretsData.serviceAccounts
    foreach ($serviceAccount in $serviceAccounts) {
      $username = $serviceAccount.UserName
      $password = ConvertTo-SecureString $serviceAccount.Password -AsPlainText -Force
      $credential = New-Object -Typename System.Management.Automation.PSCredential `
        -Argumentlist $username, $password
      New-Variable -Name $serviceAccount.Name -Value $credential -Force
    }
  }
  else {
    Throw "Missing $secretsFile"
  }

  #Initialization of the output path for the generated MOF files.
  #Honour the -OutputPath parameter when supplied; otherwise default to <scriptDir>\MOF.
  if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $mofOutputPath = Join-Path -Path $scriptBasePath -ChildPath 'MOF'
  }
  else {
    $mofOutputPath = $OutputPath
  }
  if (-not (Test-Path -Path $mofOutputPath)) {
    New-Item -Path $mofOutputPath -ItemType Directory | Out-Null
  }

  Configuration CfgAppPdc {
    #Initialize variables
    $dataDrive = $configurationData.NonNodeData.Drives.Data
    [System.String] $fullQualifiedDomainName = $ConfigurationData.NonNodeData.ADS.DomainName
    # Build the domain DN from any number of labels so the script works for
    # contoso.com (-> DC=contoso,DC=com), europe.contoso.com
    # (-> DC=europe,DC=contoso,DC=com), local (-> DC=local), etc.
    [System.String] $domainDN = ($fullQualifiedDomainName -split '\.' | ForEach-Object { "DC=$_" }) -join ','
    [System.String] $svcOUActiveDirectoryPath = "OU=ServiceAccounts,$domainDN"
    [System.String] $intOUActiveDirectoryPath = "OU=INT,$domainDN"

    # NOTE: Module versions below MUST stay in sync with
    #       scripts/init/Initialize-DscNode.psd1 (Modules table).
    #Import the required DSC resources
    Import-DscResource -ModuleName ActiveDirectoryDsc -ModuleVersion 6.7.1
    Import-DscResource -ModuleName ActiveDirectoryCSDsc -ModuleVersion 5.0.0
    Import-DscResource -ModuleName CertificateDsc -ModuleVersion 6.0.0
    Import-DscResource -ModuleName ComputerManagementDsc -ModuleVersion 10.0.0
    Import-DscResource -ModuleName PSDscResources -ModuleVersion 2.12.0.0

    #For All servers
    Node $AllNodes.Nodename {
      #Set the Local Configuration Manager
      LocalConfigurationManager {
        ConfigurationMode  = 'ApplyOnly'
        RebootNodeIfNeeded = $true
        # Certificate the LCM uses to decrypt the encrypted credentials in this
        # node's MOF. $Node.Thumbprint is injected into the wildcard block by
        # Initialize-DscEncryption.ps1; without it the LCM cannot process an
        # encrypted MOF ("LCM is not configured with a certificate").
        CertificateID      = $Node.Thumbprint
      }

      #Create the SoftwarePackages folder
      File APPLICATION_SpsAddSoftwarePackages {
        Ensure          = 'Present'
        Type            = 'Directory'
        DestinationPath = "$dataDrive\SoftwarePackages"
      }
      #Stop unnecessary Windows Services
      Service SYSTEM_SvcSpoolerManualStopped {
        Name        = 'Spooler'
        StartupType = 'Manual'
        State       = 'Stopped'
      }
      Service SYSTEM_SvcAudioSrvManualStopped {
        Name        = 'AudioSrv'
        StartupType = 'Manual'
        State       = 'Stopped'
      }
      Service SYSTEM_SvcTWerSvcDisableStopped {
        Name        = 'WerSvc'
        StartupType = 'Disabled'
        State       = 'Stopped'
      }
      #Enable Windows Firewall File And Printer Sharing
      Script SYSTEM_EnableFileAndPrinterSharing {
        GetScript  = { }
        TestScript = { return $null -ne (Get-NetFirewallRule -DisplayGroup 'File And Printer Sharing' -Enabled True -ErrorAction SilentlyContinue | Where-Object { $_.Profile -eq 'Domain' }) }
        SetScript  = { Set-NetFirewallRule -DisplayGroup 'File And Printer Sharing' -Enabled True -Profile Domain }
      }
      #Enable Windows Firewall Remote Event Log Management
      Script SYSTEM_EnableRemoteEventLogManagement {
        GetScript  = { }
        TestScript = { return $null -ne (Get-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -ErrorAction SilentlyContinue | Where-Object { $_.Profile -eq 'Domain' }) }
        SetScript  = { Set-NetFirewallRule -DisplayGroup 'Remote Event Log Management' -Enabled True -Profile Any }
      }
      #Install the Remote Server Administration Tools for Active Directory Domain Services Tools
      WindowsFeature SYSTEM_ADS_Feature_RSAT-AD-Tools {
        Name                 = 'RSAT-AD-Tools'
        IncludeAllSubFeature = $true
        Ensure               = 'Present'
      }
      # Configure the DNS client server address on the primary IPv4 NIC.
      # The interface alias is resolved at APPLY time on the target node so
      # the config works on Azure VMs, Hyper-V and bare metal with any NIC
      # naming. An optional $Node.InterfaceAlias override in the psd1 wins
      # when provided; otherwise we pick the NIC that holds the default IPv4
      # gateway (always the management NIC).
      $dnsServerAddress = $ConfigurationData.NonNodeData.ADS.DnsServerAddress
      $preferredAlias   = $Node.InterfaceAlias
      Script SYSTEM_DnsServerAddress_SetDNS {
        GetScript  = {
          @{ Result = (Get-DnsClientServerAddress -AddressFamily IPv4 |
              Select-Object InterfaceAlias, ServerAddresses) }
        }
        TestScript = {
          $alias = if (-not [string]::IsNullOrWhiteSpace($using:preferredAlias)) {
            $using:preferredAlias
          }
          else {
            (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
              Select-Object -First 1 -ExpandProperty InterfaceAlias)
          }
          if ([string]::IsNullOrWhiteSpace($alias)) { return $false }
          $current = (Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 `
              -ErrorAction SilentlyContinue).ServerAddresses
          return ($current -contains $using:dnsServerAddress)
        }
        SetScript  = {
          $alias = if (-not [string]::IsNullOrWhiteSpace($using:preferredAlias)) {
            $using:preferredAlias
          }
          else {
            (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } |
              Select-Object -First 1 -ExpandProperty InterfaceAlias)
          }
          if ([string]::IsNullOrWhiteSpace($alias)) {
            throw 'Unable to determine primary IPv4 interface alias (no default-gateway NIC found and no override in psd1).'
          }
          Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $using:dnsServerAddress
        }
      }
    }

    #For all servers with Active Directory Services Role
    Node $AllNodes.Where{ $_.IsPDCServer }.Nodename {
      #Install Active Directory Domain Services
      #Install Active Directory Domain Services feature
      WindowsFeature SYSTEM_ADS_Feature_AD-Domain-Services {
        Name   = 'AD-Domain-Services'
        Ensure = 'Present'
      }
      #Install DNS Server feature
      WindowsFeature SYSTEM_ADS_Feature_DNS {
        Name   = 'DNS'
        Ensure = 'Present'
      }
      #Install the Remote Server Administration Tools for DNS Server Tools
      WindowsFeature SYSTEM_ADS_Feature_RSAT-DNS-Server {
        Name   = 'RSAT-DNS-Server'
        Ensure = 'Present'
      }
      #Configure Active Directory Domain Services
      ADDomain SYSTEM_ADS_CreateADForest {
        DomainName                    = $ConfigurationData.NonNodeData.ADS.DomainName
        DomainNetbiosName             = $ConfigurationData.NonNodeData.ADS.DomainNetBIOSName
        Credential                    = $ADSETUP
        SafemodeAdministratorPassword = $ADSAFEMODE
        DatabasePath                  = 'C:\NTDS'
        LogPath                       = 'C:\NTDS'
        SysvolPath                    = 'C:\SYSVOL'
        DependsOn                     = '[WindowsFeature]SYSTEM_ADS_Feature_DNS'
      }
      #Reboot the server after creating the Active Directory Domain Services
      PendingReboot RebootOnSignalFromCreateADForest {
        Name      = 'RebootOnSignalFromCreateADForest'
        DependsOn = '[ADDomain]SYSTEM_ADS_CreateADForest'
      }
      #Wait for the Domain Controller to be ready
      # Runs on the DC itself right after promotion, as SYSTEM (already a domain
      # principal), so it validates the domain in the local computer context. Do
      # NOT pass a Credential here: that parameter is for a member/replica server
      # waiting for a REMOTE domain, and impersonating a domain service account
      # that this very configuration has not created yet (the ADUser resources
      # below DependOn this one) deadlocks with "user name or password is
      # incorrect" and loops WaitTimeout x RestartCount before failing.
      WaitForADDomain WaitForDCReady {
        DomainName   = $ConfigurationData.NonNodeData.ADS.DomainName
        WaitTimeout  = 300
        RestartCount = 3
        DependsOn    = '[PendingReboot]RebootOnSignalFromCreateADForest'
      }
      # Edge browser policies are optional and gated by $Node.ApplyEdgePolicies.
      # The OU / service-account / user-account provisioning further down is gated
      # only by $Node.IsADSServer so it always runs on the PDC, regardless of the
      # Edge toggle. (Previously both blocks shared a single combined gate, which
      # caused OUs and users to be skipped when ApplyEdgePolicies was $False.)
      if ($node.IsADSServer -and $node.ApplyEdgePolicies) {
        # Edge browser policies are declared in the psd1 (NonNodeData.EdgePolicies)
        # so they can be tuned per customer without touching this script.
        [System.Object[]] $EdgePolicies = $ConfigurationData.NonNodeData.EdgePolicies
        #Apply Edge policies - https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies
        Script ConfigureEdgePolicies {
          SetScript  = {
            $domain = Get-ADDomain -Current LocalComputer
            $registryKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge'
            $policies = $using:EdgePolicies
            $gpo = New-GPO -name 'Edge_browser'
            New-GPLink -Guid $gpo.Id -Target $domain.DistinguishedName -order 1

            foreach ($policy in $policies) {
              $key = $registryKey
              if ($true -eq $policy.policyCanBeRecommended) { $key += '\Recommended' }
              $valueType = if ($policy.policyValueValue -is [int]) { 'DWORD' } else { 'STRING' }
              Set-GPRegistryValue -Guid $gpo.Id -key $key -ValueName $policy.policyValueName -Type $valueType -value $policy.policyValueValue
            }
          }
          GetScript  = { return @{ 'Result' = 'false' } }
          TestScript = {
            $policy = Get-GPO -name 'Edge_browser' -ErrorAction SilentlyContinue
            if ($null -eq $policy) {
              return $false
            }
            else {
              return $true
            }
          }
        }
      }
      if ($node.IsADSServer) {
        #Create the Organizational Unit for the service accounts
        ADOrganizationalUnit SYSTEM_ADS_CreateServiceAccount_OU {
          Name                            = $svcOUActiveDirectoryPath.Split(',')[0].Substring(3)
          Path                            = $svcOUActiveDirectoryPath.Substring($svcOUActiveDirectoryPath.IndexOf(',') + 1)
          ProtectedFromAccidentalDeletion = $false
          Ensure                          = 'Present'
          DependsOn                       = "[WaitForADDomain]WaitForDCReady"
        }
        # Provision only the entries that are real domain service accounts.
        # Entries with IsAdAccount = $False (credential containers like ADSETUP,
        # ADSAFEMODE, Passphrase, or the per-certificate PFX-password containers
        # such as DscPullCert / SharePointCert / OfficeOnlineCert / SQLServerCert)
        # carry only a password and must not be created as AD users.
        # New entries default to AD provisioning unless IsAdAccount is set to $False
        # in Secrets.psd1 — no further edit needed in this file. See wiki.
        $serviceAccounts = $secretsData.serviceAccounts | Where-Object -FilterScript {
          $_.IsAdAccount -ne $false
        }
        # Pre-flight: ADUser keys on (DomainName + UserName). Two entries with
        # the same sAMAccountName cause an opaque "identical key properties"
        # MOF conflict. Fail fast here with a clear message instead.
        $samMap = @{}
        foreach ($sa in $serviceAccounts) {
          $sam = ($sa.Username -replace '.*\\', '').ToLowerInvariant()
          if ($samMap.ContainsKey($sam)) {
            throw ("Duplicate sAMAccountName '{0}' in Secrets.psd1 serviceAccounts (entries '{1}' and '{2}'). Each service account must have a unique Username." -f $sam, $samMap[$sam], $sa.Name)
          }
          $samMap[$sam] = $sa.Name
        }
        foreach ($serviceAccount in $serviceAccounts) {
          $username = "$($serviceAccount.Username)"
          $password = ConvertTo-SecureString $serviceAccount.Password -AsPlainText -Force
          [System.Management.Automation.PSCredential] $credential = New-Object -Typename System.Management.Automation.PSCredential -Argumentlist $username, $password
          #Create the service account
          ADUser "SYSTEM_ADS_CreateServiceAccount_$($serviceAccount.Name)" {
            DomainName           = $ConfigurationData.NonNodeData.ADS.DomainName
            Path                 = $svcOUActiveDirectoryPath
            UserName             = "$($serviceAccount.Username -replace '.*\\', '')"
            DisplayName          = "$($serviceAccount.DisplayName)"
            Description          = "$($serviceAccount.Description)"
            EmailAddress         = "$($serviceAccount.Username -replace '.*\\', '')@$($fullQualifiedDomainName)"
            UserPrincipalName    = "$($serviceAccount.Username -replace '.*\\', '')@$($fullQualifiedDomainName)"
            Password             = $credential
            PasswordNeverExpires = $true
            PasswordNeverResets  = $true
            PsDscRunAsCredential = $ADSETUP
            Ensure               = 'Present'
            DependsOn            = '[ADOrganizationalUnit]SYSTEM_ADS_CreateServiceAccount_OU'
          }
        }
        #Create the Organizational Unit for the user accounts
        ADOrganizationalUnit SYSTEM_ADS_CreateINT_OU {
          Name                            = $intOUActiveDirectoryPath.Split(',')[0].Substring(3)
          Path                            = $intOUActiveDirectoryPath.Substring($intOUActiveDirectoryPath.IndexOf(',') + 1)
          ProtectedFromAccidentalDeletion = $true
          Ensure                          = 'Present'
          DependsOn                       = "[WaitForADDomain]WaitForDCReady"
        }
        #Create all users accounts
        $userAccounts = $secretsData.users
        foreach ($userAccount in $userAccounts) {
          $username = "$($userAccount.Username)"
          $password = ConvertTo-SecureString $userAccount.Password -AsPlainText -Force
          [System.Management.Automation.PSCredential] $credential = New-Object -Typename System.Management.Automation.PSCredential -Argumentlist $username, $password
          #Create the service account
          ADUser "SYSTEM_ADS_CreateUserAccount_$($userAccount.Name)" {
            DomainName           = $ConfigurationData.NonNodeData.ADS.DomainName
            Path                 = $intOUActiveDirectoryPath
            UserName             = "$($userAccount.Username -replace '.*\\', '')"
            DisplayName          = "$($userAccount.DisplayName)"
            GivenName            = "$($userAccount.GivenName)"
            Surname              = "$($userAccount.SurName)"
            Description          = "$($userAccount.Description)"
            EmailAddress         = "$($userAccount.Username -replace '.*\\', '')@$($fullQualifiedDomainName)"
            UserPrincipalName    = "$($userAccount.Username -replace '.*\\', '')@$($fullQualifiedDomainName)"
            Password             = $credential
            PasswordNeverExpires = $true
            PasswordNeverResets  = $true
            PsDscRunAsCredential = $ADSETUP
            Ensure               = 'Present'
            DependsOn            = '[ADOrganizationalUnit]SYSTEM_ADS_CreateINT_OU'
          }
        }
      }
    }
    #For all servers with Active Directory Certificate Services Role
    Node $AllNodes.Where{ $_.IsADCServer }.Nodename {
      #Install Active Directory Certificate Services
      #Install Certificate Authority feature
      WindowsFeature SYSTEM_ADS_Feature_ADCS-Cert-Authority {
        Name      = 'ADCS-Cert-Authority'
        Ensure    = 'Present'
        DependsOn = '[WaitForADDomain]WaitForDCReady'
      }
      #Install Certificate Authority
      ADCSCertificationAuthority SYSTEM_ADS_CreateADCertificateAuthority {
        CAType           = 'EnterpriseRootCA'
        IsSingleInstance = 'Yes'
        Ensure           = 'Present'
        Credential       = $ADSETUP
        DependsOn        = '[WindowsFeature]SYSTEM_ADS_Feature_ADCS-Cert-Authority'
      }
      #Wait for the Certificate Authority to be ready
      $caRootName = "$($ConfigurationData.NonNodeData.ADS.DomainNetBIOSName)-$($node.NodeName)-CA"
      $caServerFQDN = "$($node.NodeName).$($ConfigurationData.NonNodeData.ADS.DomainName)"
      WaitForCertificateServices WaitAfterADCSProvisioning {
        CAServerFQDN         = "$($caServerFQDN)"
        CARootName           = "$($caRootName)"
        PsDscRunAsCredential = $ADSETUP
        DependsOn            = '[ADCSCertificationAuthority]SYSTEM_ADS_CreateADCertificateAuthority'
      }
      WindowsFeature SYSTEM_ADS_Feature_ADCS-ManagementTools {
        Name      = 'RSAT-ADCS-Mgmt'
        Ensure    = 'Present'
        DependsOn = '[ADCSCertificationAuthority]SYSTEM_ADS_CreateADCertificateAuthority'
      }
      #Create certificates
      $certificates = $ConfigurationData.NonNodeData.ADC.certificates
      foreach ($certificate in $certificates) {
        Certreq "SYSTEM_ADS_CreateCertificate$($certificate.Name)" {
          CARootName          = "$($caRootName)"
          CAServerFQDN        = "$($caServerFQDN)"
          Subject             = "$($certificate.Subject)"
          SubjectAltName      = "$($certificate.SubjectAlt)"
          FriendlyName        = "$($certificate.FriendlyName)"
          KeyLength           = '2048'
          Exportable          = $true
          ProviderName        = '"Microsoft RSA SChannel Cryptographic Provider"'
          OID                 = '1.3.6.1.5.5.7.3.1'
          KeyUsage            = '0xa0'
          CertificateTemplate = 'WebServer'
          AutoRenew           = $true
          Credential          = $ADSETUP
          DependsOn           = '[WaitForCertificateServices]WaitAfterADCSProvisioning'
        }
        #Export the certificate to a file
        CertificateExport "SYSTEM_ADS_ExportCER_$($certificate.Name)" {
          Type         = 'CERT'
          FriendlyName = "$($certificate.FriendlyName)"
          Path         = "$($certificate.CertPath)"
          DependsOn    = "[Certreq]SYSTEM_ADS_CreateCertificate$($certificate.Name)"
        }
        CertificateExport "SYSTEM_ADS_ExportPFX_$($certificate.Name)" {
          Type         = 'PFX'
          FriendlyName = "$($certificate.FriendlyName)"
          Path         = "$($certificate.PfxPath)"
          # Per-certificate PFX password: looked up from the matching entry
          # in Secrets.psd1 (Name = $certificate.Name, e.g. 'DscPullCert').
          # Fails fast at compile time if the entry is missing.
          Password     = (Get-Variable -Name $certificate.Name -ValueOnly)
          DependsOn    = "[Certreq]SYSTEM_ADS_CreateCertificate$($certificate.Name)"
        }
      }
    }
  }
  #Run the CfgAppPdc configuration with the provided ConfigurationData
  # Note: Import-PowerShellDataFile returns hashtables, so use ForEach-Object
  # (hashtable dot-syntax) instead of Select-Object -ExpandProperty.
  $nodeList = ($configurationData.AllNodes | Where-Object { $_.NodeName -ne '*' } | ForEach-Object { $_.NodeName }) -join ', '
  Write-Host ("[{0}] Compiling CfgAppPdc for node(s) : {1}" -f (Get-Date -Format 'o'), $nodeList)
  Write-Host ("[{0}] MOF output path            : {1}" -f (Get-Date -Format 'o'), $mofOutputPath)
  CfgAppPdc -ConfigurationData $ConfigurationData -OutputPath $mofOutputPath

  #Checksum the generated MOF files
  New-DscChecksum -Force -Path $mofOutputPath -verbose
  Write-Host ("[{0}] Compilation complete." -f (Get-Date -Format 'o'))
}
catch {
  # Preserve full error context (script, line number, exception message) before rethrowing.
  Write-Error -Message ("CfgAppPdc compilation failed at {0}:{1} - {2}" -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message) -ErrorAction Continue
  throw
}
