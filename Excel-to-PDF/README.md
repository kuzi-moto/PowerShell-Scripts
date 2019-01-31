# Excel-To-PDF.ps1

This is a fairly simple script that when run does the following:

* Prompts the user to select some Excel files
* Uses Excel to open and copy all the sheets into a single document
* Prompts the user on where to save the PDF
* Uses Excel to export the document to PDF

## Usage

To run normally, just right-click and "Run with PowerShell".

### Parameters

You can use the following swtiches for optional behaviors.

* -xlsx - Use this switch to output the merged spreadsheet with the PDF for testing. You could also use this if you just wanted to easily merge several spreadsheets.
* -GridLines - Enables the PDF to show grid lines. I suppose it might be better to just copy the existing spreadsheet's setting...