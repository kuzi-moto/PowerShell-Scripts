[CmdletBinding()]
param (
    [string]$Path
)

try {
    $UserList = Import-Csv -Path $Path -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Could not read file $Path" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    return
}

try {
    Import-Module -Name MicrosoftTeams -ErrorAction Stop
}
catch {
    throw "Missing MicrosoftTeams module. Install and run again"
}

Connect-MicrosoftTeams

do {
    $TeamName = Read-Host "Enter the name of a Team to add users"
    Write-Host "Searching teams..."
    $TeamsList = Get-Team -DisplayName $TeamName

    if ($TeamsList.GetType().name -eq "Object[]") {

        for ($i = 1; $i -le $TeamsList.Count; $i++) {
            $TeamsList[$i - 1] | Add-Member -NotePropertyName "Option" -NotePropertyValue $i -Force
        }

        do {

            Write-Host "Found the following teams:"
            $TeamsList | Select-Object Option, DisplayName, Visibility, Archived, Description | Format-Table -AutoSize | Out-Host

            $Option = Read-Host "Enter the option to proceed with - 0 to cancel"
            if ($Option -notmatch '^-?\d+$') {
                Write-Host "Must be a number" -ForegroundColor Red
            }
            elseif ($TeamsList.Option -notcontains $Option -and $Option -ne 0) {
                Write-Host "Must enter one of the listed options" -ForegroundColor Red
            }
            else {
                $Team = ($TeamsList | Where-Object { $_.Option -eq $Option })
            }

        } until ($Team -or $Option -eq 0)

    }
    elseif ($TeamsList.GetType().Name -eq "TeamSettings") {

        Write-Host "Found this team:"
        $TeamsList | Select-Object DisplayName, Visibility, Archived, Description | Format-Table -AutoSize | Out-Host

        $Done = $false
        do {
            switch -regex (Read-Host "Continue with this team? [Y]es/[N]o") {
                '^y$|^yes$' { $Team = $TeamsList; $Done = $true; break }
                '^n$|^no$' { $Done = $true; break }
                Default { Write-Host "Not a valid answer. 'Y' or 'N' only" }
            }
        } until ($Done)

    }
    else {

        Write-Host "Not sure what happened but couldn't find a team. Try again" -ForegroundColor Red

    }

} until ($Team)

$TeamMembers = $Team | Get-TeamUser

$UPNColumn = $null

$UserList[0] | Select-Object * | Out-Host

do {

    $UserInput = Read-Host 'Enter column containing UPN'

    if (($UserList | Get-Member -MemberType NoteProperty).Name -contains $UserInput) {
        $UPNColumn = $UserInput
    }
    else {
        Write-Host "$UserInput - Not a valid column, try again" -ForegroundColor Red
        Start-Sleep -Seconds 2
    }

} until ($UPNColumn)


for ($i = 0; $i -lt $UserList.Count; $i++) {

    Write-Progress -Activity "Adding users to $($Team.DisplayName) team" -Status "Progress: $i/$($UserList.Count)" -PercentComplete ($i/$UserList.Count*100)

    if ($TeamMembers.User -contains $UserList[$i].$UPNColumn) {
        Write-Host "$($UserList[$i].$UPNColumn) - Already a member"
    }
    else {
        $Team | Add-TeamUser -User $UserList[$i].$UPNColumn
        Write-Host "$($UserList[$i].$UPNColumn) - Added to team" -ForegroundColor Green
    }

}