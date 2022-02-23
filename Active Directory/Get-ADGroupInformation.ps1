[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [string]$Group
)

#--------------[ Includes ]--------------

$Lib = Join-Path $PSScriptRoot 'lib'

. "$Lib/Load-ConfigFile.ps1"
. "$Lib/Test-ServerConnection.ps1"
. "$Lib/Invoke-ServerCommand.ps1"


#-----------[ Main Execution ]-----------

Load-ConfigFile $PSScriptRoot

if (-not (Test-ServerConnection)) { return }

if (!$ADCredentials) { $Global:ADCredentials = Get-Credential -Message "Enter your Admin account credentials" }

$ScriptBlock = {
  $Properties = @('CanonicalName', 'DisplayName', 'GroupCategory', 'GroupScope', 'mail', 'Members', 'ProxyAddresses')
  try { $Result = Get-ADGroup -Identity $Using:Group -Properties $Properties -ErrorAction SilentlyContinue }
  catch { }

  if (!$Result) {
    try { $Result = Get-ADGroup -Filter "Name -like `"*$Using:Group*`"" -Properties $Properties -ErrorAction SilentlyContinue }
    catch { }
  }

  $Result
}

$ADGroup = Invoke-ServerCommand $ScriptBlock

if (!$ADGroup) {
  Write-Warning "Unable to locate an account for `"$Group`", please check the name and try again."
  return
}
elseif ($ADGroup.Count -gt 1) {
  Write-Host "Found the following accounts:"
  $ADGroup | Select-Object -Property Name, SamAccountName | Sort-Object -Property Name | Out-Host
  Write-Warning "Found $($ADGroup.Count) matches, consider using SamAccountName from the list above."
  return
}

$Aliases

Write-host "Group: $($ADGroup.Name)"
Write-Host " - DN: $($ADGroup.DistinguishedName)"
Write-Host " - Mail: $($ADGroup.mail)"
Write-Host " "
Write-Host " - Class: $($ADGroup.ObjectClass)"
Write-Host " - Category: $($ADGroup.GroupCategory)"
Write-Host " - Scope: $($ADGroup.GroupScope)"
Write-Host " - "