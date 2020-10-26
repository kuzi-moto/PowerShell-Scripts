function Read-HostYN {
  param ([string]$Question)

  do {
    switch -regex (Read-Host $Question"? [Y]es/[N]o") {
      'y$|yes$' { return $true }
      'n$|no$' { return $False }
      Default { Write-Output "Sorry, [Y]es or [N]o only" }
    }
  } while ($true)
}