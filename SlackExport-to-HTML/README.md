# SlackExport-to-HTML

Using an (export from Slack](https://slack.com/help/articles/201658943-Export-your-workspace-data) this script will
create an HTML file for each channel contained within the export folder. Additionally, it downloads all the
attachments that were posted to the channel.

At the moment the output is partially incomplete because I no longer needed to use this. It shows all messages and
what files were attached to the message, but isn't clickable. Also can't tell what messages are replies to a thread.

## Usage

1. Extract the `Slack export.zip`.
2. Run `SlackExport-to-HTML.ps1 -ExportPath 'path/to/export'`.

### Parameters

* `-ExportPath` - (Mandatory) Location of the extracted Slack export.
* `-Destination` - (Optional) Folder to store the generated HTML files. `.\output` by default.
* `-Channel` - (Optional) Only generates output for the specified channel.
