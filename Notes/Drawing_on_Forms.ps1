[reflection.assembly]::LoadWithPartialName( "System.Windows.Forms") | Out-Null
[reflection.assembly]::LoadWithPartialName( "System.Drawing") | Out-Null

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