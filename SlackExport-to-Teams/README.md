# SlackExport-to-Teams

This script migrates history from Slack to Microsoft Teams. Existing solutions will have you dump the chat history into a `.html` file and upload it to the Teams channel, or pay a third party about $50 a channel to migrate it properly. The first method is at least free, but the search experience is terrible as you can't search the contents from within Teams. The second method can produce great results where chat messages are directly imported to Teams and appear as native messages, but can get very expensive where 20 channels can easily cost $1,000.

Attempting to get the best of both worlds, this script puts all of the history into a single message thread. On the browser, messages are formatted to mimic [Teams cards](https://docs.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/cards-format?tabs=adaptive-md%2Cconnector-html), while on mobile apps they are simply separated by a space. Multiple Slack messages are combined into one Teams message to reduce the number of requests to the Graph API, as there is a rate limit of about 2 a second. This makes navigating through the history a little cumbersome, as you need to keep expanding the messages to see all the content. Additionally, messages as part of a thread appear in chronological order with other messages (with an indication that it's a reply). On the plus side, searching works nearly as good as native Teams messages, reducing the need to manually move through the history. Slack status messages, such as channel joins/leaves, and bot messages are left out to reduce clutter and speed up the migration process.

## Prerequisites

* Powershell 5 - The script does not work on 7
* [MSAL.PS](https://github.com/AzureAD/MSAL.PS) module
* A [Slack export](https://slack.com/help/articles/201658943-Export-your-workspace-data) file. To backup private channels without having an Enterprise Slack license, you can use this Python tool: [Slack Exporter](https://github.com/zach-snell/slack-export).
  * At the time of writing, the original project does not fetch all private channels correctly. [This project](https://github.com/ax42/slack-export/tree/slack-conversations-api) does, make sure to pull the `slack-conversations-api` branch.

### AzureAD Application

Before using this, you need to [register a new application](https://docs.microsoft.com/en-us/azure/active-directory-b2c/tutorial-register-applications?tabs=app-reg-ga#register-a-web-application).



## Usage
