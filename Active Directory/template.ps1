[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [string]$Query
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

}

$Result = Invoke-ServerCommand $ScriptBlock