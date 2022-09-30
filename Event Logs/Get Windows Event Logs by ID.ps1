Import-Module ActiveDirectory

<#
Implement an ID picker

4725 - A user account was disabled - Security
4724 - Password change attempted by admin - Security
4723 - Password change attempted by user - Security

#>

#$keyword = Read-Host "Enter Keyword"
$EventID = Read-Host "Enter EventID"
$LogName = Read-Host "Enter the name of log you want to search, application, security, etc."

$domains = (Get-ADForest).domains

$dcs = Foreach ($domain in $domains) {
    Write-Progress -Activity "Searching $domain"
    Get-ADDomainController -Filter * | Select-Object Name -ExpandProperty Name | Sort-Object | Get-Unique
}

$Events = @()

for ($i = 1; $i -lt $dcs.Count + 1; $i++) {
    $dc = $dcs[$i - 1]
    Write-Progress "Searching $dc" -PercentComplete ($i / $dcs.count * 100) -Status "$i/$($dcs.count)"

    if (Test-Connection -ComputerName $dc -Quiet -Count 1 ) {

        try {
            $Events += Get-WinEvent -FilterHashtable @{'LogName' = $LogName; 'ID' = $EventID } -ComputerName $dc -ErrorAction Stop | Select-Object -Property Message,MachineName,TimeCreated
        }
        catch {
            Write-Warning ($dc + ': ' + $Error[0])
        }

    }
    else {
        Write-Warning "Couldn't connect to $dc"
    }

}

$Events