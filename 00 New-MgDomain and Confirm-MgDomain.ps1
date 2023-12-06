Import-Module AADInternals

. .\config.ps1

$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier2Support")

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
    
    try {
        $domain = New-MgDomain -Id $fqdn -ErrorAction Stop
        Write-Host "[+] It worked :)"
        $domain | Format-Table
    }
    catch {
        Write-Host "[-] Didn't work :( -> '$($_.Exception.Message)'"
        continue
    }

    $verif = Get-MgDomainVerificationDnsRecord -DomainId $fqdn -Filter "RecordType eq 'Txt'"
    Write-Host "Create this TXT record '$($verif.AdditionalProperties.text)' on '$($verif.Label)'"
    
    do {
        Start-Sleep 5
        $confirmation = Confirm-MgDomain -DomainId $fqdn -ErrorAction SilentlyContinue
    } while ($confirmation.AvailabilityStatus -ne "AvailableImmediately")
    Write-Host "[+] Confirmation OK: $($confirmation.AvailabilityStatus)"
}