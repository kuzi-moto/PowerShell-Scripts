# TeamsUserActivity-ByDepartment-Export-Csv

Provided a [Microsoft Teams user activity report](https://docs.microsoft.com/en-us/microsoftteams/teams-analytics-and-reports/user-activity-report),
this script will determine the number of messages per Department from AzureAD in Microsoft Teams.

## Requirements

* A user activity report `.csv` file
* the AzureAD module to connect to AzureAD to pull user information

## Usage

Call the script with your Office 365 tenant domain, and the path to your `.csv` export.

```BASH
TeamsUserActivity-ByDepartment-Export-Csv.ps1 -Office365Domain contoso.onmicrosoft.com -TeamsUserActivityFile path/to/file.csv
```
