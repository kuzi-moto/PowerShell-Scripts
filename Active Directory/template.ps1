[CmdletBinding()]
param (
  [Parameter(Mandatory = $true)]
  [string]$Query
)

#--------------[ Includes ]--------------

$Lib = Join-Path (Get-Item -Path $PSScriptRoot).Parent 'lib'

. "$Lib\Get-ConfigFile.ps1"
. "$Lib\Remote_Functions.ps1"


#-----------[ Main Execution ]-----------

Get-ConfigFile $PSScriptRoot

if (-not (Test-ServerConnection)) { return }

if (!$ADCredentials) { $Global:ADCredentials = Get-Credential -Message "Enter your Admin account credentials" }

$ScriptBlock = {

}

$Result = Invoke-ServerCommand $ScriptBlock