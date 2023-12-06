Import-Module AADInternals
Import-Module MSOnline

. .\config.ps1

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Error "MSOL isn't compatible with PowerShell 7+. Try again with PowerShell 5"
    return
}

$roles = @("globalAdmin", "securityAdmin", "hybridIdentityAdmin", "externalIdentityProviderAdmin", "domainNameAdmin", "partnerTier1Support", "partnerTier2Support")
# $roles = @("partnerTier2Support")

foreach ($role in $roles) {
    Write-Host "---------------------- $role"
    $fqdn = "$role.$custom_domain_suffix"

    # first, use Global Admin account to delete domain if it already exists
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials["globalAdmin"].login, (ConvertTo-SecureString -String $credentials["globalAdmin"].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg

    $domain = $null
    $domain = Get-MsolDomain -DomainName $fqdn -ErrorAction SilentlyContinue
    if ($null -ne $domain) {
        Remove-MsolDomain -DomainName $fqdn -Force -ErrorAction SilentlyContinue
        
        # ensure it's applied
        do {
            Start-Sleep 2
            $domain = $null
            $domain = Get-MsolDomain -DomainName $fqdn -ErrorAction SilentlyContinue
        } while ($null -ne $domain)
        Start-Sleep 5
    }

    # now, log as target user and try adding the domain
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $credentials[$role].login, (ConvertTo-SecureString -String $credentials[$role].password -AsPlainText -Force)
    $at = Get-AADIntAccessTokenForAADGraph -Credentials $Credential
    $atg = Get-AADIntAccessTokenForMSGraph -Credentials $Credential
    Connect-MsolService -AdGraphAccessToken $at -MsGraphAccessToken $atg

    try {
        $domain = New-MsolDomain -Name $fqdn -ErrorAction Stop
        Write-Host "[+] It worked :)"
        $domain | Format-Table
    }
    catch {
        Write-Host "[-] Didn't work :( -> '$($_.Exception.Message)'"
        continue
    }
    
    $verif = Get-MsolDomainVerificationDns -DomainName $fqdn -Mode DnsTxtRecord
    Write-Host "Create this TXT record '$($verif.Text)' on '$($verif.Label)'"

    do {
        Start-Sleep 5
        $confirmation = Confirm-MsolDomain -DomainName $fqdn -ErrorAction SilentlyContinue
    } while ($confirmation.Availability -ne "AvailableImmediately")
    Write-Host "[+] Confirmation OK: $($confirmation.AvailabilityDetails)"
}