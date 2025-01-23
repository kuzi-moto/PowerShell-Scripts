# Microsoft Graph Powershell

## Resources

* [Microsoft Graph PowerShell overview](https://learn.microsoft.com/en-us/powershell/microsoftgraph/overview?view=graph-powershell-1.0)
* [user resource type](https://learn.microsoft.com/en-us/graph/api/resources/user?view=graph-rest-1.0)

## Tips

### Properties

By default `Get-MgUser` supplies several properties such as the display name and primary email address. When looking at the user object it will show all of the available properties but most will be empty.

You can specify additional property to return with `-Property`. However, it will return only the properties you specify, so the default values that appear will only be returned if you add them to the Property parameter.
 
### Get-MgAuditLogDirectoryAudit

#### Permissions

Specify `Directory.Read.All` when connecting.

#### Using -Filter

The syntax of filter is very confusing. Using this section to document how it works and some useful queries.

Search for a user or application target by its ID:

```
"targetResources/any(t:t/id eq '<user id or app id>')"
```

#### Activity Types

