[CmdletBinding()]
param([switch]$Test)

# Determine if a parameter was used. This is useful for when a variable might be assigned a value another way,
# and so simply checking the existance of the variable is not appropriate.

if ($PSBoundParameters.ContainsKey('Test')) {
  Write-Host 'The "-Test" parameter was used'
}
else { Write-Host 'The -Test parameter was not used' }