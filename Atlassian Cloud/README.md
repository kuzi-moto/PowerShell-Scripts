# Atlassian Cloud

Scripts for interacting with Atlassian Cloud

## Configuration

For convenience the scripts do not accept commonly used values such as email address, api keys, or other id's as parameters. Instead, the scripts will ask for the values as needed and then automatically save them in this folder as `config.json`. This way, scripts can be run with minimal fuss and not having to keep track of what keys to use for what purpose.

## API Keys/Tokens

There are three separate API keys/tokens which may be required depending on the functions used.

### Atlassian Admin

A key for interacting with the Atlassian Admin API is required. This allows you to retreive the organization details, and interact with users of your organization.

### User Provisioning API Key

If you wish to manipulate users synced through an Identity Provider then an SCIM key will be required. The only way I have gotten this to work is to use the API key generated when you set up your Identity Provider. If you didn't already have this saved then a new one will need to be generated and then saved in your Identity Provider again otherwise provisioning will be broken.

### Jira/Confluence User API Token

A user token is necessary to use with scripts to interact with Atlassian Cloud.

1. Navigate to [API Tokens](https://id.atlassian.com/manage-profile/security/api-tokens) page.
2. **Create API token**
3. Enter a name > **Create**
4. Copy token
5. Paste into the script when asked

## Notes

* [Atlassian API Resource](https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/)

Reference for useful commands or things that don't require a script. Before running the commands make sure to [dot source](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts?view=powershell-7.2#script-scope-and-dot-sourcing) so they are available in your current session:

```PowerShell
. .\Atlassian_Functions.ps1
```

### Using Invoke-AtlassianApiRequest

The `Invoke-AtlassianApiRequest` helper function will allow you to directly interact with the Atlassian API.

### Find the smart value for a field

Pulled from [Find the smart value for a field](https://support.atlassian.com/cloud-automation/docs/find-the-smart-value-for-a-field/) article in Atlassian's Cloud automation support.

Run this command on an existing issue, replace `<issuekey>` with a valid issue key. Ex: `IT-1234`

```PowerShell
$response = Invoke-AtlassianApiRequest 'issue/<issuekey>?expand=names'
```

The list of issue names can be retrieved from the `names` property.

```PowerShell
$response.names
```

If you have a particularly long list of values and want to filter the results, you can replace `<searchterm>` below:

```PowerShell
$response.names | Get-Member | Where-Object { $_.Definition -match "<searchterm>" }
```
