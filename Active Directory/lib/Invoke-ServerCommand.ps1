function Invoke-ServerCommand {
  param (
    $ScriptBlock
  )

  try { Invoke-Command -ComputerName $ADConfig.Server -Credential $ADCredentials -ScriptBlock $ScriptBlock -ErrorAction Stop }
  catch { throw $_ }

}