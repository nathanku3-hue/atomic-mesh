param([int]$X = 0, [int]$Y = 0, [int]$Width = 0, [int]$Height = 0, [switch]$GetRect, [IntPtr]$Handle)

$def = @"
[DllImport("user32.dll")] 
public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags); 

[DllImport("kernel32.dll")] 
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

[StructLayout(LayoutKind.Sequential)]
public struct RECT
{
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
"@

try {
    Add-Type -MemberDefinition $def -Name "WinPos" -Namespace "Native" -ErrorAction SilentlyContinue
    
    if ($GetRect) {
        if ($Handle -eq [IntPtr]::Zero) {
            $Handle = [Native.WinPos]::GetConsoleWindow()
        }
        $rect = New-Object Native.RECT
        [Native.WinPos]::GetWindowRect($Handle, [ref]$rect) | Out-Null
        return $rect
    }
    else {
        $hwnd = [Native.WinPos]::GetConsoleWindow()
        if ($Width -gt 0 -and $Height -gt 0) {
            # Resize AND move: use 0 flags to allow both
            [Native.WinPos]::SetWindowPos($hwnd, [IntPtr]::Zero, $X, $Y, $Width, $Height, 0x0000) | Out-Null
        }
        else {
            # Move only: use SWP_NOSIZE (0x0001)
            [Native.WinPos]::SetWindowPos($hwnd, [IntPtr]::Zero, $X, $Y, 0, 0, 0x0001) | Out-Null
        }
    }
}
catch {}

