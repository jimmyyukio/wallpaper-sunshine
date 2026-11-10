' Start the Sunshine <-> Wallpaper Engine watcher hidden at logon.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\Tools\wallpaper-sunshine\we-stream-watch.ps1""", 0, False
