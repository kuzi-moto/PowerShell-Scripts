# UpdateSubscribersInGroupsUsedByTeams.PS1
# https://github.com/12Knocksinna/Office365itpros/blob/master/UpdateSubscribersInGroupsUsedByTeams.PS1
# Update the subscriber list for Teams-enabled groups so that members receive calendar updates
# Modified by Kuzma Fesenko

Connect-ExchangeOnline

Clear-Host
Write-Progress -Activity "Getting Groups"
$Groups = Get-UnifiedGroup -Filter { ResourceProvisioningOptions -eq "Team" } -ResultSize Unlimited

Write-Progress -Activity "Getting groups" -Status "Done" -Completed

do {
    $Selection = Read-Host "Search for a group by name"
    $Group = $Groups | Where-Object { $_.DisplayName -eq $Selection }

    if (!$Group) {
        $Group = $Groups | Where-Object { $_.DisplayName -match $Selection }
    }

    if ($Group.GetType().Fullname -eq 'System.Management.Automation.PSObject') {
        Write-Host "Found Group:"
        $Group | Select-Object -Property DisplayName, PrimarySmtpAddress, AccessType, Notes | Format-Table -AutoSize | Out-Host
    }
    elseif ($Group.GetType().Fullname -eq 'System.Object[]') {
        Write-Host "Found multiple groups. Please use exact name:"
        $Group | Select-Object -Property DisplayName, PrimarySmtpAddress, AccessType, Notes | Format-Table -AutoSize | Out-Host
    }
    else {
        Write-Warning "Couldn't find any group matching `"$Selection`""
    }
} until ($Group)

$Continue = $false
do {

    switch (Read-Host -Prompt "Continue? (y/n)") {
        'y' { $Continue = $true; break }
        'n' { return }
        Default { "Not valid" }
    }

} until ($Continue)

# Where-Object { $_.AutoSubscribeNewMembers -eq $False -Or $_.AlwaysSubscribeMembersToCalendarEvents -eq $False }

if ($Group.AutoSubscribeNewMembers -eq $true -and $Group.AlwaysSubscribeMembersToCalendarEvents -eq $true) {
    Write-Host "$($Group.DisplayName) has already been set properly."
}
else {
    # Update group so that new members are added to the subscriber list and will receive calendar events
    Set-UnifiedGroup -Identity $Group.ExternalDirectoryObjectId -AutoSubscribeNewMembers:$True -AlwaysSubscribeMembersToCalendarEvents
}


# Get current members and the subscribers list
$Members = Get-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -LinkType Member
$Subscribers = Get-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -LinkType Subscribers

# Check each member and if they're not in the subscriber list, add them
$Count = 1
ForEach ($Member in $Members) {

    Write-Progress "Adding existing members as subscribers" -Status "Processing: $Count/$($Members.count)" -PercentComplete $Count/$Members.count*100

    If ($Member.ExternalDirectoryObjectId -notin $Subscribers.ExternalDirectoryObjectId) {

        # Not in the list
        #    Write-Host "Adding" $Member.PrimarySmtpAddress "as a subscriber"
        Add-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -LinkType Subscribers -Links $Member.PrimarySmtpAddress
        $ReportLine = [PSCustomObject] @{
            Group      = $Group.DisplayName
            Subscriber = $Member.PrimarySmtpAddress
            Name       = $Member.DisplayName
        }
        $Report.Add($ReportLine)

    }

    $Count++

}

Write-Progress "Adding existing members as subscribers" -Completed