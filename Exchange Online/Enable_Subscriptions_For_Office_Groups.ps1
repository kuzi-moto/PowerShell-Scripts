# UpdateSubscribersInGroupsUsedByTeams.PS1
# https://github.com/12Knocksinna/Office365itpros/blob/master/UpdateSubscribersInGroupsUsedByTeams.PS1
# Update the subscriber list for Teams-enabled groups so that members receive calendar updates
# Modified by Kuzma Fesenko

param (
    [string]$Name
)

#--------------[ Includes ]--------------


$Lib = Join-Path (Get-Item -Path $PSScriptRoot).Parent.FullName 'lib'

. (Join-Path $PSScriptRoot 'Functions.ps1')


#-----------[ Main Execution ]-----------


Connect-ToEXO

Clear-Host
$Group = $null

if ($PSBoundParameters.ContainsKey("Name")) {

    $Group = Get-UnifiedGroup -Identity $Name

    if (!$Group) {
        Write-Warning "Group couldn't be found for $Name"
        return
    }
    else {
        Write-Host "Found group:"
        $Group | Select-Object -Property DisplayName, PrimarySmtpAddress, AccessType, Notes | Format-Table -AutoSize | Out-Host
        Write-Host
    }
}
else {
    # The -Name parameter is left empty

    if ($MicrosoftGroups) {

        Write-Host "Re-using groups from the last run. To refresh groups exit and restart your terminal"

    }
    else {

        Write-Progress -Activity 'Getting All Groups' -Status 'This may take a minute'
        $Global:MicrosoftGroups = Get-UnifiedGroup -Filter { ResourceProvisioningOptions -eq 'Team' } -ResultSize Unlimited
        Write-Progress -Activity 'Getting All Groups' -Status 'Done' -Completed

    }

    do {

        $UserInput = Read-Host 'Search for a group by name'
        [array]$Selection = $MicrosoftGroups | Where-Object { $_.DisplayName -eq $UserInput }

        if ($Selection.Count -eq 0) {
            # If an exact match by name isn't found, then we'll attempt a more fuzzy match
            [array]$Selection = $MicrosoftGroups | Where-Object { $_.DisplayName -match $UserInput }
        }

        switch ($Selection.Count) {
            0 {
                Write-Warning "Couldn't find any group matching `"$UserInput`""
                break
            }
            1 {
                Write-Host 'Found group:'
                $Group = $Selection
                $Group | Select-Object -Property DisplayName, PrimarySmtpAddress, AccessType, Notes | Format-Table -AutoSize | Out-Host
                break
            }
            Default {
                Write-Host 'Found multiple groups. Please use exact name:'
                $Selection | Select-Object -Property DisplayName, PrimarySmtpAddress, AccessType, Notes | Format-Table -AutoSize | Out-Host    
            }
        }

    } until ($Group)

}

$Continue = $false
do {

    switch (Read-Host -Prompt "Continue? (y/n)") {
        'y' { $Continue = $true; break }
        'n' { return }
        Default { "Not valid" }
    }

} until ($Continue)

# Where-Object { $_.AutoSubscribeNewMembers -eq $False -Or $_.AlwaysSubscribeMembersToCalendarEvents -eq $False }

if ($Group.SubscriptionEnabled -eq $false) {
    Set-UnifiedGroup -Identity $Group.ExternalDirectoryObjectId -SubscriptionEnabled:$true
    Write-Host "Enabled SubscriptionEnabled property"
}

if ($Group.AutoSubscribeNewMembers -eq $true -and $Group.AlwaysSubscribeMembersToCalendarEvents -eq $true) {
    Write-Host "$($Group.DisplayName) has already been set."
}
else {
    # Update group so that new members are added to the subscriber list and will receive calendar events
    Set-UnifiedGroup -Identity $Group.ExternalDirectoryObjectId -AutoSubscribeNewMembers:$true -AlwaysSubscribeMembersToCalendarEvents
    Write-Host "Set `"$($Group.DisplayName)`" settings"
}

# Get current members and the subscribers list
$Members = Get-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -LinkType Member
$Subscribers = Get-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -LinkType Subscribers

# Check each member and if they're not in the subscriber list, add them
for ($i = 0; $i -lt $Members.Count; $i++) {
    $Count = $i+1
    $Total = $Members.count
    $Percent = $Count / $Total * 100
    Write-Progress 'Adding members as subscribers' -Status "Processing: $Count/$Total" -PercentComplete $Percent

    if ($Members[$i].ExternalDirectoryObjectId -notin $Subscribers.ExternalDirectoryObjectId) {
        Add-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -LinkType Subscribers -Links $Members[$i].PrimarySmtpAddress
        Write-Host "Added $($Members[$i].DisplayName) as subscriber"
    }
}

Write-Progress "Adding members as subscribers" -Status "Done" -Completed