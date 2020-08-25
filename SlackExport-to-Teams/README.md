# SlackExport-to-Teams

This script migrates history from Slack to Microsoft Teams. Existing solutions will have you dump the chat history into a `.html` file and upload it to the Teams channel, or pay a third party about $50 a channel to migrate it properly. The first method is at least free, but the search experience is terrible as you can't search the contents from within Teams. The second method can produce great results where chat messages are directly imported to Teams and appear as native messages, but can get very expensive where 20 channels can easily cost $1,000.

Attempting to get the best of both worlds, this script puts all of the history into a single message thread. On the browser, messages are formatted to mimic [Teams cards](https://docs.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/cards-format?tabs=adaptive-md%2Cconnector-html), while on mobile apps they are simply separated by a space. Multiple Slack messages are combined into one Teams message to reduce the number of requests to the Graph API, as there is a rate limit of about 2 a second. This makes navigating through the history a little cumbersome, as you need to keep expanding the messages to see all the content. Additionally, messages as part of a thread appear in chronological order with other messages (with an indication that it's a reply). On the plus side, searching works nearly as good as native Teams messages, reducing the need to manually move through the history. Slack status messages, such as channel joins/leaves, and bot messages are left out to reduce clutter and speed up the migration process.

## Prerequisites

* Powershell 5 - The script does not work on 7
* [MSAL.PS](https://github.com/AzureAD/MSAL.PS) module
* A [Slack export](https://slack.com/help/articles/201658943-Export-your-workspace-data) file. To backup private channels without having an Enterprise Slack license, you can use this Python tool: [Slack Exporter](https://github.com/zach-snell/slack-export).
  * At the time of writing, the original project does not fetch all private channels correctly. [This fork](https://github.com/ax42/slack-export/tree/slack-conversations-api) does, make sure to pull the `slack-conversations-api` branch.
  * **Important!** - If you do have to download private files, you will have to create a Slack app to get a token. In addition to the permissions required for the **slack-export** tool, you will also need to add the `files:read` permission to download the files, and add the slack token to your `config.json` file.

### AzureAD Application

The application will connect to the Graph API on your behalf. Here are instructions to set up:

1. [Register a new Azure AD application](https://docs.microsoft.com/en-us/azure/active-directory-b2c/tutorial-register-applications?tabs=app-reg-ga#register-a-web-application).
    1. Follow instructions 1-5.
    2. Skip step 6.
    3. At step 7 for the **Redirect URI** select **Public client/native (mobile & desktop)**, and enter `http://localhost` as the value.
    4. Select **Register**, and skip rest of instructions.
    5. After creating the application, make a note of the **Application ID** and **Directory ID** for later.
2. Set Permissions
    1. On the sidebar under **Manage** click on **API Permissions**.
    2. Click **+ Add a permission** > **Microsoft Graph** > **Delegated permissions**
    3. Search for the following permissions, and check the box next to them:
        * ChannelMessage.Read.All
        * ChannelMessage.Send
        * Files.Read.All
        * Group.ReadWrite.All
        * Team.ReadBasic.All
    4. Click **Add permissions**
    5. Click **Grant admin consent for \<domain\>**

## Usage

1. Move `config-example.json` to `config.json` and replace the **Client ID** and **Tenant ID** values from your Azure application.
    * Optionally, you can edit the **RootMessageSubject** to modify the subject of the root message where the history will be placed.
2. Move `data-example.csv` to `data.csv`. Each row should contain the source Slack channel, followed by the destination Team, and Teams channel. Accurately naming is important otherwise it will fail.
3. Run `.\Slack-Export-to-Teams.ps1 -SlackExportPath 'directory/to/slack/export'`

The script will now run through all of the entries in the `data.csv` file. The process is not fully automated and requires manual intervention to upload files that were downloaded from the channel, but tries to make it as simple as possible.

### Parameters

* `-SlackExportPath <path/to/export>` - [Required] The path to your Slack export folder
* `-ConfigurationPath <path/to/config.json>` - [Optional] Path to the `config.json` file to use. By default this uses the directory the script is in
* `-DataPath <path/to/data.csv>` - [Optional] Path to the `data.csv` file to use. By default this uses the directory the script is in
* `-Resume` - [Optional] Add this switch to continue running the script from the last successfully sent message in the event of an error

## Issues

The most common issue so far is that Powershell 5 does not handle unicode characters very well. A lot of characters are encoded in the Slack export and are handled properly. Some characters are not, so I have included the decimal value for ones I have encountered. They are pretty easy to spot, using a missing character icon. To resolve, add the decimal value of the character to where the `$UnicodeChars` variable is assigned. A list of unicode characters and their decimal values can be found on [Wikipedia](https://en.wikipedia.org/wiki/List_of_Unicode_characters#Special_areas_and_format_characters).
