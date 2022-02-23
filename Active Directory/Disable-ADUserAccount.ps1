<#
.SYNOPSIS
    Disables a terminated user in AD
.DESCRIPTION
    The Disable-ADUserAccount.ps1 script will take the supplied username, and then fully disable, remove groups,
    clear fields, and more.

    The most simple way to run this is to just supply the short username after the script name. This will then
    search Active Directory for a match, then confirm with you before proceeding.

    If you don't know the shortname, you could also try a part (or all) of a user's real name. The script will
    run a wildcard search after anything that is entered. If it returns multiple names, then it will print all the
    results with their full name, samAccountName, and UserPrincipalName.

    Searching on the samAccountName is always an exact match, so re-run the script providing that value from the
    list that was returned.

    Output in Yellow means that the script is doing that task, green means that it is done. Certain tasks will
    always be green as it might not be obvious that it was already done (such as a password reset).
.EXAMPLE
    PS C:\> ./Disable-ADUserAccount.ps1 teus

    Runs the script and searches for "Test User" by supplying the first couple letters from first and last name.
.NOTES
    General notes
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$User,

    [string]$Server,

    [string]$DisabledGroup,

    [string]$DisabledOU,

    [string[]]$IgnoreGroups
)


#----------------[ Functions ]------------------


function Read-HostYN {
    param ([string]$Question)

    do {
        switch -regex (Read-Host $Question'? [Y]es/[N]o') {
            'y$|yes$' { return $true }
            'n$|no$' { return $False }
            Default { Write-Output 'Sorry, [Y]es or [N]o only' }
        }
    } while ($true)
}


#----------------[ Main Execution ]---------------


$ConfigPath = Join-Path $PSScriptRoot 'config.json'

if (Test-Path $ConfigPath) {
    try { $Config = Get-Content $ConfigPath -ErrorAction Stop | ConvertFrom-Json }
    catch {
        Write-Warning "Couldn't read the config file."
        return
    }
}

@(
    'Server'
    'DisabledGroup'
    'DisabledOU'
    'IgnoreGroups'
) | ForEach-Object {
    if (-not $PSBoundParameters.ContainsKey($_) -and $Config.($_)) { Set-Variable -Name $_ -Value $Config.($_) }
}

if (!$Server) { $Server = Read-Host "Enter the name of the AD server to connect to" }

Write-Host "Testing connection to `"$Server`""
try { $null = Test-Connection -ComputerName $Server -Count 1 -ErrorAction Stop }
catch {
    Write-Warning "Couldn't reach $Server, are you connected to the VPN?"
    return
}

if (!$ADCredentials) { $Global:ADCredentials = Get-Credential -Message "Enter your Admin account credentials" }

$ScriptBlock = {
    try { $Result = Get-ADUser -Identity $Using:User -ErrorAction SilentlyContinue }
    catch { }

    if (!$Result) {
        try { $Result = Get-ADUser -Filter "Name -like `"*$Using:User*`"" -ErrorAction SilentlyContinue }
        catch { }
    }

    $Result
}

Write-host "Attempting to get AD account for `"$User`""
try { $ADUser = Invoke-Command -ComputerName $Server -Credential $ADCredentials -ScriptBlock $ScriptBlock -ErrorAction Stop }
catch { throw $_ }

if (!$ADUser) {
    Write-Warning "Unable to locate an account for `"$User`", please check the name and try again."
    return
}
elseif ($ADUser.Count -gt 1) {
    Write-Host "Found the following accounts:"
    $ADUser | Select-Object -Property Name, SamAccountName | Sort-Object -Property Name | Out-Host
    Write-Warning "Found $($ADUser.Count) matches, consider using SamAccountName from the list above."
    return
}

Write-Host "Found account:"
$ADUser | Select-Object -Property Name, SamAccountName, UserPrincipalName | Out-Host

if (-not (Read-HostYN -Question "Is this the correct account")) {
    Write-Host "Exiting..."
    return
}

# https://gist.github.com/marcgeld/4891bbb6e72d7fdb577920a6420c1dfb
$NewPassword = -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 15 | ForEach-Object { [char]$_ })

$ScriptBlock2 = {
    $ADUser = Get-ADUser -Identity $Using:ADUser.SamAccountName -Properties *
    $DisableGroupName = $Using:Config.DisabledGroup
    $DisabledOUName = $Using:Config.DisabledOU
    $IgnoreGroups = $Using:Config.IgnoreGroups

    # Disable account
    if ($ADUser.Enabled) {
        Write-Host "- Disabling AD account" -ForegroundColor Yellow
        try { $ADUser | Disable-ADAccount -ErrorAction Stop }
        catch { throw $_ }
    }
    Write-Host "- AD account disabled" -ForegroundColor Green

    # Reset password
    try { $ADUser | Set-ADAccountPassword -Reset -NewPassword ($Using:NewPassword | ConvertTo-SecureString -AsPlainText -Force) }
    catch { throw $_ }
    Write-Host "- Reset password: $Using:NewPassword" -ForegroundColor Green

    # Clear out these fields
    $ClearFields = @(
        'Title'
        'Department'
        'Company'
        'Manager'
        'physicalDeliveryOfficeName'
        'telephoneNumber'
        'pager'
        'mobile'
        'ipPhone'
        'HomePhone'
        'extensionAttribute10'
    )

    try { $ADUser | Set-ADUser -Clear $ClearFields -ErrorAction Stop }
    catch { throw $_ }
    Write-Host "- Cleared fields: $($ClearFields -join ', ')" -ForegroundColor Green

    # Set the description
    if ($ADUser.Description -notmatch '\d{4}-\d{2}-\d{2}') {
        Write-Host "- Setting Description field" -ForegroundColor Green
        $Date = Get-Date -Format 'yyyy-MM-dd'
        try { $ADUser | Set-ADUser -Description $Date -ErrorAction Stop }
        catch { throw $_ }
    }
    Write-Host "- Description field set: $($ADUser.Description)" -ForegroundColor Green

    # Add user to the Disabled group
    $Groups = $ADUser | Get-ADPrincipalGroupMembership
    $DisabledGroup = Get-ADGroup -Identity $DisableGroupName -Properties PrimaryGroupToken
    if ($Groups.name -notcontains $DisableGroupName ) {
        Write-Host "- Adding to disable group" -ForegroundColor Yellow
        try { $DisabledGroup | Add-ADGroupMember -Members $ADUser.SamAccountName -ErrorAction Stop }
        catch { throw $_ }
    }
    Write-Host "- Added to `"$DisableGroupName`" group" -ForegroundColor Green

    # Set the primary group
    if ($ADUser.primaryGroupID -ne $DisabledGroup.PrimaryGroupToken) {
        Write-Host "- Setting primary group" -ForegroundColor Yellow
        try { $ADUser | Set-ADUser -replace @{primaryGroupID = $DisabledGroup.primaryGroupToken } }
        catch { throw $_ }
    }
    Write-Host "- Primary group set to: `"$DisableGroupName`"" -ForegroundColor Green

    # Remove all other groups
    foreach ($Group in $Groups) {
        if ($Group.SID -eq $DisabledGroup.SID) { continue }
        if ($IgnoreGroups -contains $Group.Name) { continue }

        try {
            Write-Host "- Removing group: $($Group.name)" -ForegroundColor Yellow
            Remove-ADGroupMember -Identity $Group.SID -Members $ADUser.SamAccountName -Confirm:$FALSE -ErrorAction Stop
        }
        catch { throw $_ }
    }
    Write-Host "- Removed all groups" -ForegroundColor Green

    # Network access permission: Deny Acess
    try { $ADUser | Set-ADUser -Replace @{msNPAllowDialIn = $FALSE } -ErrorAction Stop }
    catch { throw $_ }
    Write-Host "- Set Network access Permission to Deny Access" -ForegroundColor Green

    # Move user to Disabled > Disabled Users
    $DestinationOU = Get-ADOrganizationalUnit -filter "name -eq '$DisabledOUName'"
    if ($ADUser.DistinguishedName -notmatch $DestinationOU.DistinguishedName) {
        try {
            Write-Host "- Moving AD account to `"$DisabledOUName`" OU" -ForegroundColor Yellow
            $ADUser | Move-ADObject -TargetPath $DestinationOU -ErrorAction Stop
        }
        catch { throw $_ }
    }
    Write-Host "- Account moved to `"$DisabledOUName`"" -ForegroundColor Green

}

Write-Host "Running through disable procedure:`n"
Invoke-Command -ComputerName $Server -Credential $ADCredentials -ScriptBlock $ScriptBlock2

# Remove user calendar events
try { Import-Module -Name 'ExchangeOnlineManagement' -ErrorAction Stop }
catch {
    Write-Warning "Missing the ExchangeOnlineManagement module."
    Write-Warning 'To remove calendar events, run "Install-Module -Name ExchangeOnlineManagement".'
    return
}

$ExchangeSession = Get-PSSession | Where-Object { $_.ConfigurationName -eq 'Microsoft.Exchange' }
if (!$ExchangeSession -or $ExchangeSession.State -ne 'Opened') {
    Connect-ExchangeOnline
}

Remove-CalendarEvents -Identity $ADUser.userPrincipalName -CancelOrganizedMeetings -QueryWindowInDays 180 -Confirm:$false
if ($error[0].CategoryInfo.Activity -eq "Remove-CalendarEvents") {
    Write-Host "- Failed to cancel meetings" -ForegroundColor Red
}
else { Write-Host "- Canceled meetings" -ForegroundColor Green }

Write-Host "`nDone!"