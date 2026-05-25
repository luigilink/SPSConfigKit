#Requires -Version 5.1

<#
.SYNOPSIS
    Bootstraps DSC document-encryption for SPSConfigKit configurations.

.DESCRIPTION
    Generates (or reuses) a self-signed Document Encryption certificate on the
    authoring host, exports the public .cer (and an optional password-protected
    .pfx) to a shared folder, then patches every Cfg*.psd1 in the repository
    by updating the wildcard '*' AllNodes block so it carries:
        PSDscAllowPlainTextPassword = $false
        CertificateFile             = '<NodeCertImportPath>'
        Thumbprint                  = '<thumbprint>'

    Because the values live on the wildcard block, every named node inherits
    them automatically; no per-node duplication.

    Once the patch is applied, recompiling any Cfg*.ps1 produces a MOF whose
    credential blobs are encrypted with the certificate's public key and can
    only be decrypted by the target node holding the private key.

    Re-running is safe:
      * An existing cert with the same Subject is reused (use -Force to rotate).
      * Wildcard blocks that already carry CertificateFile / Thumbprint have
        their values refreshed in place (no duplicates).
      * PSDscAllowPlainTextPassword is always set to $false (the whole point).
      * A .bak copy of each psd1 is created the first time it is patched.

.PARAMETER SourcePath
    UNC or local folder that receives the exported certificate files AND that
    each node will read at compile time. Default: \\PDC1\Softwarepackages

.PARAMETER CertSubject
    Subject (CN=...) of the self-signed certificate. Default: 'DSC Encryption'.

.PARAMETER CertFileName
    File name (no path) for the exported public certificate.
    Default: 'DscEncryption.cer'. The .pfx uses the same base name.

.PARAMETER PfxPassword
    Optional SecureString used to export a password-protected .pfx alongside
    the .cer. Omit to skip PFX export (nodes will then need an alternate path
    for receiving the private key).

.PARAMETER NodeCertImportPath
    Path written into each patched psd1 as CertificateFile. The DSC authoring
    host must be able to read this path at compile time.
    Defaults to "$SourcePath\$CertFileName".

.PARAMETER NoPatch
    Generate / export the cert but skip the psd1 patching pass.

.PARAMETER Force
    Remove any existing cert with the same Subject and create a fresh one.
    Existing CertificateFile / Thumbprint lines in patched psd1 files are
    refreshed to the new thumbprint.

.EXAMPLE
    .\Initialize-DscEncryption.ps1

    Reuses or creates the cert, exports only the .cer to \\PDC1\Softwarepackages,
    and patches every Cfg*.psd1 found in the repo.

.EXAMPLE
    $pfxPwd = Read-Host 'PFX password' -AsSecureString
    .\Initialize-DscEncryption.ps1 -PfxPassword $pfxPwd -Force

    Rotates the cert, exports both the public .cer and a password-protected .pfx,
    and refreshes the wildcard '*' block in every Cfg*.psd1.

.NOTES
    Runs on Windows only (uses the Cert: drive and New-SelfSignedCertificate).

    On EACH target node, after the .pfx is available:
        Import-PfxCertificate -FilePath '\\PDC1\Softwarepackages\DscEncryption.pfx' `
            -CertStoreLocation Cert:\LocalMachine\My `
            -Password (Read-Host 'PFX password' -AsSecureString)

    Then recompile the appropriate Cfg*.ps1 to produce encrypted MOFs.
#>

[CmdletBinding()]
param(
    [string]       $SourcePath         = '\\PDC1\Softwarepackages',
    [string]       $CertSubject        = 'DSC Encryption',
    [string]       $CertFileName       = 'DscEncryption.cer',
    [SecureString] $PfxPassword,
    [string]       $NodeCertImportPath,
    [switch]       $NoPatch,
    [switch]       $Force
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------

if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.OS -notlike '*Windows*') {
    throw "Initialize-DscEncryption.ps1 must run on Windows (uses Cert:\ and New-SelfSignedCertificate)."
}

if (-not $NodeCertImportPath) {
    $NodeCertImportPath = Join-Path -Path $SourcePath -ChildPath $CertFileName
}

$pfxFileName = [System.IO.Path]::ChangeExtension($CertFileName, 'pfx')
$cerOutPath  = Join-Path -Path $SourcePath -ChildPath $CertFileName
$pfxOutPath  = Join-Path -Path $SourcePath -ChildPath $pfxFileName

# ---------------------------------------------------------------------------
# 1) Locate or create the self-signed Document Encryption certificate
# ---------------------------------------------------------------------------

$existing = Get-ChildItem -Path Cert:\LocalMachine\My |
    Where-Object {
        $_.Subject -eq "CN=$CertSubject" -and
        $_.HasPrivateKey -and
        ($_.EnhancedKeyUsageList | Where-Object { $_.ObjectId -eq '1.3.6.1.4.1.311.80.1' })
    } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

if ($existing -and -not $Force) {
    Write-Host "[*] Reusing existing certificate"
    Write-Host "    Thumbprint : $($existing.Thumbprint)"
    Write-Host "    NotAfter   : $($existing.NotAfter)"
    $cert = $existing
}
else {
    if ($existing -and $Force) {
        Write-Host "[*] -Force specified: removing existing cert $($existing.Thumbprint)"
        Remove-Item -Path "Cert:\LocalMachine\My\$($existing.Thumbprint)" -Force
    }

    Write-Host "[*] Creating new self-signed Document Encryption certificate (CN=$CertSubject)..."
    # Minimal invocation per Microsoft docs (avoids the CSP / smart-card UI):
    #   https://learn.microsoft.com/en-us/powershell/dsc/pull-server/securemof
    # -Type DocumentEncryptionCertLegacyCsp already sets the right EKU
    # (1.3.6.1.4.1.311.80.1) and the legacy CSP key spec; adding -KeyUsage or
    # -KeyAlgorithm causes a key-spec mismatch that prompts for a smart card.
    $cert = New-SelfSignedCertificate `
        -Type              DocumentEncryptionCertLegacyCsp `
        -Subject           "CN=$CertSubject" `
        -HashAlgorithm     SHA256 `
        -NotAfter          ((Get-Date).AddYears(10)) `
        -CertStoreLocation Cert:\LocalMachine\My
    Write-Host "[+] Created  Thumbprint=$($cert.Thumbprint)"
    Write-Host "             NotAfter  =$($cert.NotAfter)"
}

$thumb = $cert.Thumbprint

# ---------------------------------------------------------------------------
# 2) Ensure SourcePath is reachable and export the public .cer
# ---------------------------------------------------------------------------

if (-not (Test-Path -Path $SourcePath)) {
    try {
        New-Item -ItemType Directory -Path $SourcePath -Force | Out-Null
        Write-Host "[+] Created folder $SourcePath"
    }
    catch {
        throw "Cannot create or reach SourcePath '$SourcePath': $($_.Exception.Message)"
    }
}

Export-Certificate -Cert $cert -FilePath $cerOutPath -Force | Out-Null
Write-Host "[+] Exported public certificate -> $cerOutPath"

# ---------------------------------------------------------------------------
# 3) Optionally export the private .pfx
# ---------------------------------------------------------------------------

if ($PfxPassword) {
    Export-PfxCertificate -Cert $cert -FilePath $pfxOutPath -Password $PfxPassword -Force | Out-Null
    Write-Host "[+] Exported private key (.pfx) -> $pfxOutPath"
}
else {
    Write-Host "[i] -PfxPassword not supplied: .pfx export skipped."
}

# ---------------------------------------------------------------------------
# 4) Patch every Cfg*.psd1 in the repository
# ---------------------------------------------------------------------------

if ($NoPatch) {
    Write-Host ""
    Write-Host "[i] -NoPatch specified: leaving psd1 files untouched."
    return
}

# Repo layout: <repo>\scripts\init\Initialize-DscEncryption.ps1
$scriptsRoot = Split-Path -Path $PSScriptRoot -Parent
$psd1Files   = Get-ChildItem -Path $scriptsRoot -Recurse -Filter 'Cfg*.psd1' -File

Write-Host ""
Write-Host "[*] Patching $($psd1Files.Count) psd1 file(s) under $scriptsRoot..."

# Match the wildcard '*' AllNodes block. All current wildcard blocks are flat
# (no nested @{...}), so [^{}] safely stops at the block's closing brace.
$rxWild = [System.Text.RegularExpressions.Regex]::new(
    "@\{(?<body>[^{}]*?NodeName\s*=\s*'\*'[^{}]*?)\}",
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)

$certPathLit = $NodeCertImportPath -replace "'", "''"
$thumbLit    = $thumb

foreach ($file in $psd1Files) {
    $text  = Get-Content -Path $file.FullName -Raw
    $match = $rxWild.Match($text)

    if (-not $match.Success) {
        Write-Host ("  [!] {0,-60} no wildcard '*' AllNodes block found" -f $file.FullName)
        continue
    }

    $body = $match.Groups['body'].Value

    # Step 1: force PSDscAllowPlainTextPassword = $false (insert if absent).
    if ($body -match '(?m)^(?<lead>\s*PSDscAllowPlainTextPassword\s*=\s*)\$\w+') {
        $body = $body -replace '(?m)^(?<lead>\s*PSDscAllowPlainTextPassword\s*=\s*)\$\w+', '${lead}$false'
    }

    # Step 2: refresh existing CertificateFile / Thumbprint or insert before }.
    $hasCert  = $body -match '(?m)^\s*CertificateFile\s*='
    $hasThumb = $body -match '(?m)^\s*Thumbprint\s*='

    if ($hasCert -and $hasThumb) {
        $newLines = foreach ($line in ($body -split "`r?`n")) {
            if ($line -match '^(?<lead>\s*CertificateFile\s*=\s*)') {
                "$($Matches.lead)'$certPathLit'"
            }
            elseif ($line -match '^(?<lead>\s*Thumbprint\s*=\s*)') {
                "$($Matches.lead)'$thumbLit'"
            }
            else {
                $line
            }
        }
        $body = $newLines -join "`r`n"
    }
    elseif ($hasCert -or $hasThumb) {
        Write-Warning "Wildcard block in $($file.FullName) has partial cert metadata; leaving as-is."
    }
    else {
        # Detect indentation from the last non-empty key line and the closing brace.
        $bodyLines   = $body -split "`r?`n"
        $closeIndent = $bodyLines[-1]
        $keyIndent   = '      '
        for ($i = $bodyLines.Count - 2; $i -ge 0; $i--) {
            if ($bodyLines[$i].Trim()) {
                if ($bodyLines[$i] -match '^(?<lead>\s+)\S') { $keyIndent = $Matches.lead }
                break
            }
        }
        $trimBody = $body -replace '\s+$', ''
        $body     = "$trimBody`r`n${keyIndent}CertificateFile = '$certPathLit'`r`n${keyIndent}Thumbprint      = '$thumbLit'`r`n${closeIndent}"
    }

    $newBlock = "@{${body}}"
    $newText  = $text.Substring(0, $match.Index) + $newBlock + $text.Substring($match.Index + $match.Length)

    if ($newText -ne $text) {
        $bak = "$($file.FullName).bak"
        if (-not (Test-Path -Path $bak)) {
            Copy-Item -Path $file.FullName -Destination $bak
        }
        Set-Content -Path $file.FullName -Value $newText -Encoding UTF8 -NoNewline
        Write-Host ("  [+] {0,-60} wildcard '*' block updated" -f $file.FullName)
    }
    else {
        Write-Host ("  [-] {0,-60} already up to date" -f $file.FullName)
    }
}

# ---------------------------------------------------------------------------
# 5) Next-steps banner
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host " DSC encryption bootstrap complete"
Write-Host "============================================================"
Write-Host " Thumbprint        : $thumb"
Write-Host " Public cert (.cer): $cerOutPath"
if ($PfxPassword) {
    Write-Host " Private key (.pfx): $pfxOutPath"
}
Write-Host " Per-node path     : $NodeCertImportPath"
Write-Host ""
Write-Host " NEXT STEPS"
Write-Host " ----------"
Write-Host " 1. On EACH target node, import the cert WITH its private key:"
Write-Host "      Import-PfxCertificate -FilePath '$pfxOutPath' ``"
Write-Host "          -CertStoreLocation Cert:\LocalMachine\My ``"
Write-Host "          -Password (Read-Host 'PFX password' -AsSecureString)"
Write-Host ""
Write-Host " 2. Recompile any Cfg*.ps1; the new MOFs will hold encrypted"
Write-Host "    credentials only decryptable by the holder of the private key."
Write-Host ""
Write-Host "    Note: PSDscAllowPlainTextPassword has been set to `$false on the"
Write-Host "    wildcard '*' block, so compilation will FAIL until every target"
Write-Host "    node has imported the .pfx into Cert:\LocalMachine\My."
Write-Host "============================================================"
