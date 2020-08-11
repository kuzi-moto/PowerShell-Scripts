# Every example should rely on these being loaded in the current powershell instance

[reflection.assembly]::LoadWithPartialName( "System.Windows.Forms") | Out-Null
[reflection.assembly]::LoadWithPartialName( "System.Drawing") | Out-Null



##############
# Example 1: #
##############
#
# This creates a basic form, and writes some text and a line onto it
# Source: https://www.techotopia.com/index.php/Drawing_Graphics_using_PowerShell_1.0_and_GDI%2B
# Source: https://docs.microsoft.com/en-us/dotnet/api/system.windows.forms.control.paint?view=netframework-4.8

# Create a Form
$form = New-Object Windows.Forms.Form

# Get the form's graphics object
$formGraphics = $form.createGraphics()

$Font = [System.Drawing.Font]::new('Arial', 10)

# Define the paint handler
$form.add_paint(
  {
    $formGraphics.DrawString("This is a diagonal line drawn on the control", $Font, [System.Drawing.Brushes]::Blue, 30, 30)
    $FormGraphics.DrawLine([System.Drawing.Pens]::Red, $form.Left, $form.Top, $form.Right, $form.Bottom)
  }
)

$form.ShowDialog()   # display the dialog


##############
# Example 2: #
##############
#
# This creates a simple form, that on clicking in the form, returns the coordinates
# It shows a more complex way to handle events

$form = New-Object Windows.Forms.Form
$form.add_mousedown($handler_form_mousedown)
$handler_form_Mousedown =
{
  param([object]$sender, [System.EventArgs]$e)
  write-host $e.x
  write-host $e.y
  $sender.text = "if ya think your so noble answer the question"
  $sender.text = "Nobles Oblige"
}

$App = $form.ShowDialog()



#############
# Example 3 #
#############
#
# This is somewhat incomplete, but was trying to get example from Microsoft working
# using a combination of the earlier examples.

$Form = [System.Windows.Forms.Form]::new()

$PictureBox = [System.Windows.Forms.PictureBox]::new()
$Font = [System.Drawing.Font]::new('Arial',10)

$Form.add_mousedown($PictureBox_Paint)

$PictureBox_Paint =
{
  param([object]$sender, [System.EventArgs]$e)
  $g = $sender.Graphics

  $g.DrawString("This is a diagonal line drawn on the control", $Font, [System.Drawing.Brushes]::Blue, [System.Drawing.Point]::new(30,30))
  $g.DrawLine([System.Drawing.Pens]::Red, $PictureBox.Left, $PictureBox.Top, $PictureBox.Right, $PictureBox.Bottom)
}

$Form_Load =
{
  param([object]$sender, [System.EventArgs]$e)
  $PictureBox.Dock = 'DockStyle.Fill'
  $PictureBox.BackColor = 'Color.White'
  $PictureBox.Paint += [System.Windows.Forms.PaintEventHandler]::new($sender.$PictureBox_Paint)
  $sender.Controls.Add($PictureBox)
}

$Form.ShowDialog()