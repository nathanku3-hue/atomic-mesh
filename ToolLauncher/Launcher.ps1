param(
    [switch]$AutoLaunch,
    [string]$CommandPlan,
    [string]$CommandPlanBase64
)

# Ensure npm global bin is in PATH (Node.js should already be in system PATH)
$env:PATH = "$env:APPDATA\npm;$env:PATH"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Self-elevate to Administrator (preserve inbound flags) - skip elevation for CommandPlan to avoid hidden UAC in headless mode
if (-not $CommandPlan -and -not $CommandPlanBase64) {
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        if ($AutoLaunch) { $argList += "-AutoLaunch" }
        Start-Process powershell -Verb RunAs -ArgumentList $argList
        Exit
    }
}

# Debug logging for headless mode
$launcherDebugLog = Join-Path $PSScriptRoot "launcher_debug.log"

# Decode base64 command plan if provided
if ($CommandPlanBase64) {
    "$(Get-Date -Format o) Launcher started with CommandPlanBase64 (len=$($CommandPlanBase64.Length))" | Out-File $launcherDebugLog -Append
    try {
        $CommandPlan = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($CommandPlanBase64))
        "$(Get-Date -Format o) Decoded plan: $($CommandPlan.Substring(0, [Math]::Min(500, $CommandPlan.Length)))..." | Out-File $launcherDebugLog -Append
    }
    catch {
        $errMsg = $_.Exception.Message
        "$(Get-Date -Format o) ERROR decoding: $errMsg" | Out-File $launcherDebugLog -Append
        Write-Warning "Failed to decode CommandPlanBase64: $errMsg"
        $CommandPlan = $null
    }
}

# Configuration
$ConfigPath = Join-Path $PSScriptRoot "projects.json"
if (-not (Test-Path $ConfigPath)) {
    $Config = @{ Projects = @() }
}
else {
    $Config = Get-Content -Raw $ConfigPath | ConvertFrom-Json
}

$GlobalCodexMaxDefault = if ($Config.PSObject.Properties.Match('CodexMaxGlobal').Count -and $Config.CodexMaxGlobal) { $true } else { $false }
$GlobalCodexResumeDefault = if ($Config.PSObject.Properties.Match('CodexResumeGlobal').Count -and ($Config.CodexResumeGlobal -eq $false)) { $false } else { $true }
$GlobalClaudeModelDefault = if ($Config.PSObject.Properties.Match('ClaudeModelOpus').Count) { $Config.ClaudeModelOpus } else { $true } # Default to Opus

# --- MODERN UI STYLING ---
$FontMain = New-Object System.Drawing.Font("Segoe UI", 10)

$FontTitle = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)

$ColorBg = [System.Drawing.Color]::FromArgb(240, 242, 245) # Soft Gray Background
$ColorPanel = [System.Drawing.Color]::White
$ColorPrimary = [System.Drawing.Color]::FromArgb(0, 120, 215) # Windows Blue
$ColorSuccess = [System.Drawing.Color]::FromArgb(34, 197, 94) # Modern Green
$ColorDanger = [System.Drawing.Color]::FromArgb(239, 68, 68) # Modern Red
$ColorText = [System.Drawing.Color]::FromArgb(30, 41, 59) # Dark Slate
$ColorSubText = [System.Drawing.Color]::FromArgb(100, 116, 139) # Slate Gray
$ColorBorder = [System.Drawing.Color]::FromArgb(226, 232, 240) # Light Border

# Form Setup
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "AI Tool Launcher"
$Form.Size = New-Object System.Drawing.Size(950, 550)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$Form.MaximizeBox = $false
$Form.BackColor = $ColorBg
$Form.Font = $FontMain

# --- CUSTOM CONTROLS ---

# Custom Flat Button Function
function New-ModernButton($Text, $Color, $X, $Y, $W, $H) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.BackColor = $Color
    $btn.ForeColor = "White"
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $btn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
    return $btn
}

# Top Header Panel (White Bar)
$TopPanel = New-Object System.Windows.Forms.Panel
$TopPanel.Location = New-Object System.Drawing.Point(0, 0)
$TopPanel.Size = New-Object System.Drawing.Size(950, 80)
$TopPanel.BackColor = $ColorPanel
# Add subtle shadow line at bottom
$TopPanel.add_Paint({
        $g = $_.Graphics
        $pen = New-Object System.Drawing.Pen($ColorBorder, 1)
        $g.DrawLine($pen, 0, 79, 950, 79)
    })
$Form.Controls.Add($TopPanel)

# Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "AI Tool Launcher"
$lblTitle.Font = $FontTitle
$lblTitle.ForeColor = $ColorText
$lblTitle.Location = New-Object System.Drawing.Point(15, 20)
$lblTitle.Size = New-Object System.Drawing.Size(210, 40)
$TopPanel.Controls.Add($lblTitle)

# Settings Button (opens settings dialog with Schedule, Update, Calibrate, Reset Layout)
$btnSettings = New-ModernButton "Settings" $ColorSubText 620 20 90 40
$btnSettings.Add_Click({ Show-SettingsDialog })
$TopPanel.Controls.Add($btnSettings)

# Update Checkbox (hidden, state managed by settings dialog)
$chkUpdate = New-Object System.Windows.Forms.CheckBox
$chkUpdate.Checked = $true

# --- SETTINGS DIALOG ---
function Show-SettingsDialog {
    $settingsForm = New-Object System.Windows.Forms.Form
    $settingsForm.Text = "Settings"
    $settingsForm.Size = New-Object System.Drawing.Size(320, 280)
    $settingsForm.StartPosition = "CenterParent"
    $settingsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $settingsForm.MaximizeBox = $false
    $settingsForm.MinimizeBox = $false
    $settingsForm.BackColor = $ColorBg
    $settingsForm.Font = $FontMain

    # Update Checkbox
    $chkUpdateSetting = New-Object System.Windows.Forms.CheckBox
    $chkUpdateSetting.Text = "Update tools before launching"
    $chkUpdateSetting.Location = New-Object System.Drawing.Point(20, 20)
    $chkUpdateSetting.Size = New-Object System.Drawing.Size(260, 24)
    $chkUpdateSetting.ForeColor = $ColorText
    $chkUpdateSetting.Checked = $chkUpdate.Checked
    $settingsForm.Controls.Add($chkUpdateSetting)

    # Schedule Button
    $btnScheduleSetting = New-ModernButton "Schedule..." $ColorSubText 20 60 120 36
    $btnScheduleSetting.Add_Click({ Show-ScheduleDialog })
    $settingsForm.Controls.Add($btnScheduleSetting)

    # Calibrate Button
    $btnCalibrateSetting = New-ModernButton "Calibrate" $ColorSubText 160 60 120 36
    $btnCalibrateSetting.Add_Click({ Start-Calibration })
    $settingsForm.Controls.Add($btnCalibrateSetting)

    # Reset Layout Button
    $btnResetSetting = New-ModernButton "Reset Layout" $ColorSubText 20 110 120 36
    $btnResetSetting.Add_Click({
            $Script:WindowIndex = 0
            [System.Windows.Forms.MessageBox]::Show("Window layout position reset to Top-Left.", "Layout Reset")
        })
    $settingsForm.Controls.Add($btnResetSetting)

    # Close Button
    $btnCloseSetting = New-ModernButton "Close" $ColorPrimary 100 200 100 36
    $btnCloseSetting.Add_Click({
            # Save the update checkbox state
            $chkUpdate.Checked = $chkUpdateSetting.Checked
            $settingsForm.Close()
        })
    $settingsForm.Controls.Add($btnCloseSetting)

    $settingsForm.ShowDialog() | Out-Null
}

# --- SCHEDULE DIALOG ---
function Show-ScheduleDialog {
    $schedForm = New-Object System.Windows.Forms.Form
    $schedForm.Text = "Auto-Start Settings"
    $schedForm.Size = New-Object System.Drawing.Size(400, 300)
    $schedForm.StartPosition = "CenterParent"
    $schedForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $schedForm.MaximizeBox = $false
    $schedForm.MinimizeBox = $false
    $schedForm.BackColor = $ColorBg
    $schedForm.Font = $FontMain

    # Group 1: Start with Windows
    $grpStartup = New-Object System.Windows.Forms.GroupBox
    $grpStartup.Text = "System Startup"
    $grpStartup.Location = New-Object System.Drawing.Point(20, 20)
    $grpStartup.Size = New-Object System.Drawing.Size(340, 70)
    $schedForm.Controls.Add($grpStartup)

    $chkLogin = New-Object System.Windows.Forms.CheckBox
    $chkLogin.Text = "Start Launcher when Windows starts"
    $chkLogin.Location = New-Object System.Drawing.Point(20, 30)
    $chkLogin.Size = New-Object System.Drawing.Size(300, 24)
    $chkLogin.Checked = if ($Config.StartWithWindows) { $true } else { $false }
    $grpStartup.Controls.Add($chkLogin)

    # Group 2: Daily Schedule
    $grpSchedule = New-Object System.Windows.Forms.GroupBox
    $grpSchedule.Text = "Daily Schedule"
    $grpSchedule.Location = New-Object System.Drawing.Point(20, 110)
    $grpSchedule.Size = New-Object System.Drawing.Size(340, 100)
    $schedForm.Controls.Add($grpSchedule)

    $chkDaily = New-Object System.Windows.Forms.CheckBox
    $chkDaily.Text = "Enable Daily Auto-Launch"
    $chkDaily.Location = New-Object System.Drawing.Point(20, 30)
    $chkDaily.Size = New-Object System.Drawing.Size(300, 24)
    $chkDaily.Checked = if ($Config.ScheduleEnabled) { $true } else { $false }
    $grpSchedule.Controls.Add($chkDaily)

    $lblTime = New-Object System.Windows.Forms.Label
    $lblTime.Text = "Run at:"
    $lblTime.Location = New-Object System.Drawing.Point(20, 65)
    $lblTime.Size = New-Object System.Drawing.Size(60, 24)
    $grpSchedule.Controls.Add($lblTime)

    $dtPicker = New-Object System.Windows.Forms.DateTimePicker
    $dtPicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Time
    $dtPicker.ShowUpDown = $true
    $dtPicker.Location = New-Object System.Drawing.Point(80, 62)
    $dtPicker.Size = New-Object System.Drawing.Size(100, 26)
    if ($Config.ScheduleTime) {
        $dtPicker.Value = [DateTime]::ParseExact($Config.ScheduleTime, "HH:mm", $null)
    }
    $grpSchedule.Controls.Add($dtPicker)

    # Buttons
    $btnSaveSched = New-ModernButton "Save Settings" $ColorPrimary 130 220 120 36
    $btnSaveSched.Add_Click({
            # Update Config Object
            $Config.StartWithWindows = $chkLogin.Checked
            $Config.ScheduleEnabled = $chkDaily.Checked
            $Config.ScheduleTime = $dtPicker.Value.ToString("HH:mm")
        
            # Save to File
            Save-Config
        
            # Update Windows Task
            Update-ScheduledTask
        
            $schedForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $schedForm.Close()
        })
    $schedForm.Controls.Add($btnSaveSched)

    $schedForm.ShowDialog() | Out-Null
}

function Update-ScheduledTask {
    $TaskName = "AI Tool Launcher Daily"
    
    if ($Config.ScheduleEnabled) {
        $Action = New-ScheduledTaskAction -Execute "$PSScriptRoot\Launcher.exe" -Argument "-AutoLaunch"
        $Trigger = New-ScheduledTaskTrigger -Daily -At $Config.ScheduleTime
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $Principal = New-ScheduledTaskPrincipal -UserId (WhoAmI) -LogonType Interactive -RunLevel Highest
        
        # Register/Update Task (Requires Admin, which we have)
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force | Out-Null
    }
    else {
        # Unregister if exists
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
        }
    }
}

# Add Project Button (aligned right)
$btnAdd = New-ModernButton "+ Add Project" $ColorSuccess 720 20 100 40
$TopPanel.Controls.Add($btnAdd)

# Column Headers
$HeaderPanel = New-Object System.Windows.Forms.Panel
$HeaderPanel.Location = New-Object System.Drawing.Point(30, 100)
$HeaderPanel.Size = New-Object System.Drawing.Size(900, 30)
$HeaderPanel.BackColor = $ColorBg
$Form.Controls.Add($HeaderPanel)

function New-HeaderLabel($Text, $X, $Width) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Text.ToUpper()
    $lbl.Location = New-Object System.Drawing.Point($X, 5)
    $lbl.Size = New-Object System.Drawing.Size($Width, 20)
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $lbl.ForeColor = $ColorSubText
    return $lbl
}

$HeaderPanel.Controls.Add((New-HeaderLabel "Project Name" 10 130))
$HeaderPanel.Controls.Add((New-HeaderLabel "Project Path" 150 220))
$HeaderPanel.Controls.Add((New-HeaderLabel "Auto" 385 40))
$HeaderPanel.Controls.Add((New-HeaderLabel "Claude" 430 60))
$HeaderPanel.Controls.Add((New-HeaderLabel "Codex" 500 50))
$HeaderPanel.Controls.Add((New-HeaderLabel "Remember" 620 80))

# Scrollable Panel for Projects
$ProjectsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$ProjectsPanel.Location = New-Object System.Drawing.Point(30, 135)
$ProjectsPanel.Size = New-Object System.Drawing.Size(900, 330)
$ProjectsPanel.AutoScroll = $true
$ProjectsPanel.FlowDirection = "TopDown"
$ProjectsPanel.WrapContents = $false
$ProjectsPanel.BackColor = $ColorBg
$Form.Controls.Add($ProjectsPanel)

# List to keep track of project rows (for saving)
$ProjectRows = New-Object System.Collections.ArrayList

# List to keep timers alive (prevent garbage collection)
$Script:AllTimers = New-Object System.Collections.ArrayList

# Function to move a project row to the top
function Move-ProjectToTop($RowData) {
    $panel = $RowData.Panel
    $currentIndex = $ProjectsPanel.Controls.IndexOf($panel)
    if ($currentIndex -gt 0) {
        $ProjectsPanel.Controls.SetChildIndex($panel, 0)
        # Also update ProjectRows order
        $ProjectRows.Remove($RowData)
        $ProjectRows.Insert(0, $RowData)
    }
}

function Set-CodexModeButtonState {
    param(
        [System.Windows.Forms.Button]$Button,
        [bool]$Resume
    )

    $Button.Tag = $Resume
    if ($Resume) {
        $Button.Text = "Resume"
        $Button.BackColor = $ColorPrimary
    }
    else {
        $Button.Text = "New"
        $Button.BackColor = $ColorSuccess
    }
    $Button.ForeColor = "White"
}

function Get-CodexModeValue {
    param([System.Windows.Forms.Button]$Button)

    if ($null -eq $Button -or $null -eq $Button.Tag) {
        return $true
    }

    return [bool]$Button.Tag
}

function Set-ClaudeModelButtonState {
    param(
        [System.Windows.Forms.Button]$Button,
        [bool]$IsOpus
    )

    $Button.Tag = $IsOpus
    if ($IsOpus) {
        $Button.Text = "Opus"
        $Button.BackColor = [System.Drawing.Color]::FromArgb(139, 0, 139) # Dark Magenta (stronger)
    }
    else {
        $Button.Text = "Sonnet"
        $Button.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180) # Steel Blue (softer)
    }
    $Button.ForeColor = "White"
}

function Get-ClaudeModelValue {
    param([System.Windows.Forms.Button]$Button)

    if ($null -eq $Button -or $null -eq $Button.Tag) {
        return $false # Default to Sonnet
    }

    return [bool]$Button.Tag
}

function ConvertTo-Roman {
    param([int]$Number)

    if ($Number -le 0) {
        return ""
    }

    $map = @(
        @{ Value = 1000; Numeral = "M" }
        @{ Value = 900; Numeral = "CM" }
        @{ Value = 500; Numeral = "D" }
        @{ Value = 400; Numeral = "CD" }
        @{ Value = 100; Numeral = "C" }
        @{ Value = 90; Numeral = "XC" }
        @{ Value = 50; Numeral = "L" }
        @{ Value = 40; Numeral = "XL" }
        @{ Value = 10; Numeral = "X" }
        @{ Value = 9; Numeral = "IX" }
        @{ Value = 5; Numeral = "V" }
        @{ Value = 4; Numeral = "IV" }
        @{ Value = 1; Numeral = "I" }
    )

    $result = ""
    foreach ($entry in $map) {
        while ($Number -ge $entry.Value) {
            $result += $entry.Numeral
            $Number -= $entry.Value
        }
    }

    return $result
}

function Get-GeminiCountButtonValue {
    param([System.Windows.Forms.Button]$Button)

    if ($null -eq $Button -or $null -eq $Button.Tag) {
        return 0
    }

    return [int]$Button.Tag
}

function Set-GeminiCountButtonValue {
    param(
        [System.Windows.Forms.Button]$Button,
        [int]$Value
    )

    if ($null -eq $Button) {
        return
    }

    $Button.Tag = [int]$Value
    $Button.Text = ConvertTo-Roman ([int]$Value)
}

# Global Settings Panel (bottom)
$CodexSettingsPanel = New-Object System.Windows.Forms.Panel
$CodexSettingsPanel.Location = New-Object System.Drawing.Point(30, 455)
$CodexSettingsPanel.Size = New-Object System.Drawing.Size(900, 60)
$CodexSettingsPanel.BackColor = $ColorBg
$Form.Controls.Add($CodexSettingsPanel)

# Claude Model Selection
$lblClaudeModel = New-Object System.Windows.Forms.Label
$lblClaudeModel.Text = "Claude model"
$lblClaudeModel.Location = New-Object System.Drawing.Point(10, 20)
$lblClaudeModel.Size = New-Object System.Drawing.Size(100, 24)
$lblClaudeModel.Font = $FontMain
$lblClaudeModel.ForeColor = $ColorText
$CodexSettingsPanel.Controls.Add($lblClaudeModel)

# Claude Model Toggle Button (Opus/Sonnet)
$GlobalClaudeModelButton = New-Object System.Windows.Forms.Button
$GlobalClaudeModelButton.Location = New-Object System.Drawing.Point(120, 12)
$GlobalClaudeModelButton.Size = New-Object System.Drawing.Size(80, 36)
$GlobalClaudeModelButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$GlobalClaudeModelButton.FlatAppearance.BorderSize = 0
$GlobalClaudeModelButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$GlobalClaudeModelButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
Set-ClaudeModelButtonState $GlobalClaudeModelButton $GlobalClaudeModelDefault # Use saved default
$GlobalClaudeModelButton.Add_Click({
        $next = -not (Get-ClaudeModelValue $this)
        Set-ClaudeModelButtonState $this $next
    })
$CodexSettingsPanel.Controls.Add($GlobalClaudeModelButton)

$lblCodexSettings = New-Object System.Windows.Forms.Label
$lblCodexSettings.Text = "Codex settings"
$lblCodexSettings.Location = New-Object System.Drawing.Point(520, 20)
$lblCodexSettings.Size = New-Object System.Drawing.Size(110, 24)
$lblCodexSettings.Font = $FontMain
$lblCodexSettings.ForeColor = $ColorText
$CodexSettingsPanel.Controls.Add($lblCodexSettings)

$GlobalCodexMaxBox = New-Object System.Windows.Forms.CheckBox
$GlobalCodexMaxBox.Text = "Max"
$GlobalCodexMaxBox.Checked = $GlobalCodexMaxDefault
$GlobalCodexMaxBox.Location = New-Object System.Drawing.Point(640, 20)
$GlobalCodexMaxBox.Size = New-Object System.Drawing.Size(55, 24)
$GlobalCodexMaxBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$CodexSettingsPanel.Controls.Add($GlobalCodexMaxBox)

$GlobalCodexModeButton = New-Object System.Windows.Forms.Button
$GlobalCodexModeButton.Location = New-Object System.Drawing.Point(710, 12)
$GlobalCodexModeButton.Size = New-Object System.Drawing.Size(80, 36)
$GlobalCodexModeButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$GlobalCodexModeButton.FlatAppearance.BorderSize = 0
$GlobalCodexModeButton.Cursor = [System.Windows.Forms.Cursors]::Hand
$GlobalCodexModeButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
Set-CodexModeButtonState $GlobalCodexModeButton $GlobalCodexResumeDefault
$GlobalCodexModeButton.Add_Click({
        $next = -not (Get-CodexModeValue $this)
        Set-CodexModeButtonState $this $next
    })
$CodexSettingsPanel.Controls.Add($GlobalCodexModeButton)

# Global Window Index for Grid Positioning
$Script:WindowIndex = 0

# Global Calibration Offset (Default 670)
$Script:XOffset = if ($Config.WindowOffset) { $Config.WindowOffset } else { 670 }

# Session flag to track if npm update has been done
$Script:UpdateDoneThisSession = $false

function Start-Calibration {
    $WindowHelper = Join-Path $PSScriptRoot "WindowHelper.ps1"
    
    # Launch 3 dummy windows using cmd /c start to match the exact style of the tool windows
    $dummyTitles = @("Calibration 1", "Calibration 2", "Calibration 3")
    foreach ($title in $dummyTitles) {
        Start-Process "cmd.exe" -ArgumentList "/c start ""$title"" /D ""$PSScriptRoot"" ""powershell"" -NoProfile -Command ""mode con cols=100 lines=30; [Console]::BackgroundColor = 'Black'; [Console]::ForegroundColor = 'Gray'; Clear-Host; Write-Host 'Please arrange these 3 windows side-by-side with your desired spacing.'; Read-Host 'Press Enter to close...'"""
    }
    
    [System.Windows.Forms.MessageBox]::Show("Three calibration windows have been launched.`n`nPlease drag them to arrange them side-by-side with your desired spacing (Top-Left, Top-Middle, Top-Right).`n`nClick OK when you are done arranging them.", "Calibration Step 1")
    
    # Find windows and measure
    $windows = Get-Process | Where-Object { $dummyTitles -contains $_.MainWindowTitle } | Sort-Object MainWindowTitle
    
    if ($windows.Count -lt 2) {
        [System.Windows.Forms.MessageBox]::Show("Could not find enough calibration windows. Please try again.", "Calibration Failed")
        return
    }
    
    $positions = @()
    foreach ($win in $windows) {
        # Use WindowHelper to get RECT
        $rect = & $WindowHelper -GetRect -Handle $win.MainWindowHandle
        if ($rect) {
            $positions += $rect.Left
        }
    }
    
    $positions = $positions | Sort-Object
    
    # Calculate average distance
    $distances = @()
    for ($i = 0; $i -lt ($positions.Count - 1); $i++) {
        $dist = $positions[$i + 1] - $positions[$i]
        $distances += $dist
    }
    
    if ($distances.Count -gt 0) {
        $avgDist = ($distances | Measure-Object -Average).Average
        $Script:XOffset = [math]::Round($avgDist)
        
        Save-Config # Save the new offset
        
        [System.Windows.Forms.MessageBox]::Show("Calibration Complete!`n`nMeasured Offset: $Script:XOffset pixels.`nThis setting has been saved.", "Success")
    }
    else {
        [System.Windows.Forms.MessageBox]::Show("Could not calculate distance.", "Error")
    }
    
    # Cleanup
    $windows | Stop-Process -Force
}

function Get-WindowPosition($WindowIndex, $XOffset, $YOffset) {
    # New positioning logic:
    # - Windows 0-5: Normal grid (3 columns x 2 rows)
    # - Windows 6+: Fixed to middle column positions (same as windows 2-3)

    if ($WindowIndex -le 5) {
        # Normal grid positioning for first 6 windows
        $Row = $WindowIndex % 2
        $Col = [math]::Floor($WindowIndex / 2)
    }
    else {
        # Windows 7+ (index 6+): Fixed to middle column positions
        # Even indices use position 2 (top-middle), odd use position 3 (bottom-middle)
        if ($WindowIndex % 2 -eq 0) {
            # Even index: Same as window 3 (index 2) - top middle
            $Row = 0
            $Col = 1
        }
        else {
            # Odd index: Same as window 4 (index 3) - bottom middle
            $Row = 1
            $Col = 1
        }
    }

    $PosX = [Math]::Max(0, ($Col * $XOffset) - 8)
    $PosY = [Math]::Max(0, $Row * $YOffset)

    return @{ X = $PosX; Y = $PosY }
}

function Launch-CommandPlan($PlanItems) {
    "$(Get-Date -Format o) Launch-CommandPlan called with $($PlanItems.Count) items" | Out-File $launcherDebugLog -Append
    if (-not $PlanItems -or $PlanItems.Count -eq 0) {
        "$(Get-Date -Format o) ERROR: PlanItems empty or null" | Out-File $launcherDebugLog -Append
        Write-Host "CommandPlan empty; nothing to launch." -ForegroundColor Yellow
        return
    }

    # Determine PowerShell Executable (User prefers x86 for window style)
    $PSExec = Join-Path $Env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $PSExec)) {
        "$(Get-Date -Format o) x86 PowerShell not found, using default" | Out-File $launcherDebugLog -Append
        [System.Windows.Forms.MessageBox]::Show("Could not find x86 PowerShell at: $PSExec. Falling back to default.", "Warning")
        $PSExec = "powershell"
    }

    $WindowHelper = Join-Path $PSScriptRoot "WindowHelper.ps1"
    $YOffset = 300  # smaller window height → tighter grid
    $XOffset = $Script:XOffset
    # Reset window index for deterministic positioning in headless mode
    $Script:WindowIndex = 0

    # Auto-save only when project rows are populated (avoid wiping config in headless use)
    if ($ProjectRows -and $ProjectRows.Count -gt 0) {
        Save-Config
    }

    # Only update once per session
    if ($chkUpdate.Checked -and -not $Script:UpdateDoneThisSession) {
        $codexRunning = Get-Process -Name "codex" -ErrorAction SilentlyContinue
        $claudeRunning = Get-Process -Name "claude" -ErrorAction SilentlyContinue

        # Position update window at 5th grid position (index 4: top-right)
        $UpdatePos = Get-WindowPosition 4 $XOffset $YOffset
        $UpdatePosX = $UpdatePos.X
        $UpdatePosY = $UpdatePos.Y

        if ($codexRunning -or $claudeRunning) {
            $runningTool = if ($codexRunning) { "Codex" } else { "Claude" }
            Start-Process $PSExec -ArgumentList "-NoProfile -Command "". '$WindowHelper' -X $UpdatePosX -Y $UpdatePosY; mode con cols=100 lines=30; `$Host.UI.RawUI.WindowTitle = 'Update Status'; cmd /c color 07; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host '$runningTool is currently running. Skipping update.'; Start-Sleep -Seconds 2""" -Wait
        }
        else {
            Start-Process $PSExec -ArgumentList "-NoProfile -Command "". '$WindowHelper' -X $UpdatePosX -Y $UpdatePosY; mode con cols=100 lines=30; `$Host.UI.RawUI.WindowTitle = 'Update Status'; cmd /c color 07; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host 'Updating tools...'; npm i -g @anthropic-ai/claude-code @openai/codex; Write-Host 'Done.'; Start-Sleep -Seconds 1""" -Wait
        }
        # Mark update as done for this session
        $Script:UpdateDoneThisSession = $true
    }

    foreach ($item in $PlanItems) {
        if (-not $item) { continue }
        $projectPath = if ($item.ProjectPath) { [string]$item.ProjectPath } else { $PSScriptRoot }
        if (-not (Test-Path $projectPath)) {
            Write-Warning "Project path not found for plan item: $projectPath"
            continue
        }

        $cmdText = if ($item.Command) { [string]$item.Command } else { "" }
        if (-not $cmdText) {
            Write-Warning "Missing command for plan item targeting $projectPath"
            continue
        }

        $toolLabel = if ($item.Tool) { [string]$item.Tool } else { "Worker" }
        $typeLabel = if ($item.Type) { [string]$item.Type } else { "" }
        $title = if ($item.Title) {
            [string]$item.Title
        }
        else {
            $guidSegment = ([Guid]::NewGuid().ToString("N")).Substring(0, 6)
            if ($typeLabel) { "$toolLabel - $typeLabel - $guidSegment" } else { "$toolLabel - $guidSegment" }
        }
        $titleSafe = $title -replace '"', ""

        # Calculate column and row for 3x3 grid layout
        # Col = index % 3 (fills left-to-right), Row = floor(index / 3) (then top-to-bottom)
        $Col = $Script:WindowIndex % 3
        $Row = [math]::Floor($Script:WindowIndex / 3) % 3

        $setTitleCmd = "`$Host.UI.RawUI.WindowTitle = '$titleSafe';"

        # Build the full script block: setup (position, resize, colors) + user command
        # Window size and position calculated dynamically for exact 3x3 screen tiling
        $fullScript = @"
# Calculate exact 3x3 screen tiling with no gaps
Add-Type -AssemblyName System.Windows.Forms
`$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
`$col = $Col
`$row = $Row
`$baseWidth = [math]::Ceiling(`$screen.Width / 3)
`$baseHeight = [math]::Ceiling(`$screen.Height / 3)
`$posX = `$col * `$baseWidth
`$posY = `$row * `$baseHeight
# Add overlap to cover Windows shadow/border gaps
`$overlap = 8
# Width: last column extends to edge, others get overlap
if (`$col -eq 2) {
    `$winWidth = `$screen.Width - `$posX
} else {
    `$winWidth = `$baseWidth + `$overlap
}
# Height: last row extends to edge, others get overlap
if (`$row -eq 2) {
    `$winHeight = `$screen.Height - `$posY
} else {
    `$winHeight = `$baseHeight + `$overlap
}
# Resize and position window via WindowHelper (pixel-level via SetWindowPos API)
. '$WindowHelper' -X `$posX -Y `$posY -Width `$winWidth -Height `$winHeight
$setTitleCmd
[Console]::BackgroundColor = 'Black'
[Console]::ForegroundColor = 'Gray'
Clear-Host
Write-Host 'Launching $toolLabel $typeLabel'
$cmdText
"@
        # Encode as Base64 for -EncodedCommand (avoids all escaping issues)
        $encodedScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($fullScript))

        try {
            # Use conhost.exe explicitly to force classic console (bypass Windows Terminal)
            # conhost.exe launches the console host directly, then we run PowerShell inside it
            Start-Process "conhost.exe" -ArgumentList """$PSExec"" -NoExit -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedScript" -WorkingDirectory $projectPath
            Start-Sleep -Milliseconds 200
            $Script:WindowIndex++
        }
        catch {
            $msg = "Error launching plan item for $($projectPath): $($_.Exception.Message)"
            try {
                [System.Windows.Forms.MessageBox]::Show($msg, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            }
            catch {}
            Write-Host $msg -ForegroundColor Red
        }
    }
}

function Launch-Tools($ProjectName, $ProjectPath, $ClaudeCount, $CodexCount, $GeminiCount) {
    # Explicitly cast counts to ensure they are integers
    $ClaudeCount = [int]$ClaudeCount
    $CodexCount = [int]$CodexCount
    $GeminiCount = [int]$GeminiCount

    $CodexMax = if ($GlobalCodexMaxBox) { $GlobalCodexMaxBox.Checked } else { $GlobalCodexMaxDefault }
    $CodexResume = if ($GlobalCodexModeButton) { Get-CodexModeValue $GlobalCodexModeButton } else { $GlobalCodexResumeDefault }

    # Smart Grid Alignment: If we are currently at an odd index (bottom slot),
    # skip to the next even index (top of next column) to ensure the new project
    # starts cleanly in a new column, rather than splitting across columns.
    if ($Script:WindowIndex % 2 -ne 0) {
        $Script:WindowIndex++
    }

    # Determine PowerShell Executable (User prefers x86 for window style)
    $PSExec = Join-Path $Env:SystemRoot "SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $PSExec)) {
        [System.Windows.Forms.MessageBox]::Show("Could not find x86 PowerShell at: $PSExec. Falling back to default.", "Warning")
        $PSExec = "powershell"
    }
    
    $WindowHelper = Join-Path $PSScriptRoot "WindowHelper.ps1"
    $YOffset = 380 # Reverted to original
    $XOffset = $Script:XOffset # Use Calibrated Offset

    # Auto-save on launch
    Save-Config

    # Only update once per session
    if ($chkUpdate.Checked -and -not $Script:UpdateDoneThisSession) {
        $codexRunning = Get-Process -Name "codex" -ErrorAction SilentlyContinue
        $claudeRunning = Get-Process -Name "claude" -ErrorAction SilentlyContinue

        # Position update window at 5th grid position (index 4: top-right)
        $UpdatePos = Get-WindowPosition 4 $XOffset $YOffset
        $UpdatePosX = $UpdatePos.X
        $UpdatePosY = $UpdatePos.Y

        if ($codexRunning -or $claudeRunning) {
            $runningTool = if ($codexRunning) { "Codex" } else { "Claude" }
            Start-Process $PSExec -ArgumentList "-NoProfile -Command "". '$WindowHelper' -X $UpdatePosX -Y $UpdatePosY; mode con cols=100 lines=30; `$Host.UI.RawUI.WindowTitle = 'Update Status'; cmd /c color 07; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host '$runningTool is currently running. Skipping update.'; Start-Sleep -Seconds 2""" -Wait
        }
        else {
            Start-Process $PSExec -ArgumentList "-NoProfile -Command "". '$WindowHelper' -X $UpdatePosX -Y $UpdatePosY; mode con cols=100 lines=30; `$Host.UI.RawUI.WindowTitle = 'Update Status'; cmd /c color 07; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host 'Updating tools...'; npm i -g @anthropic-ai/claude-code @openai/codex; Write-Host 'Done.'; Start-Sleep -Seconds 1""" -Wait
        }
        # Mark update as done for this session
        $Script:UpdateDoneThisSession = $true
    }

    # Verify Path
    if (-not (Test-Path $ProjectPath)) {
        [System.Windows.Forms.MessageBox]::Show("Project path not found: $ProjectPath", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    try {
        if ($ClaudeCount -gt 0) {
            1..$ClaudeCount | ForEach-Object {
                # Calculate position using new logic
                $Pos = Get-WindowPosition $Script:WindowIndex $XOffset $YOffset
                $PosX = $Pos.X
                $PosY = $Pos.Y

                $guidSegment = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
                $windowTitle = "AI Tool Session (x86) - Claude - $guidSegment"

                # Check if Opus is selected
                $isOpus = if ($GlobalClaudeModelButton) { Get-ClaudeModelValue $GlobalClaudeModelButton } else { $false }

                # Build Claude command: use --model flag for Opus, /resume only for Sonnet
                $ClaudeCmd = if ($isOpus) {
                    "claude --dangerously-skip-permissions --model claude-opus-4-5-20251101"
                }
                else {
                    "claude --dangerously-skip-permissions '/resume'"
                }

                # Workaround: Use 'cmd /c start' with a custom title to bypass default PowerShell Blue console properties
                # We use RawUI to set BufferSize (3000 lines) separate from WindowSize (30 lines) to enable scrolling
                $ResizeCmd = ""
                Start-Process "cmd.exe" -ArgumentList "/c start ""$windowTitle"" /D ""$ProjectPath"" ""$PSExec"" -NoProfile -Command "". '$WindowHelper' -X $PosX -Y $PosY; $ResizeCmd [Console]::BackgroundColor = 'Black'; [Console]::ForegroundColor = 'Gray'; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host 'Launching Claude ($_)'; $ClaudeCmd"""

                Start-Sleep -Milliseconds 300
                $Script:WindowIndex++
            }
        }

        if ($CodexCount -gt 0) {
            1..$CodexCount | ForEach-Object {
                # Calculate position using new logic
                $Pos = Get-WindowPosition $Script:WindowIndex $XOffset $YOffset
                $PosX = $Pos.X
                $PosY = $Pos.Y

                $guidSegment = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
                $windowTitle = "AI Tool Session (x86) - Codex - $guidSegment"
                $setTitleCmd = "`$Host.UI.RawUI.WindowTitle = '$windowTitle';"

                # Workaround: Use 'cmd /c start' with a custom title to bypass default PowerShell Blue console properties
                # We use RawUI to set BufferSize (3000 lines) separate from WindowSize (30 lines) to enable scrolling
                $ResizeCmd = ""
                # Build Codex command with bypass flag and optional model/resume
                $CodexCmd = "codex --dangerously-bypass-approvals-and-sandbox"
                if ($CodexMax) {
                    $CodexCmd = "$CodexCmd -m gpt-5.1-codex-max"
                }
                if ($CodexResume) {
                    $CodexCmd = "$CodexCmd resume"
                }
                Start-Process "cmd.exe" -ArgumentList "/c start ""$windowTitle"" /D ""$ProjectPath"" ""$PSExec"" -NoProfile -Command "". '$WindowHelper' -X $PosX -Y $PosY; $ResizeCmd $setTitleCmd [Console]::BackgroundColor = 'Black'; [Console]::ForegroundColor = 'Gray'; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host 'Launching Codex ($_)'; $CodexCmd"""
                Start-Sleep -Milliseconds 200
                $Script:WindowIndex++
            }
        }

        if ($GeminiCount -gt 0) {
            1..$GeminiCount | ForEach-Object {
                # Calculate position using new logic
                $Pos = Get-WindowPosition $Script:WindowIndex $XOffset $YOffset
                $PosX = $Pos.X
                $PosY = $Pos.Y

                $guidSegment = ([Guid]::NewGuid().ToString("N")).Substring(0, 8)
                $windowTitle = "AI Tool Session (x86) - Gemini - $guidSegment"
                $setTitleCmd = "`$Host.UI.RawUI.WindowTitle = '$windowTitle';"
                $ResizeCmd = ""
                Start-Process "cmd.exe" -ArgumentList "/c start ""$windowTitle"" /D ""$ProjectPath"" ""$PSExec"" -NoProfile -Command "". '$WindowHelper' -X $PosX -Y $PosY; $ResizeCmd $setTitleCmd [Console]::BackgroundColor = 'Black'; [Console]::ForegroundColor = 'Gray'; Clear-Host; Write-Host 'Admin Status: ' ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Write-Host 'Launching Gemini ($_)'; gemini"""
                Start-Sleep -Milliseconds 200
                $Script:WindowIndex++
            }
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Error launching tools: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Add-ProjectRow($Name, $Path, $ClaudeCount, $CodexCount, $AutoLaunch, $GeminiCount, $GeminiRemember = $false) {
    # Card Panel
    $RowPanel = New-Object System.Windows.Forms.Panel
    $RowPanel.Size = New-Object System.Drawing.Size(900, 60)
    $RowPanel.BackColor = $ColorPanel
    $RowPanel.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 15) # Spacing between cards

    # Draw subtle border
    $RowPanel.add_Paint({
            $g = $_.Graphics
            $pen = New-Object System.Drawing.Pen($ColorBorder, 1)
            $rect = New-Object System.Drawing.Rectangle(0, 0, 899, 59)
            $g.DrawRectangle($pen, $rect)
        })

    # Name TextBox
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Text = $Name
    $txtName.Location = New-Object System.Drawing.Point(10, 18)
    $txtName.Size = New-Object System.Drawing.Size(130, 26)
    $txtName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtName.Font = $FontMain

    # Path TextBox
    $txtPath = New-Object System.Windows.Forms.TextBox
    $txtPath.Text = $Path
    $txtPath.Location = New-Object System.Drawing.Point(150, 18)
    $txtPath.Size = New-Object System.Drawing.Size(220, 26)
    $txtPath.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $txtPath.Font = $FontMain

    # Auto Launch Checkbox
    $chkAuto = New-Object System.Windows.Forms.CheckBox
    $chkAuto.Text = ""
    $chkAuto.Checked = if ($AutoLaunch -ne $false) { $true } else { $false } # Default to true if null
    $chkAuto.Location = New-Object System.Drawing.Point(395, 20)
    $chkAuto.Size = New-Object System.Drawing.Size(20, 24)

    # Timer for delayed counter reset (5 seconds after last click)
    $resetTimer = New-Object System.Windows.Forms.Timer
    $resetTimer.Interval = 5000 # 5 seconds
    [void]$Script:AllTimers.Add($resetTimer) # Keep alive

    # Timer for delayed launch (1 second after last click to avoid lag)
    $launchTimer = New-Object System.Windows.Forms.Timer
    $launchTimer.Interval = 1000 # 1 second
    [void]$Script:AllTimers.Add($launchTimer) # Keep alive

    # Claude Count Button (Roman numerals)
    $btnClaude = New-Object System.Windows.Forms.Button
    $btnClaude.Location = New-Object System.Drawing.Point(430, 18)
    $btnClaude.Size = New-Object System.Drawing.Size(50, 26)
    $btnClaude.Font = $FontMain
    $btnClaude.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnClaude.FlatAppearance.BorderSize = 1
    $btnClaude.BackColor = $ColorPanel
    $btnClaude.ForeColor = [System.Drawing.Color]::Black
    $btnClaude.UseVisualStyleBackColor = $false
    $btnClaude.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-GeminiCountButtonValue $btnClaude (if ($GeminiRemember -and ($null -ne $ClaudeCount)) { [int]$ClaudeCount } else { 0 })

    # Codex Count Button (Roman numerals)
    $btnCodex = New-Object System.Windows.Forms.Button
    $btnCodex.Location = New-Object System.Drawing.Point(500, 18)
    $btnCodex.Size = New-Object System.Drawing.Size(50, 26)
    $btnCodex.Font = $FontMain
    $btnCodex.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCodex.FlatAppearance.BorderSize = 1
    $btnCodex.BackColor = $ColorPanel
    $btnCodex.ForeColor = [System.Drawing.Color]::Black
    $btnCodex.UseVisualStyleBackColor = $false
    $btnCodex.Cursor = [System.Windows.Forms.Cursors]::Hand
    Set-GeminiCountButtonValue $btnCodex (if ($GeminiRemember -and ($null -ne $CodexCount)) { [int]$CodexCount } else { 0 })

    # Remember Count Checkbox
    $chkGeminiRemember = New-Object System.Windows.Forms.CheckBox
    $chkGeminiRemember.Text = ""
    $chkGeminiRemember.Checked = if ($GeminiRemember) { $true } else { $false }
    $chkGeminiRemember.Location = New-Object System.Drawing.Point(670, 20)
    $chkGeminiRemember.Size = New-Object System.Drawing.Size(20, 24)
    $chkGeminiRemember.Tag = @($btnClaude, $btnCodex)
    $chkGeminiRemember.Add_CheckedChanged({
            if (-not $this.Checked) {
                foreach ($btn in $this.Tag) {
                    Set-GeminiCountButtonValue $btn 0
                }
            }
        })

    # Delete Button (Icon style)
    $btnDel = New-Object System.Windows.Forms.Button
    $btnDel.Text = "×"
    $btnDel.Font = New-Object System.Drawing.Font("Arial", 16)
    $btnDel.Location = New-Object System.Drawing.Point(710, 12)
    $btnDel.Size = New-Object System.Drawing.Size(25, 36)
    $btnDel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDel.FlatAppearance.BorderSize = 0
    $btnDel.BackColor = "Transparent"
    # Hover effect
    $btnDel.Add_MouseEnter({ $this.ForeColor = $ColorDanger })
    $btnDel.Add_MouseLeave({ $this.ForeColor = $ColorSubText })

    # Data Packet
    $RowData = @{
        NameBox = $txtName; PathBox = $txtPath;
        ClaudeBox = $btnClaude; CodexBox = $btnCodex;
        AutoBox = $chkAuto;
        GeminiRememberBox = $chkGeminiRemember;
        Panel = $RowPanel;
        ResetTimer = $resetTimer;
        LaunchTimer = $launchTimer
    }

    # Timer tick event - reset counters after 5 seconds of no clicks
    $resetTimer.Add_Tick({
            param($sender, $e)
            $sender.Stop()
            if (-not $RowData.GeminiRememberBox.Checked) {
                Set-GeminiCountButtonValue $RowData.ClaudeBox 0
                Set-GeminiCountButtonValue $RowData.CodexBox 0
            }
        }.GetNewClosure())

    # Launch timer tick event - launch tools after 1 second delay
    $launchTimer.Add_Tick({
            param($sender, $e)
            $sender.Stop()

            # Stop reset timer to avoid conflicts
            $RowData.ResetTimer.Stop()

            $claudeCount = Get-GeminiCountButtonValue $RowData.ClaudeBox
            $codexCount = Get-GeminiCountButtonValue $RowData.CodexBox

            # Launch tools if any count is greater than 0
            if ($claudeCount -gt 0 -or $codexCount -gt 0) {
                Launch-Tools $RowData.NameBox.Text $RowData.PathBox.Text $claudeCount $codexCount 0
                # Move project to top
                Move-ProjectToTop $RowData
                # Reset counters after launching (unless Remember is checked)
                if (-not $RowData.GeminiRememberBox.Checked) {
                    Set-GeminiCountButtonValue $RowData.ClaudeBox 0
                    Set-GeminiCountButtonValue $RowData.CodexBox 0
                }
            }
        }.GetNewClosure())

    # Click handler for count buttons - increment counter and delay launch
    $btnClaude.Add_Click({
            $current = Get-GeminiCountButtonValue $btnClaude
            $next = $current + 1
            if ($next -gt 10) { $next = 0 }
            Set-GeminiCountButtonValue $btnClaude $next
            # Restart the launch timer (1 second delay before launch)
            $RowData.LaunchTimer.Stop()
            $RowData.LaunchTimer.Start()
            # Restart the reset timer
            $RowData.ResetTimer.Stop()
            $RowData.ResetTimer.Start()
        }.GetNewClosure())
    $btnClaude.Add_MouseUp({
            if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
            $current = Get-GeminiCountButtonValue $btnClaude
            $next = $current - 1
            if ($next -lt 0) { $next = 0 }
            Set-GeminiCountButtonValue $btnClaude $next
            # Restart the launch timer on right-click too
            $RowData.LaunchTimer.Stop()
            $RowData.LaunchTimer.Start()
            # Restart the reset timer on right-click too
            $RowData.ResetTimer.Stop()
            $RowData.ResetTimer.Start()
        }.GetNewClosure())

    $btnCodex.Add_Click({
            $current = Get-GeminiCountButtonValue $btnCodex
            $next = $current + 1
            if ($next -gt 10) { $next = 0 }
            Set-GeminiCountButtonValue $btnCodex $next
            # Restart the launch timer (1 second delay before launch)
            $RowData.LaunchTimer.Stop()
            $RowData.LaunchTimer.Start()
            # Restart the reset timer
            $RowData.ResetTimer.Stop()
            $RowData.ResetTimer.Start()
        }.GetNewClosure())
    $btnCodex.Add_MouseUp({
            if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
            $current = Get-GeminiCountButtonValue $btnCodex
            $next = $current - 1
            if ($next -lt 0) { $next = 0 }
            Set-GeminiCountButtonValue $btnCodex $next
            # Restart the launch timer on right-click too
            $RowData.LaunchTimer.Stop()
            $RowData.LaunchTimer.Start()
            # Restart the reset timer on right-click too
            $RowData.ResetTimer.Stop()
            $RowData.ResetTimer.Start()
        }.GetNewClosure())

    $btnDel.Tag = $RowData
    $btnDel.Add_Click({
            $d = $this.Tag
            $d.ResetTimer.Stop()
            $d.ResetTimer.Dispose()
            $d.LaunchTimer.Stop()
            $d.LaunchTimer.Dispose()
            $ProjectsPanel.Controls.Remove($d.Panel)
            $ProjectRows.Remove($d)
            $d.Panel.Dispose()
        })

    # Add Controls
    $RowPanel.Controls.Add($txtName)
    $RowPanel.Controls.Add($txtPath)
    $RowPanel.Controls.Add($chkAuto)
    $RowPanel.Controls.Add($btnClaude)
    $RowPanel.Controls.Add($btnCodex)
    $RowPanel.Controls.Add($chkGeminiRemember)
    $RowPanel.Controls.Add($btnDel)

    $ProjectsPanel.Controls.Add($RowPanel)
    $ProjectRows.Add($RowData) | Out-Null
}

# Headless command-plan mode (used by /go integration)
if ($CommandPlan) {
    try {
        $planItems = $CommandPlan | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to parse CommandPlan JSON: $($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Exit 1
    }
    Launch-CommandPlan $planItems
    Exit
}

# Load existing projects
if ($Config.Projects) {
    foreach ($p in $Config.Projects) {
        $cCount = if ($null -ne $p.ClaudeCount) { $p.ClaudeCount } else { 1 }
        $xCount = if ($null -ne $p.CodexCount) { $p.CodexCount } else { 1 }
        $auto = if ($p.PSObject.Properties.Match('AutoLaunch').Count) { $p.AutoLaunch } else { $true }
        $gCount = if ($p.PSObject.Properties.Match('GeminiCount').Count) { $p.GeminiCount } else { 0 }
        $gRemember = if ($p.PSObject.Properties.Match('GeminiRemember').Count) { [bool]$p.GeminiRemember } else { $true }
        Add-ProjectRow $p.Name $p.Path $cCount $xCount $auto $gCount $gRemember
    }
}

# Add Button Event
$btnAdd.Add_Click({ Add-ProjectRow "New Project" "E:\" 1 1 $true 0 })

# Update Save-Config to include AutoLaunch
function Save-Config {
    $NewProjects = @()
    foreach ($row in $ProjectRows) {
        $NewProjects += @{
            Name           = $row.NameBox.Text
            Path           = $row.PathBox.Text
            ClaudeCount    = if ($row.GeminiRememberBox.Checked) { Get-GeminiCountButtonValue $row.ClaudeBox } else { 0 }
            CodexCount     = if ($row.GeminiRememberBox.Checked) { Get-GeminiCountButtonValue $row.CodexBox } else { 0 }
            GeminiCount    = if ($row.GeminiRememberBox.Checked) { Get-GeminiCountButtonValue $row.GeminiBox } else { 0 }
            GeminiRemember = $row.GeminiRememberBox.Checked
            AutoLaunch     = $row.AutoBox.Checked
        }
    }
    $NewConfig = @{
        Projects          = $NewProjects
        StartWithWindows  = $Config.StartWithWindows # Use Config value as checkbox is now in dialog
        WindowOffset      = $Script:XOffset
        ScheduleEnabled   = $Config.ScheduleEnabled
        ScheduleTime      = $Config.ScheduleTime
        CodexMaxGlobal    = if ($GlobalCodexMaxBox) { $GlobalCodexMaxBox.Checked } else { $GlobalCodexMaxDefault }
        CodexResumeGlobal = if ($GlobalCodexModeButton) { Get-CodexModeValue $GlobalCodexModeButton } else { $GlobalCodexResumeDefault }
        ClaudeModelOpus   = if ($GlobalClaudeModelButton) { Get-ClaudeModelValue $GlobalClaudeModelButton } else { $GlobalClaudeModelDefault }
    }
    $NewConfig | ConvertTo-Json | Set-Content $ConfigPath

    # Handle Startup Shortcut
    $StartupPath = "$Env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\AI Tool Launcher.lnk"
    if ($Config.StartWithWindows) {
        # Create shortcut if it doesn't exist
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut($StartupPath)
        $Shortcut.TargetPath = Join-Path $PSScriptRoot "Launcher.exe"
        $Shortcut.Arguments = "-AutoLaunch" # Pass AutoLaunch flag
        $Shortcut.WorkingDirectory = $PSScriptRoot
        $Shortcut.Save()
    }
    else {
        # Remove shortcut if it exists
        if (Test-Path $StartupPath) {
            Remove-Item $StartupPath -Force
        }
    }
}

# Auto-Launch Logic
if ($AutoLaunch) {
    if ($Config.Projects) {
        foreach ($p in $Config.Projects) {
            # Check for AutoLaunch property, default to true if missing (backward compatibility)
            $shouldLaunch = if ($p.PSObject.Properties.Match('AutoLaunch').Count) { $p.AutoLaunch } else { $true }
            
            if ($shouldLaunch) {
                $cCount = if ($null -ne $p.ClaudeCount) { $p.ClaudeCount } else { 1 }
                $xCount = if ($null -ne $p.CodexCount) { $p.CodexCount } else { 1 }
                $gCount = if ($p.PSObject.Properties.Match('GeminiCount').Count) { $p.GeminiCount } else { 0 }
                Launch-Tools $p.Name $p.Path $cCount $xCount $gCount
            }
        }
    }
    Exit
}
else {
    # Show Form
    $Form.ShowDialog()
}
