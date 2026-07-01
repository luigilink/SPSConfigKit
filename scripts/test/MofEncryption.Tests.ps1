<#
.SYNOPSIS
  Pester (v5) guard-rail that fails if a compiled MOF still contains plain-text
  credentials — i.e. verifies that DSC document-encryption is actually in effect.

.DESCRIPTION
  Designed to be invoked through scripts/test/Invoke-MofEncryptionTest.ps1, which
  builds a Pester container with -Data @{ MofPath = ... }. MofPath may be a single
  .mof file or a folder; every *.mof (excluding *.meta.mof) is checked.

  For each MOF the suite asserts:
    * every credential `Password = "..."` value is a CMS-encrypted blob
      (starts with '-----BEGIN CMS-----'), never a clear-text secret;
    * when at least one credential is present, the ConfigurationDocument footer
      declares ContentType="PasswordEncrypted".

  This catches the single most dangerous mistake in a DSC v1/v2 workflow: shipping
  a MOF whose credentials were compiled in clear text because the wildcard
  PSDscAllowPlainTextPassword was left $true or the encryption certificate wasn't
  wired in (see scripts/init/Initialize-DscEncryption.ps1).

.NOTES
  Requires Pester 5.0 or later.
#>

#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

[CmdletBinding()]
param
(
  [Parameter(Mandatory = $true)]
  [string] $MofPath
)

BeforeDiscovery {
  if (-not (Test-Path -LiteralPath $MofPath)) {
    throw "MofPath not found: $MofPath"
  }
  $item = Get-Item -LiteralPath $MofPath
  if ($item.PSIsContainer) {
    $mofFiles = @(Get-ChildItem -LiteralPath $MofPath -Filter '*.mof' -File |
        Where-Object { $_.Name -notlike '*.meta.mof' } |
        ForEach-Object { $_.FullName })
  }
  else {
    $mofFiles = @($item.FullName)
  }
}

BeforeAll {
  # Extract every quoted Password value from a MOF and classify it.
  function script:Get-MofPassword {
    param([string] $Text)
    $rx = [regex]::new('Password\s*=\s*"(?<val>(?:[^"\\]|\\.)*)"',
      [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($m in $rx.Matches($Text)) {
      $val = $m.Groups['val'].Value
      [pscustomobject]@{
        Encrypted = $val.StartsWith('-----BEGIN CMS-----')
        Preview   = if ($val.Length -gt 24) { $val.Substring(0, 24) + '…' } else { $val }
      }
    }
  }
}

Describe 'MOF <_>' -ForEach $mofFiles {
  BeforeAll {
    $script:MofFile = $_
    $script:MofText = Get-Content -LiteralPath $_ -Raw
    $script:Passwords = @(script:Get-MofPassword -Text $script:MofText)
  }

  It 'contains no clear-text credential (every Password is a CMS blob)' {
    $plain = @($script:Passwords | Where-Object { -not $_.Encrypted })
    $plain.Count | Should -Be 0 -Because (
      "each credential in a compiled MOF must be encrypted with the DSC " +
      "document-encryption certificate. Clear-text found: " +
      (($plain | ForEach-Object { $_.Preview }) -join ', ') +
      ". Run scripts/init/Initialize-DscEncryption.ps1 and recompile."
    )
  }

  It 'declares ContentType="PasswordEncrypted" when credentials are present' {
    if ($script:Passwords.Count -eq 0) {
      Set-ItResult -Skipped -Because 'this MOF carries no credentials'
      return
    }
    $script:MofText | Should -Match 'ContentType\s*=\s*"PasswordEncrypted"' -Because (
      'a MOF carrying credentials must be marked PasswordEncrypted so the LCM ' +
      'decrypts them with the node certificate.'
    )
  }
}
