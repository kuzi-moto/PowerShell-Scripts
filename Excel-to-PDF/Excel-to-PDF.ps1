param (
  [switch]$xlsx,
  [switch]$GridLines
)

# https://blogs.technet.microsoft.com/heyscriptingguy/2009/09/01/hey-scripting-guy-can-i-open-a-file-dialog-box-with-windows-powershell/
[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
$MissingValue = [System.Reflection.Missing]::Value
$xlFixedFormat = "Microsoft.Office.Interop.Excel.xlFixedFormatType" -as [type]

$OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$OpenFileDialog.initialDirectory = $Env:USERPROFILE
$OpenFileDialog.Filter = "Excel files (*.xlsx, *.xlm, *.xls)|*.xlsx;*.xlm;*.xls"

$ExcelFiles = @()

Write-Host "Pick Excel files. Click `"Cancel`" when done."
Start-Sleep -Seconds 3
do {
  $Status = $OpenFileDialog.ShowDialog()
  if ($Status -eq "OK") {
    $ExcelFiles += (Get-Item $OpenFileDialog.FileName)
    $OpenFileDialog.InitialDirectory = $ExcelFiles[$ExcelFiles.Count-1].DirectoryName
    $OpenFileDialog.FileName = $null
  }
} until ($Status -eq "Cancel")

if ($ExcelFiles.Count -lt 1) {
  Write-Host "You did not choose any Excel files." -ForegroundColor Red
  Write-Host "Exiting..." -ForegroundColor Yellow
  Start-Sleep -Seconds 3
  return
}

$Excel = New-Object -ComObject Excel.Application
$Excel.DisplayAlerts = $false
$Excel.Visible = $false

$Tempwb = $Excel.Workbooks.Add()
foreach ($File in $ExcelFiles) {
  Write-Host "Reading File: $($File.BaseName)"
  # Open each sheet in readonly mode. https://docs.microsoft.com/en-us/office/vba/api/excel.workbooks.open
  $wb = $Excel.Workbooks.Open($File.FullName, $null, $true)
  foreach ($sheet in $wb.Worksheets) {
    $sheet.Copy($MissingValue, $Tempwb.Worksheets.Item($Tempwb.Worksheets.Count))
    if ($GridLines) {
      $Tempwb.Worksheets[$Tempwb.Worksheets.Count].PageSetup.PrintGridlines = $true
    }
  }
  $wb.Close()
}

$Tempwb.Worksheets[1].Delete()

$SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
$SaveFileDialog.InitialDirectory = $Env:USERPROFILE
$SaveFileDialog.Filter = "PDF (*.pdf)|*.pdf"
$SaveFileDialog.FileName = "merged.pdf"

Write-Host "Choose your save location"
Start-Sleep -Seconds 3
if ($SaveFileDialog.ShowDialog() -eq "OK") {
  $OutPath = $SaveFileDialog.FileName
  Write-Host "Exporting PDF here: $OutPath"
  # https://blogs.technet.microsoft.com/heyscriptingguy/2010/09/06/save-a-microsoft-excel-workbook-as-a-pdf-file-by-using-powershell/
  $Tempwb.ExportAsFixedFormat($xlFixedFormat::xlTypePDF, $OutPath)
  Write-Host "Success" -ForegroundColor Green

  if ($xlsx) {
    $PDF = get-item $OutPath
    $DebugFile = Join-Path -Path $PDF.DirectoryName -ChildPath "$($PDF.BaseName).xlsx"
    $Tempwb.SaveAs($DebugFile)
  }
}
else {
  Write-Host "CANCELED!! Did not save PDF." -ForegroundColor Red
}

Write-Host "Exiting..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Don't save after closing
$Tempwb.Close($false)
$Excel.Quit()