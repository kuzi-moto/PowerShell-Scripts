# Thanks to https://stackoverflow.com/a/36388891
Resolve-path 'asdf'
$Error[0].Exception.GetType().FullName

try { Resolve-path 'asdf' -ErrorAction Stop }
catch [System.Management.Automation.ItemNotFoundException] {
  Write-Host 'Error: Path not found!' -ForegroundColor Red
}

# This is useful, as you can target specific errors and the standard error
# doesn't tell you the full name of the error.