# Use PowerShell 7 to get better error management
Import-Module AADInternals

. .\config.ps1


$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier1Support")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"

    # first, use Global Admin account to add federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
        
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    $atg_secure = ConvertTo-SecureString $atg -AsPlainText -Force
    Connect-MgGraph -AccessToken $atg_secure | Out-Null

    # delete any federation config
    $configs = $null
    $configs = Get-MgDomainFederationConfiguration -DomainId $fqdn -ErrorAction SilentlyContinue
    if ($configs) {
        Remove-MgDomainFederationConfiguration -DomainId $fqdn -InternalDomainFederationId $configs.Id
        #Write-Host "Deleted config"
    }

    # add one
    $firstDisplayName = "created by GA"
    try {
        $newconf = New-MgDomainFederationConfiguration `
            -DomainId $fqdn `
            -ActiveSignInUri "https://example.com/something" `
            -IssuerUri "https://$fqdn/$('{0:X}' -f (Get-Date).GetHashCode())" `
            -MetadataExchangeUri "https://example.net/something" `
            -PassiveSignInUri "https://example.net/something" `
            -SignOutUri "https://example.net/something" `
            -DisplayName $firstDisplayName `
            -FederatedIdpMfaBehavior "acceptIfMfaDoneByFederatedIdp" `
            -SigningCertificate $benign_cert `
            -ErrorAction Stop
        
        if ($null -ne $newconf) {
            #Write-Host "Added new config: $($newconf.Id) with DisplayName=$firstDisplayName"
        }
    }
    catch {
        Write-Host "[!] New-MgDomainFederationConfiguration: $_"
    }


    # now log as target user and try deleting federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    $atg_secure = ConvertTo-SecureString $atg -AsPlainText -Force
    Connect-MgGraph -AccessToken $atg_secure | Out-Null

    # wait until the new federation config is taken into account
    do {
        try {
            $foundconf = $null
            $foundconf = Get-MgDomainFederationConfiguration -DomainId $fqdn -InternalDomainFederationId $newconf.Id -ErrorAction Stop
        }
        catch {
            #Write-Host "[.] Waiting..."
            Start-Sleep 2
        }
    } until ($null -ne $foundconf)
    # just in case
    Start-Sleep 5

    try {
        Remove-MgDomainFederationConfiguration `
            -DomainId $fqdn `
            -InternalDomainFederationId $newconf.Id `
            -ErrorAction Stop
        
        Write-Host "[+] It worked :) Federation config was deleted"
    }
    catch {
        Write-Host "[!] Remove-MgDomainFederationConfiguration: $_"
        Write-Host "[-] Didn't work :( Couldn't delete federation config"
    }
}
