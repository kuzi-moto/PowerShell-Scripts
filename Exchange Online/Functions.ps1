# Thanks to Https://lazyadmin.nl/powershell/connect-to-exchange-online-powershell/
Function Connect-ToEXO {
    <#
      .SYNOPSIS
          Connects to EXO when no connection exists. Checks for EXO v2 module
    #>

    process {
        # Check if EXO is installed and connect if no connection exists
        if ($null -eq (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Write-Host "Exchange Online PowerShell v2 module is requied, do you want to install it?" -ForegroundColor Yellow

            $install = Read-Host Do you want to install module? [Y] Yes [N] No
            if ($install -match "[yY]") {
                Write-Host "Installing Exchange Online PowerShell v2 module" -ForegroundColor Cyan
                Install-Module ExchangeOnlineManagement -Repository PSGallery -AllowClobber -Force
            }
            else {
                Write-Error "Please install EXO v2 module."
            }
        }


        if ($null -ne (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            # Check if there is a active EXO sessions
            $psSessions = Get-PSSession | Select-Object -Property State, Name
            If (((@($psSessions) -like '@{State=Opened; Name=ExchangeOnlineInternalSession*').Count -gt 0) -ne $true) {
                Connect-ExchangeOnline
            }
        }
        else {
            Write-Error "Please install EXO v2 module."
        }
    }
}

function Search-Alias {

    param (
        [string]$Alias
    )

    try {
        $User = Get-Recipient $Alias -ErrorAction SilentlyContinue
    }
    catch {
        throw
    }

    if ($User.count -gt 1) {
        Write-Warning "Multiple users found for $Alias"
        return $null
    }
    elseif ($User) {
        return $User
    }
    else {
        Write-Warning "$Alias not found"
        Return $null
    }

}