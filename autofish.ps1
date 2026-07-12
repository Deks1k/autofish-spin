#Requires -Version 5.0
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    powershell -STA -File $MyInvocation.MyCommand.Path
    return
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Drawing;

[StructLayout(LayoutKind.Sequential)]
public struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Sequential)]
public struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo; }
[StructLayout(LayoutKind.Explicit)]
public struct MKI {
    [FieldOffset(0)] public MOUSEINPUT mi;
    [FieldOffset(0)] public KEYBDINPUT ki;
}
[StructLayout(LayoutKind.Sequential)]
public struct INPUT { public int type; public MKI ui; }

public class WinAPI {
    [DllImport("user32.dll")] public static extern uint SendInput(uint n, INPUT[] i, int s);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);

    public const uint LMD = 0x0002, LMU = 0x0004;
    public const uint KU = 0x0002;
    public const int IM = 0, IK = 1;

    public static void SM(uint f) { INPUT[] i = new INPUT[1]; i[0].type = IM; i[0].ui.mi.dwFlags = f; SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static void SK(ushort vk, uint f) { INPUT[] i = new INPUT[1]; i[0].type = IK; i[0].ui.ki.wVk = vk; i[0].ui.ki.dwFlags = f; SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static void Rel() { SK(0x10, KU); SM(LMU); }
    public static bool KeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing"

$script:f = $false
$script:st = 0
$script:tk = 0
$script:tm = $null

function StopFish {
    $script:f = $false; $script:st = 0; $script:tk = 0
    if ($script:tm) { $script:tm.Stop() }
    [WinAPI]::Rel()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoFish Spin"
$form.Size = [System.Drawing.Size]::new(320, 220)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.Text = "Ожидание (с):"
$lbl1.Location = [System.Drawing.Point]::new(15, 15); $lbl1.Size = [System.Drawing.Size]::new(120, 25)
$form.Controls.Add($lbl1)

$numWait = New-Object System.Windows.Forms.NumericUpDown
$numWait.Location = [System.Drawing.Point]::new(140, 13); $numWait.Size = [System.Drawing.Size]::new(60, 25)
$numWait.Minimum = 1; $numWait.Maximum = 30; $numWait.Value = 3
$form.Controls.Add($numWait)

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = "Мотка (с):"
$lbl2.Location = [System.Drawing.Point]::new(15, 50); $lbl2.Size = [System.Drawing.Size]::new(120, 25)
$form.Controls.Add($lbl2)

$numReel = New-Object System.Windows.Forms.NumericUpDown
$numReel.Location = [System.Drawing.Point]::new(140, 48); $numReel.Size = [System.Drawing.Size]::new(60, 25)
$numReel.Minimum = 1; $numReel.Maximum = 60; $numReel.Value = 15
$form.Controls.Add($numReel)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Name = "lblStatus"
$lblStatus.Text = "Остановлен"
$lblStatus.Location = [System.Drawing.Point]::new(15, 85)
$lblStatus.Size = [System.Drawing.Size]::new(280, 25)
$lblStatus.ForeColor = [System.Drawing.Color]::Red
$lblStatus.Font = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblStatus)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Старт"
$btnStart.Location = [System.Drawing.Point]::new(60, 125); $btnStart.Size = [System.Drawing.Size]::new(80, 30)
$btnStart.Add_Click({
    if ($script:f) { StopFish; $btnStart.Text = "Старт"; $lblStatus.Text = "Остановлен"; $lblStatus.ForeColor = "Red"; return }
    $wait = [int]$numWait.Value
    $reel = [int]$numReel.Value
    $script:f = $true; $script:st = 1; $script:tk = 0
    $btnStart.Text = "Стоп"
    $lblStatus.Text = "Заброс..."; $lblStatus.ForeColor = "Green"

    $script:tm = New-Object System.Windows.Forms.Timer
    $script:tm.Interval = 100
    $script:tm.Add_Tick({
        if (-not $script:f) { $script:tm.Stop(); return }

        if ([WinAPI]::KeyDown(0x72) -and -not $script:prevF3) { $btnStart.PerformClick() }
        if ([WinAPI]::KeyDown(0x73) -and -not $script:prevF4) { if ($script:f) { $btnStart.PerformClick() } }
        $script:prevF3 = [WinAPI]::KeyDown(0x72)
        $script:prevF4 = [WinAPI]::KeyDown(0x73)

        if ($script:st -eq 1) {
            if ($script:tk -eq 0) { [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD) }
            $script:tk++
            if ($script:tk -ge 10) {
                [WinAPI]::SK(0x10, 2); [WinAPI]::SM([WinAPI]::LMU)
                $script:st = 2; $script:tk = 0
                $lblStatus.Text = "Ожидание ${wait}с..."
            }
        }
        elseif ($script:st -eq 2) {
            $script:tk++
            if ($script:tk -ge ($wait * 10)) {
                $script:st = 3; $script:tk = 0
                [WinAPI]::SM([WinAPI]::LMD)
                $lblStatus.Text = "Мотка ${reel}с..."
            }
        }
        elseif ($script:st -eq 3) {
            $script:tk++
            if ($script:tk -ge ($reel * 10)) {
                [WinAPI]::SM([WinAPI]::LMU)
                $script:st = 1; $script:tk = 0
                [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                $lblStatus.Text = "Заброс..."; $lblStatus.Refresh()
            }
        }
    })
    $script:tm.Start()
})
$form.Controls.Add($btnStart)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Выход"
$btnExit.Location = [System.Drawing.Point]::new(170, 125); $btnExit.Size = [System.Drawing.Size]::new(80, 30)
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

[System.Windows.Forms.Application]::Run($form)
