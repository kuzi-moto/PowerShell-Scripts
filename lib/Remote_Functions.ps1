function Invoke-ServerCommand {
    param (
        $ScriptBlock
    )
  
    try { Invoke-Command -ComputerName $ADConfig.Server -Credential $ADCredentials -ScriptBlock $ScriptBlock -ErrorAction Stop }
    catch { throw $_ }
  
}

function Test-ServerConnection {
    param([string]$Server)
  
    Write-Host "Testing connection to $Server"
  
    try {
        $null = Test-Connection -ComputerName $Server -Count 1 -ErrorAction Stop
        Return $true
    }
    catch {
        Write-Warning "Couldn't reach $Server, do you need to be connected to the VPN?"
        return $false
    }
  
}