[CmdletBinding()]
<# param (
  [Parameter(Mandatory = $true)]
  [string]$Query
) #>

#--------------[ Includes ]--------------

$Lib = Join-Path $PSScriptRoot 'lib'

. "$Lib\Load-ConfigFile.ps1"
. "$Lib\Test-ServerConnection.ps1"
. "$Lib\Invoke-ServerCommand.ps1"

#-----------[ Main Execution ]-----------

Load-ConfigFile $PSScriptRoot
$ConfigModified = $false

$Global:ADConfig.Domains | Format-Table ID, Name

if ($Global:ADConfig.Domains.Count -gt 1) {
  $DomainName = ""
  do {
  
    $ID = Read-Host -Prompt "Enter the ID of the domain to use"
    if ($ID -notmatch '^\d+$') {
      Write-Host "Must be a number" -ForegroundColor Red
    }
    elseif ($Global:ADConfig.Domains.ID -notcontains $ID) {
      Write-Host "Must enter one of the listed IDs" -ForegroundColor Red
    }
    else {
      $DomainName = ($Global:ADConfig.Domains | Where-Object { $_.ID -eq $ID }).Name
    }
  
  } until ($DomainName.Length -gt 0)
}
else {
  $DomainName = $Global:ADConfig.Domains.Name
}

$Domain = $Global:ADConfig.Domains | Where-Object { $_.Name -eq $DomainName }

if (-not (Test-ServerConnection $Domain.Server)) { return }

if (!$ADCredentials) { $Global:ADCredentials = Get-Credential -Message "Enter your Admin account credentials" }

$FoundUser = $false
$User = $false
do {
  $UserInput = Read-Host -Prompt "Enter user to modify"
  try {
    $FoundUser = Get-ADUser -Credential $ADCredentials -Server $Domain.Server -Identity $UserInput -ErrorAction SilentlyContinue
  }
  catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
    Write-Host "Not a valid SamAccountName, searching by DisplayName" -ForegroundColor "Yellow"
    $FoundUser = Get-ADUser -Credential $ADCredentials -Server $Domain.Server -Filter "Name -like '*$UserInput*'"
  }
  catch {
    Write-Host "Some error occured, stopping:" -ForegroundColor "Red"
    Write-Host $_ -ForegroundColor "Red"
    return
  }

  if (!$FoundUser) {
    Write-Host "Still can't find any user by that name. Please search again" -ForegroundColor Red
    continue
  }

  Write-Host ""

  if ($FoundUser.Count -gt 1) {
    for ($i = 1; $i -le $FoundUser.Count; $i++) {
      $FoundUser[$i - 1] | Add-Member -NotePropertyName "Option" -NotePropertyValue $i -Force
    }
    Write-Host "Found the following users:"
    $FoundUser | Select-Object Option, Name, UserPrincipalName | Out-Host

    do {
      $Option = Read-Host "Select which user to proceed with - (ctrl + c) to cancel"
      if ($Option -notmatch '^\d+$') {
        Write-Host "Must be a number" -ForegroundColor Red
      }
      elseif ($FoundUser.Option -notcontains $Option) {
        Write-Host "Must enter one of the listed options" -ForegroundColor Red
      }
      else {
        $User = ($FoundUser | Where-Object { $_.Option -eq $Option })
      }
    } until ($User)
  }
  elseif ($FoundUser.GetType().Name -eq "ADUser") {
    Write-Host "Found this user:"
    $FoundUser | Select-Object Name, UserPrincipalName | Out-Host

    $Done = $false
    do {
      switch -regex (Read-Host "Continue with this user? [Y]es/[N]o") {
        '^y$|^yes$' { $User = $FoundUser; $Done = $true; break }
        '^n$|^no$' { $Done = $true; break }
        Default { Write-Host "Not a valid answer. 'Y' or 'N' only" }
      }
    } until ($Done)

  }
  else {
    Write-Host "Not sure what happened, but no user found. Try again." -ForegroundColor Red
  }
  
} until ($User)

$User = $User | Get-ADUser -Credential $ADCredentials -Server $Domain.Server -Properties MemberOf

$QuickGroups = $Domain.QuickGroups | Get-ADGroup -Credential $ADCredentials -Server $Domain.Server

if ($QuickGroups.GetType().Name -eq "ADGroup") {
  $QuickGroups = @($QuickGroups)
}

$Count = 1
for ($i = 0; $i -lt $QuickGroups.Count; $i++) {

  $QuickGroups[$i] | Add-Member -MemberType NoteProperty -Name "UserIsMember" -Value $false -Force
  $QuickGroups[$i] | Add-Member -MemberType NoteProperty -Name "Option" -Value 0 -Force

  if ($User.MemberOf -contains $QuickGroups[$i].DistinguishedName) {
    $QuickGroups[$i].UserIsMember = $true
  }
  else {
    $QuickGroups[$i].Option = $Count
    $Count++
  }

}

$ExitOption = $Count

$Done = $false
Clear-Host
do {
  Write-Host "List of available Groups:"
  Write-Host ""

  foreach ($Group in $QuickGroups) {
    $Color = "White"
    if ($Group.Option) {
      if ($Group.UserIsMember) { $Color = "Red" }
      Write-Host "$($Group.Option) - $($Group.Name)" -ForegroundColor $Color
    }
  }

  Write-Host "$ExitOption - Done, exit script" -ForegroundColor Green
  Write-Host ""

  $Ans = Read-Host -Prompt "Enter an option above, or the name of group if not listed to add to $($User.Name)"
  Write-Host ""

  if ($Ans -match '^\d+$') {
    # Catch anything that is a number
    if ($Ans -lt 1 -or $Ans -gt $ExitOption) {
      Write-Host "Option not witin the valid range" -ForegroundColor Red
      Start-Sleep -Seconds 2
    }
    elseif ($Ans -eq $ExitOption) {
      $Done = $true
      Write-Host "Bye!" -ForegroundColor Green
      Start-Sleep -Seconds 2
      continue
    }
    else {
      $Group = $QuickGroups | Where-Object { $_.Option -eq $Ans }
    }
  }
  else {
    # Anything that was not a number. Try to search for it as a group
    try {
      $FoundGroup = Get-ADGroup -Credential $ADCredentials -Server $Domain.Server -Identity $Ans -ErrorAction SilentlyContinue
    }
    catch {
      $FoundGroup = Get-ADGroup -Credential $ADCredentials -Server $Domain.Server -Filter "Name -like '*$Ans*'"
    }

    if (!$FoundGroup) {
      Write-Host "No groups found, try again" -ForegroundColor Red
      Start-Sleep -Seconds 2
    }
    elseif ($FoundGroup.Count -gt 1) {

      for ($i = 0; $i -le $FoundGroup.Count; $i++) {
        $FoundGroup[$i] | Add-Member -NotePropertyName "Option" -NotePropertyValue ($i + 1) -Force
      }
      Write-Host "Found the following groups:"
      $Foundgroup | Select-Object Option, Name, SamAccountName | Out-Host
      do {

        $Option = Read-Host "Select which group to use - Press 'Enter' to cancel"
        if ($Option -eq "") {
          Write-Host "Cancelling" -ForegroundColor Yellow
          Start-Sleep -Seconds 2
          return
        }
        elseif ($Option -notmatch '^\d+$') {
          Write-Host "Must be a number" -ForegroundColor Red
          Start-Sleep -Seconds 2
        }
        elseif ($FoundGroup.Option -notcontains $Option) {
          Write-Host "Must enter one of the listed options" -ForegroundColor Red
          Start-Sleep -Seconds 2
        }
        else {
          $Group = ($FoundGroup | Where-Object { $_.Option -eq $Option })
        }

      } until ($Group)

    }
    else {
      Write-Host "Found this group:"
      $FoundGroup | Select-Object Name, SamAccountName | Out-Host

      $Done2 = $false
      do {
        switch -regex (Read-Host "Continue with this group? [Y]es/[N]o") {
          '^y$|^yes$' { $Group = $FoundGroup; $Done2 = $true; break }
          '^n$|^no$' { $Done2 = $true; break }
          Default { Write-Host "Not a valid answer. 'Y' or 'N' only" }
        }
      } until ($Done2)
    }
  }

  if ($Group) {

    if ($User.MemberOf -contains $Group.DistinguishedName) {
      Write-Host "Error: $($User.Name) is already a member of $($Group.Name)" -ForegroundColor Red
      Start-Sleep -Seconds 2
      continue
    }

    Write-Host "Adding $($User.Name) to group: $($Group.Name)"
    try {
      $Group | Add-ADGroupMember -Credential $ADCredentials -Server $Domain.Server -Members $User -ErrorAction Stop
      Write-Host "Successfully added to group!" -ForegroundColor Green
    }
    catch {
      Write-Host "Error: Something went wrong..." -ForegroundColor Red
      Write-Host "$_" -ForegroundColor Red
    }

    if ($Domain.QuickGroups -notcontains $Group.SamAccountName) {
      $Domain.QuickGroups += $Group.SamAccountName
      $ConfigModified = $true
    }
  }

  Write-Host ""

} until ($Done)

if ($ConfigModified) {
  # Save-configfile?
}