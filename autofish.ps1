#Requires -Version 5.0
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    powershell -STA -File $MyInvocation.MyCommand.Path
    return
}

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

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

public class ScreenCapture {
    public static int CountBrightPixels(int x, int y, int w, int h, int threshold) {
        using (Bitmap bmp = new Bitmap(w, h)) {
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.CopyFromScreen(x, y, 0, 0, new Size(w, h));
            }
            Rectangle rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = data.Stride;
            byte[] pixels = new byte[stride * bmp.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            bmp.UnlockBits(data);
            int bright = 0;
            int len = (pixels.Length / 3) * 3;
            for (int i = 0; i < len; i += 3) {
                int luma = (pixels[i + 2] * 299 + pixels[i + 1] * 587 + pixels[i] * 114) / 1000;
                if (luma > threshold) bright++;
            }
            return bright;
        }
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing"

$script:f = $false; $script:st = 0; $script:tk = 0; $script:wait = 3; $script:reel = 15
$script:prevF3 = $false; $script:prevF4 = $false; $script:detectTick = 0

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoFish Spin"
$form.Size = [System.Drawing.Size]::new(400, 300)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.Text = "Ожидание (с):"; $lbl1.Location = [System.Drawing.Point]::new(15, 15); $lbl1.Size = [System.Drawing.Size]::new(120, 25)
$form.Controls.Add($lbl1)

$numWait = New-Object System.Windows.Forms.NumericUpDown
$numWait.Location = [System.Drawing.Point]::new(140, 13); $numWait.Size = [System.Drawing.Size]::new(60, 25)
$numWait.Minimum = 1; $numWait.Maximum = 30; $numWait.Value = 3
$form.Controls.Add($numWait)

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = "Мотка (с):"; $lbl2.Location = [System.Drawing.Point]::new(15, 50); $lbl2.Size = [System.Drawing.Size]::new(120, 25)
$form.Controls.Add($lbl2)

$numReel = New-Object System.Windows.Forms.NumericUpDown
$numReel.Location = [System.Drawing.Point]::new(140, 48); $numReel.Size = [System.Drawing.Size]::new(60, 25)
$numReel.Minimum = 1; $numReel.Maximum = 60; $numReel.Value = 15
$form.Controls.Add($numReel)

$txtStatus = New-Object System.Windows.Forms.TextBox
$txtStatus.Name = "txtStatus"
$txtStatus.Text = "Остановлен"
$txtStatus.Location = [System.Drawing.Point]::new(15, 85); $txtStatus.Size = [System.Drawing.Size]::new(360, 25)
$txtStatus.ForeColor = [System.Drawing.Color]::Red
$txtStatus.Font = [System.Drawing.Font]::new("Arial", 10, [System.Drawing.FontStyle]::Bold)
$txtStatus.ReadOnly = $true
$txtStatus.BackColor = [System.Drawing.Color]::White
$txtStatus.BorderStyle = "FixedSingle"
$form.Controls.Add($txtStatus)

# Detection region settings
$lblDetect = New-Object System.Windows.Forms.Label
$lblDetect.Text = "Область захвата (X,Y,W,H):"
$lblDetect.Location = [System.Drawing.Point]::new(15, 120); $lblDetect.Size = [System.Drawing.Size]::new(200, 20)
$form.Controls.Add($lblDetect)

$numDX = New-Object System.Windows.Forms.NumericUpDown
$numDX.Location = [System.Drawing.Point]::new(15, 145); $numDX.Size = [System.Drawing.Size]::new(60, 25)
$numDX.Minimum = 0; $numDX.Maximum = 3840; $numDX.Value = 800
$form.Controls.Add($numDX)

$numDY = New-Object System.Windows.Forms.NumericUpDown
$numDY.Location = [System.Drawing.Point]::new(85, 145); $numDY.Size = [System.Drawing.Size]::new(60, 25)
$numDY.Minimum = 0; $numDY.Maximum = 2160; $numDY.Value = 900
$form.Controls.Add($numDY)

$numDW = New-Object System.Windows.Forms.NumericUpDown
$numDW.Location = [System.Drawing.Point]::new(155, 145); $numDW.Size = [System.Drawing.Size]::new(60, 25)
$numDW.Minimum = 10; $numDW.Maximum = 500; $numDW.Value = 157
$form.Controls.Add($numDW)

$numDH = New-Object System.Windows.Forms.NumericUpDown
$numDH.Location = [System.Drawing.Point]::new(225, 145); $numDH.Size = [System.Drawing.Size]::new(60, 25)
$numDH.Minimum = 1; $numDH.Maximum = 100; $numDH.Value = 4
$form.Controls.Add($numDH)

$lblThresh = New-Object System.Windows.Forms.Label
$lblThresh.Text = "Порог яркости:"
$lblThresh.Location = [System.Drawing.Point]::new(15, 180); $lblThresh.Size = [System.Drawing.Size]::new(100, 20)
$form.Controls.Add($lblThresh)

$numThresh = New-Object System.Windows.Forms.NumericUpDown
$numThresh.Location = [System.Drawing.Point]::new(120, 178); $numThresh.Size = [System.Drawing.Size]::new(60, 25)
$numThresh.Minimum = 10; $numThresh.Maximum = 255; $numThresh.Value = 120
$form.Controls.Add($numThresh)

function StartFish {
    $script:wait = [int]$numWait.Value
    $script:reel = [int]$numReel.Value
    $script:f = $true; $script:st = 1; $script:tk = 0; $script:detectTick = 0
    $btnStart.Text = "Стоп"
    $txtStatus.Text = "Заброс..."; $txtStatus.ForeColor = "Green"
}

function StopFish {
    $script:f = $false; $script:st = 0; $script:tk = 0
    [WinAPI]::Rel()
    $btnStart.Text = "Старт"; $txtStatus.Text = "Остановлен"; $txtStatus.ForeColor = "Red"
}

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text = "Скан"; $btnTest.Location = [System.Drawing.Point]::new(270, 145); $btnTest.Size = [System.Drawing.Size]::new(100, 25)
$btnTest.Add_Click({
    $dx = [int]$numDX.Value; $dy = [int]$numDY.Value
    $dw = [int]$numDW.Value; $dh = [int]$numDH.Value
    $thresh = [int]$numThresh.Value
    try {
        $bright = [ScreenCapture]::CountBrightPixels($dx, $dy, $dw, $dh, $thresh)
        $total = $dw * $dh; $pct = [Math]::Round($bright / $total * 100, 1)
        $bmp = New-Object System.Drawing.Bitmap($dw, $dh)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($dx, $dy, 0, 0, [System.Drawing.Size]::new($dw, $dh))
        $g.Dispose()
        $path = "$env:USERPROFILE\Desktop\autofish_scan.png"
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $txtStatus.Text = "Ярких $bright/$total ($pct%). Скрин: $path"
    } catch {
        $txtStatus.Text = "Ошибка: $_"
    }
})
$form.Controls.Add($btnTest)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Старт"; $btnStart.Location = [System.Drawing.Point]::new(60, 215); $btnStart.Size = [System.Drawing.Size]::new(80, 30)
$btnStart.Add_Click({
    if ($script:f) { StopFish } else { StartFish }
})
$form.Controls.Add($btnStart)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Выход"; $btnExit.Location = [System.Drawing.Point]::new(170, 215); $btnExit.Size = [System.Drawing.Size]::new(80, 30)
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

$tm = New-Object System.Windows.Forms.Timer
$tm.Interval = 100
$tm.Add_Tick({
    $f3 = [WinAPI]::KeyDown(0x72); $f4 = [WinAPI]::KeyDown(0x73)

    if ($f3 -and -not $script:prevF3 -and -not $script:f) { StartFish }
    if ($f4 -and -not $script:prevF4 -and $script:f) { StopFish }

    $script:prevF3 = $f3; $script:prevF4 = $f4

    if (-not $script:f) { return }

    if ($script:st -eq 1) {
        if ($script:tk -eq 0) { [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD) }
        $script:tk++
        if ($script:tk -ge 10) {
            [WinAPI]::SK(0x10, 2); [WinAPI]::SM([WinAPI]::LMU)
            $script:st = 2; $script:tk = 0
            $txtStatus.Text = "Ожидание $($script:wait)с..."
        }
    } elseif ($script:st -eq 2) {
        $script:tk++
        if ($script:tk -ge ($script:wait * 10)) {
            $script:st = 3; $script:tk = 0; $script:detectTick = 0
            [WinAPI]::SM([WinAPI]::LMD)
            $txtStatus.Text = "Мотка..."
        }
    } elseif ($script:st -eq 3) {
        $script:tk++; $script:detectTick++
        # Check screen every 500ms (5 ticks)
        if ($script:detectTick -ge 5) {
            $script:detectTick = 0
            $dx = [int]$numDX.Value; $dy = [int]$numDY.Value
            $dw = [int]$numDW.Value; $dh = [int]$numDH.Value
            $thresh = [int]$numThresh.Value
            try {
                $bright = [ScreenCapture]::CountBrightPixels($dx, $dy, $dw, $dh, $thresh)
                $total = $dw * $dh
                $pct = $bright / $total
                # If > 5% bright pixels -> text detected
                if ($pct -gt 0.05) {
                    [WinAPI]::SM([WinAPI]::LMU)
                    $script:st = 1; $script:tk = 0
                    [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                    $txtStatus.Text = "Заброс..."
                }
            } catch {
                # ignore capture errors
            }
        }
        # Safety timeout (макс 60с)
        if ($script:tk -ge 600) {
            [WinAPI]::SM([WinAPI]::LMU)
            $script:st = 1; $script:tk = 0
            [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
            $txtStatus.Text = "Заброс..."
        }
    }
})
$tm.Start()

[System.Windows.Forms.Application]::Run($form)
