Add-Type -AssemblyName System.Windows.Forms
[Windows.Forms.MessageBox]::Show(
  "Hi! This is text inside of a message box!",        # Boxy - This is the main message you're trying to convey
  "This is the title!",                               # Title Text - Any string goes here
  "OK",                                               # Buttons - Only accepts: OK, OKCancel, AbortRetryIgnore, YesNoCancel, YesNo, RetryCancel
  "Information"                                       # Icon - Only accepts: None, Hand, Error, Stop, Question, Exclamation, Warning, Asterisk, Information
)