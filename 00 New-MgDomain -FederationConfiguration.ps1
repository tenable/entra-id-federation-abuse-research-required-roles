Import-Module AADInternals

. .\config.ps1

# DOES NOT WORK :(



$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier1Support")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"

    # first, use Global Admin account to delete domain if it already exists
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    $atg_secure = ConvertTo-SecureString $atg -AsPlainText -Force
    Connect-MgGraph -AccessToken $atg_secure | Out-Null

    $domain = $null
    $domain = Get-MgDomain -DomainId $fqdn -ErrorAction SilentlyContinue
    if ($null -ne $domain) {
        Remove-MgDomain -DomainId $fqdn -ErrorAction SilentlyContinue
        
        # ensure it's applied
        do {
            Start-Sleep 2
            $domain = $null
            $domain = Get-MgDomain -DomainId $fqdn -ErrorAction SilentlyContinue
        } while ($null -ne $domain)
        Start-Sleep 5
    }

    # now, log as target user and try adding the domain
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    $atg_secure = ConvertTo-SecureString $atg -AsPlainText -Force
    Connect-MgGraph -AccessToken $atg_secure | Out-Null
    
    $federationConfiguration = @{
        Id                              = $fqdn;
        ActiveSignInUri                 = "https://example.com/something";
        IssuerUri                       = "https://$fqdn/$('{0:X}' -f (Get-Date).GetHashCode())";
        MetadataExchangeUri             = "https://example.net/something";
        PassiveSignInUri                = "https://example.net/something";
        SignOutUri                      = "https://example.net/something";
        DisplayName                     = "some example";
        FederatedIdpMfaBehavior         = "acceptIfMfaDoneByFederatedIdp";
        SigningCertificate              = $benign_cert;
        PreferredAuthenticationProtocol = "wsFed";
        PromptLoginBehavior             = "nativeSupport";
        # isSignedAuthenticationRequestRequired = $null;
        # signingCertificateUpdateStatus = $null;
        # nextSigningCertificate = $null;
    }

    try {
        $domain = New-MgDomain -Id $fqdn `
            -FederationConfiguration $federationConfiguration `
            -ErrorAction Stop
        Write-Host "[+] It worked :)"
        $domain | Format-Table
    }
    catch {
        Write-Host "[-] Didn't work :( -> '$($_.Exception.Message)'"
        continue
    }
}