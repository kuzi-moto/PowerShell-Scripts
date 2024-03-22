# Thanks to Https://lazyadmin.nl/powershell/connect-to-exchange-online-powershell/
Function Connect-ToEXO {
    <#
      .SYNOPSIS
          Connects to EXO when no connection exists. Checks for EXO v2 module
    #>

    process {
        # Check if EXO is installed and connect if no connection exists
        if ($null -eq (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Write-Host "Exchange Online PowerShell v3 module is requied, do you want to install it?" -ForegroundColor Yellow

            $install = Read-Host 'Do you want to install module? [Y] Yes [N] No'
            if ($install -match "[yY]") {
                Write-Host "Installing Exchange Online PowerShell v3 module" -ForegroundColor Cyan
                Install-Module ExchangeOnlineManagement -Repository PSGallery -AllowClobber -Force
            }
            else {
                Write-Error "Please install EXO v3 module."
            }
        }

        # Check if there is an active EXO session
        if (Get-Module -ListAvailable -Name ExchangeOnlineManagement | Where-Object { $_.version -like "3.*" } ) {

            if ((Get-ConnectionInformation).tokenStatus -ne 'Active') {
                write-host 'Connecting to Exchange Online' -ForegroundColor Cyan
                Connect-ExchangeOnline -UserPrincipalName $adminUPN
            }

        }
        else {

            $psSessions = Get-PSSession | Select-Object -Property State, Name
            If (((@($psSessions) -like '@{State=Opened; Name=ExchangeOnlineInternalSession*').Count -gt 0) -ne $true) {
                write-host 'Connecting to Exchange Online' -ForegroundColor Cyan
                Connect-ExchangeOnline -UserPrincipalName $adminUPN
            }
            
        }
    }
}

function Search-Alias {

    param (
        [string]$Alias
    )

    try {
        [array]$User = Get-Recipient $Alias -ErrorAction SilentlyContinue
    }
    catch {
        throw
    }

    if ($User.count -gt 1) {
        Write-Warning "Multiple users found for $Alias"
        return $null
    }
    elseif ($User.Count -eq 1) {
        return $User[0]
    }
    else {
        Write-Warning "$Alias not found"
        Return $null
    }

}

function Search-Group {
    param (
        [string]$Query
    )

    try {
        switch -Regex ($Query) {
            '[\da-fA-F]{8}-([\da-fA-F]{4}-){3}[\da-fA-F]{12}' {
                Get-Group -Identity $Query
                break
            }
            Default {
                Get-Group -Anr $Query
            }
        }
    }
    catch { throw }



}