function Load-ConfigFile {
  param([string]$Path)

  $ConfigPath = Join-Path $Path 'config.json'

  if (Test-Path $ConfigPath) {
    try { $Global:ADConfig = Get-Content $ConfigPath -ErrorAction Stop | ConvertFrom-Json }
    catch {
      Write-Warning "Couldn't read the config file."
      Write-Host "$_" -ForegroundColor Red
      return $False
    }
  }

}