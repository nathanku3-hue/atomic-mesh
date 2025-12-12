# USAGE: Type 'mesh-up' in ANY project folder.
# LOCATION: C:\Tools\atomic-mesh\mesh-up.ps1
# FIX: Window title is set BEFORE the infinite loop scripts run.

param (
    [switch]$MinimizeServer = $true
)

$MeshRoot = "C:\Tools\atomic-mesh"
# Explicitly use x86 PowerShell
$PSExec = "$Env:SystemRoot\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"

Write-Host "🚀 Initializing Atomic Mesh (Sentry Mode)..." -ForegroundColor Cyan

# --- 1. THE WINDOW MANAGER ENGINE (C# Injection) ---
$User32Definition = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace AtomicMesh {
    public class WindowManager {
        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);
        
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
        
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
        
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        public static IntPtr FindWindowByTitle(string partialTitle) {
            IntPtr foundHandle = IntPtr.Zero;
            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                StringBuilder sb = new StringBuilder(256);
                GetWindowText(hWnd, sb, sb.Capacity);
                string title = sb.ToString();
                
                if (!string.IsNullOrEmpty(title) && title.Contains(partialTitle)) {
                    foundHandle = hWnd;
                    return false; 
                }
                return true; 
            }, IntPtr.Zero);
            return foundHandle;
        }
    }
}
"@

try {
    Add-Type -TypeDefinition $User32Definition -Language CSharp
}
catch {
    # Ignore if type already exists
}

# --- 2. GRID CALCULATIONS ---
Add-Type -AssemblyName System.Windows.Forms
$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$H = [int]($Screen.Height / 2)
$W = 700 
$Taskbar = 40

$Q1 = @{X = 0; Y = 0 }               # Top-Left
$Q2 = @{X = $W; Y = 0 }               # Top-Right
$Q3 = @{X = 0; Y = $H - $Taskbar }   # Bottom-Left
$Q4 = @{X = $W; Y = $H - $Taskbar }   # Bottom-Right

# Set COMMANDER window title (this window) BEFORE launching others
$host.UI.RawUI.WindowTitle = "AtomicCommander"

# --- 3. LAUNCH SEQUENCE (Fire and Forget) ---

# A. SERVER
Write-Host "   Starting Brain..." -ForegroundColor Gray
Start-Process python -ArgumentList "$MeshRoot\mesh_server.py" -WindowStyle Minimized

# B. DASHBOARD
$DashCmd = "-NoExit -Command ""`$host.UI.RawUI.WindowTitle='AtomicDashboard'; & '$MeshRoot\dashboard.ps1'"""
Start-Process "conhost.exe" -ArgumentList """$PSExec"" $DashCmd" -WindowStyle Normal

# C. FRONTEND
$FrontCmd = "-NoExit -Command ""`$host.UI.RawUI.WindowTitle='AtomicFrontend'; & '$MeshRoot\worker.ps1' -Type frontend -Tool claude"""
Start-Process "conhost.exe" -ArgumentList """$PSExec"" $FrontCmd" -WindowStyle Normal

# D. BACKEND
$BackCmd = "-NoExit -Command ""`$host.UI.RawUI.WindowTitle='AtomicBackend'; & '$MeshRoot\worker.ps1' -Type backend -Tool codex"""
Start-Process "conhost.exe" -ArgumentList """$PSExec"" $BackCmd" -WindowStyle Normal

# --- 4. THE SENTRY LOOP ---
Start-Sleep -Seconds 2

Clear-Host
Write-Host "🎖️ COMMANDER ONLINE" -ForegroundColor Green
Write-Host "   Mesh Location: $MeshRoot" -ForegroundColor Gray

$Targets = @(
    @{Title = "AtomicDashboard"; X = $Q2.X; Y = $Q2.Y },   # Top-Right
    @{Title = "AtomicFrontend"; X = $Q1.X; Y = $Q1.Y },    # Top-Left
    @{Title = "AtomicBackend"; X = $Q3.X; Y = $Q3.Y },     # Bottom-Left
    @{Title = "AtomicCommander"; X = $Q4.X; Y = $Q4.Y }    # Bottom-Right (THIS window)
)

# Run alignment loop
$MaxAttempts = 20
$Attempt = 0
$AllAligned = $false

while (-not $AllAligned -and $Attempt -lt $MaxAttempts) {
    $Attempt++
    $AlignedThisRound = 0
    
    foreach ($T in $Targets) {
        $hWnd = [AtomicMesh.WindowManager]::FindWindowByTitle($T.Title)
        if ($hWnd -ne [IntPtr]::Zero) {
            [AtomicMesh.WindowManager]::MoveWindow($hWnd, $T.X, $T.Y, $W, $H, $true) | Out-Null
            
            $rect = New-Object AtomicMesh.WindowManager+RECT
            [AtomicMesh.WindowManager]::GetWindowRect($hWnd, [ref]$rect) | Out-Null
            
            $tolerance = 10
            $xOk = [Math]::Abs($rect.Left - $T.X) -le $tolerance
            $yOk = [Math]::Abs($rect.Top - $T.Y) -le $tolerance
            
            if ($xOk -and $yOk) {
                $AlignedThisRound++
                Write-Host "." -NoNewline -ForegroundColor Green
            }
            else {
                Write-Host "~" -NoNewline -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "?" -NoNewline -ForegroundColor Red
        }
    }
    
    if ($AlignedThisRound -eq $Targets.Count) {
        $AllAligned = $true
    }
    else {
        Start-Sleep -Milliseconds 500
    }
}

if ($AllAligned) {
    Write-Host "`n✅ All Windows Aligned." -ForegroundColor Green
}
else {
    Write-Host "`n⚠️ Some windows may not be aligned." -ForegroundColor Yellow
}

# Launch Commander CLI
& "$MeshRoot\commander.ps1"
