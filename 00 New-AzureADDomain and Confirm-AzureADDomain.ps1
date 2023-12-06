Import-Module AADInternals
Import-Module AzureAD

. .\config.ps1

$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier1Support")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"

    # first, use Global Admin account to delete domain if it already exists
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    Connect-AzureAD -AadAccessToken $at -AccountId $credentials["globalAdmin"].login | Out-Null

    $domain = $null
    try {
        $domain = Get-AzureADDomain -Name $fqdn -ErrorAction SilentlyContinue
    }
    catch {}
    if ($null -ne $domain) {
        Remove-AzureADDomain -Name $fqdn -ErrorAction SilentlyContinue
        
        # ensure it's applied
        do {
            Start-Sleep 2
            $domain = $null
            try {
                $domain = Get-AzureADDomain -Name $fqdn -ErrorAction SilentlyContinue
            }
            catch {}
        } while ($null -ne $domain)
        Start-Sleep 5
    }

    # now, log as target user and try adding the domain
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    Connect-AzureAD -AadAccessToken $at -AccountId $credentials[$role].login | Out-Null
    
    try {
        $domain = New-AzureADDomain -Name $fqdn -ErrorAction Stop
        Write-Host "[+] It worked :)"
        $domain | Format-Table
    }
    catch {
        Write-Host "[-] Didn't work :( -> '$($_.Exception.Message)'"
        continue
    }

    $verif = Get-AzureADDomainVerificationDnsRecord -Name $fqdn | Where-Object { $_.Text }
    Write-Host "Create this TXT record '$($verif.Text)' on '$($verif.Label)'"
    
    do {
        Start-Sleep 5
        $confirmation = $null
        try {
            $confirmation = Confirm-AzureADDomain -Name $fqdn -ErrorAction SilentlyContinue
        }
        catch {}
    } while ($null -eq $confirmation -or $confirmation.AvailabilityStatus -ne "AvailableImmediately")
    Write-Host "[+] Confirmation OK: $($confirmation.AvailabilityStatus)"
}