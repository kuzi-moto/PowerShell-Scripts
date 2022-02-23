# PnP Powershell

## SharePoint Online

### Install

```PowerShell
Install-Module SharePointPnPPowerShellOnline
```

### Updating

```PowerShell
Update-Module SharePointPnPPowerShell*
```

### Connecting

```PowerShell
Connect-PnPOnline –Url https://yoursite.sharepoint.com -UseWebLogin
```

### Useful Commands

|                   |                                     |
| :---------------- | :---------------------------------- |
| Get-PnPConnection | Returns a PnP PowerShell Connection |

### References

* [Microsoft.com - PnP PowerShell overview](https://docs.microsoft.com/en-us/powershell/sharepoint/sharepoint-pnp/sharepoint-pnp-cmdlets?view=sharepoint-ps)
