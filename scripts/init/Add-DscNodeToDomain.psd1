@{
  # Fully-qualified Active Directory domain the node should join, e.g.
  # 'contoso.com'. Must match the domain created by the PDC configuration
  # (NonNodeData.ADS.DomainName).
  DomainName  = 'contoso.com'

  # DNS server IP address(es) to set on the node's active adapter(s) BEFORE the
  # join. On a cloud VM (for example Azure, whose default DNS is 168.63.129.16)
  # this must be the domain controller IP(s) so the domain can be resolved.
  # Sample value matches the PDC's DnsServerAddress in scripts\pdc\CfgAppPdc.psd1.
  # Leave as @() to keep the current DNS configuration untouched (on-prem or
  # VMware nodes whose DNS already resolves the domain).
  DnsServers  = @('10.1.1.4')

  # Optional distinguished name of the OU the computer object should be created
  # in, e.g. 'OU=Servers,DC=contoso,DC=com'. Empty string = default Computers
  # container.
  OUPath      = ''

  # Name of the Secrets.psd1 serviceAccounts entry whose credential is used to
  # join the domain. ADSETUP is already a domain account with the rights to add
  # computers, so it is reused here.
  JoinAccount = 'ADSETUP'

  # Restart the node after a successful join. A reboot is required to complete
  # domain membership before the node's DSC configuration is applied. Set to
  # $false to reboot manually / orchestrate the restart yourself.
  Restart     = $true
}
