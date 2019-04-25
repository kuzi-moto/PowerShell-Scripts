# Thanks to: https://stackoverflow.com/a/39319540
# This is useful if you need to track when a user becomes inactive and for how long
Add-Type @'
  using System;
  using System.Diagnostics;
  using System.Runtime.InteropServices;
  namespace PInvoke.Win32 {
    public static class UserInput {
      [DllImport("user32.dll", SetLastError=false)]
      private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
      [StructLayout(LayoutKind.Sequential)]
      private struct LASTINPUTINFO {
        public uint cbSize;
        public int dwTime;
      }
      public static DateTime LastInput {
        get {
          DateTime bootTime = DateTime.UtcNow.AddMilliseconds(-Environment.TickCount);
          DateTime lastInput = bootTime.AddMilliseconds(LastInputTicks);
          return lastInput;
        }
      }
      public static TimeSpan IdleTime {
        get {
          return DateTime.UtcNow.Subtract(LastInput);
        }
      }
      public static int LastInputTicks {
        get {
          LASTINPUTINFO lii = new LASTINPUTINFO();
          lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
          GetLastInputInfo(ref lii);
          return lii.dwTime;
        }
      }
    }
  }
'@

ForEach ($i in 0..60) {
  Write-Host ("Last input " + [PInvoke.Win32.UserInput]::LastInput)
  Write-Host ("Idle for " + [PInvoke.Win32.UserInput]::IdleTime)
  Start-Sleep -Seconds 1
}