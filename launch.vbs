Option Explicit
' Hidden launcher (no console flash). Usage:
'   wscript launch.vbs "%1"          -> quick add to current collection
'   wscript launch.vbs /pick "%1"    -> add with the collection picker
Dim sh, fso, dir, ps1, i, startIdx, extra, args, cmd
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\Add-ToZotero.ps1"
extra = ""
startIdx = 0
If WScript.Arguments.Count > 0 Then
    If WScript.Arguments(0) = "/pick" Then
        extra = " -PickCollection"
        startIdx = 1
    End If
End If
args = ""
For i = startIdx To WScript.Arguments.Count - 1
    args = args & " """ & WScript.Arguments(i) & """"
Next
cmd = "powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """" & extra & args
sh.Run cmd, 0, False