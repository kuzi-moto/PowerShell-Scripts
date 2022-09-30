#--------------[ Includes ]--------------

$Lib = Join-Path (Get-Item -Path $PSScriptRoot).Parent 'lib'

. "$Lib\Get-ConfigFile.ps1"
. "$Lib\Remote_Functions.ps1"

# This script relies on the Powershell Module PSGraph
# Install instructions here: https://psgraph.readthedocs.io/en/latest/Quick-Start-Installation-and-Example/
try {
    Import-Module PSGraph -ErrorAction Stop
}
catch {
    Write-Host "ERROR: Couldn't import the PSGraph module. This is required for the script to function." -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    return
}

#-----------[ Main Execution ]-----------

Get-ConfigFile $PSScriptRoot
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

if (!$Global:ADCredentials) { $Global:ADCredentials = @{} }

if (!$Global:ADCredentials.$Domain) {
    $Global:ADCredentials.$Domain = Get-Credential -Message "Enter your Admin account credentials"
}

$Credentials = $Global:ADCredentials.$Domain

$Users = Get-ADUser -Credential $Credentials -Server $Domain.Server -Filter * -Properties "Title", "Department", "Manager", "directReports" -ErrorAction SilentlyContinue

$Graph = Graph myGraph {

    $Users | Where-Object { $_.Enabled -eq $true } | ForEach-Object {

        if ($_.Manager) {
            Edge -From $_.Manager -To $_.DistinguishedName
        }

        if ($_.Manager -or $_.directReports) {
            Node $_.DistinguishedName @{
                label = $_.Name
                shape = {
                    if ($_.directReports) { "rectangle" }
                }
            }
        }

    }
    
}

#$Graph | Out-File ".\org_chart.dot"

$Graph | Export-PSGraph -ShowGraph -OutputFormat svg -DestinationPath ".\org_chart.svg"