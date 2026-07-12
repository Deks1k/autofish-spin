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
            using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
            Rectangle rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = data.Stride;
            byte[] pixels = new byte[stride * bmp.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            bmp.UnlockBits(data);
            int bright = 0, len = (pixels.Length / 3) * 3;
            for (int i = 0; i < len; i += 3) {
                int luma = (pixels[i + 2] * 299 + pixels[i + 1] * 587 + pixels[i] * 114) / 1000;
                if (luma > threshold) bright++;
            }
            return bright;
        }
    }
    public static int[] CaptureLuma(int x, int y, int w, int h) {
        using (Bitmap bmp = new Bitmap(w, h)) {
            using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
            Rectangle rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = data.Stride;
            byte[] pixels = new byte[stride * bmp.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            bmp.UnlockBits(data);
            int len = (pixels.Length / 3) * 3, idx = 0;
            int[] luma = new int[len / 3];
            for (int i = 0; i < len; i += 3)
                luma[idx++] = (pixels[i + 2] * 299 + pixels[i + 1] * 587 + pixels[i] * 114) / 1000;
            return luma;
        }
    }
    public static double MatchLuma(int[] refLuma, int x, int y, int w, int h, int tolerance) {
        using (Bitmap bmp = new Bitmap(w, h)) {
            using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(x, y, 0, 0, new Size(w, h)); }
            Rectangle rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            int stride = data.Stride;
            byte[] pixels = new byte[stride * bmp.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);
            bmp.UnlockBits(data);
            int match = 0, len = (pixels.Length / 3) * 3, idx = 0, total = refLuma.Length;
            for (int i = 0; i < len && idx < total; i += 3) {
                int luma = (pixels[i + 2] * 299 + pixels[i + 1] * 587 + pixels[i] * 114) / 1000;
                if (Math.Abs(luma - refLuma[idx++]) <= tolerance) match++;
            }
            return (double)match / total;
        }
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing"

$script:f = $false; $script:st = 0; $script:tk = 0; $script:wait = 3; $script:reel = 15
$script:prevF3 = $false; $script:prevF4 = $false; $script:prevF5 = $false; $script:prevF6 = $false
$script:detectTick = 0; $script:detectHit = 0; $script:scanning = $false
$script:refPixels = $null; $script:hasRef = $false

# Mode-specific settings
$script:bx = 900; $script:by = 1380; $script:bw = 110; $script:bh = 18; $script:bt = 120
$script:rx = 853; $script:ry = 1382; $script:rw = 155; $script:rh = 18

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoFish Spin"
$form.Size = [System.Drawing.Size]::new(400, 370)
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
$txtStatus.Location = [System.Drawing.Point]::new(15, 85); $txtStatus.Size = [System.Drawing.Size]::new(360, 40)
$txtStatus.ForeColor = [System.Drawing.Color]::Red
$txtStatus.Font = [System.Drawing.Font]::new("Arial", 9)
$txtStatus.ReadOnly = $true; $txtStatus.BackColor = [System.Drawing.Color]::White
$txtStatus.BorderStyle = "FixedSingle"; $txtStatus.Multiline = $true
$form.Controls.Add($txtStatus)

$lblDetect = New-Object System.Windows.Forms.Label
$lblDetect.Text = "Область захвата (X,Y,W,H):"
$lblDetect.Location = [System.Drawing.Point]::new(15, 135); $lblDetect.Size = [System.Drawing.Size]::new(200, 20)
$form.Controls.Add($lblDetect)

$numDX = New-Object System.Windows.Forms.NumericUpDown
$numDX.Location = [System.Drawing.Point]::new(15, 160); $numDX.Size = [System.Drawing.Size]::new(60, 25)
$numDX.Minimum = 0; $numDX.Maximum = 3840; $numDX.Value = 900
$form.Controls.Add($numDX)

$numDY = New-Object System.Windows.Forms.NumericUpDown
$numDY.Location = [System.Drawing.Point]::new(85, 160); $numDY.Size = [System.Drawing.Size]::new(60, 25)
$numDY.Minimum = 0; $numDY.Maximum = 2160; $numDY.Value = 1380
$form.Controls.Add($numDY)

$numDW = New-Object System.Windows.Forms.NumericUpDown
$numDW.Location = [System.Drawing.Point]::new(155, 160); $numDW.Size = [System.Drawing.Size]::new(60, 25)
$numDW.Minimum = 10; $numDW.Maximum = 500; $numDW.Value = 110
$form.Controls.Add($numDW)

$numDH = New-Object System.Windows.Forms.NumericUpDown
$numDH.Location = [System.Drawing.Point]::new(225, 160); $numDH.Size = [System.Drawing.Size]::new(60, 25)
$numDH.Minimum = 1; $numDH.Maximum = 100; $numDH.Value = 18
$form.Controls.Add($numDH)

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = "Режим:"; $lblMode.Location = [System.Drawing.Point]::new(15, 195); $lblMode.Size = [System.Drawing.Size]::new(50, 20)
$form.Controls.Add($lblMode)

$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = [System.Drawing.Point]::new(65, 193); $cmbMode.Size = [System.Drawing.Size]::new(100, 25)
$cmbMode.DropDownStyle = "DropDownList"
$cmbMode.Items.Add("Яркость"); $cmbMode.Items.Add("Эталон")
$cmbMode.SelectedIndex = 0

$lblThresh = New-Object System.Windows.Forms.Label
$lblThresh.Text = "Порог яркости:"
$lblThresh.Location = [System.Drawing.Point]::new(180, 195); $lblThresh.Size = [System.Drawing.Size]::new(100, 20)
$form.Controls.Add($lblThresh)

$numThresh = New-Object System.Windows.Forms.NumericUpDown
$numThresh.Location = [System.Drawing.Point]::new(280, 193); $numThresh.Size = [System.Drawing.Size]::new(60, 25)
$numThresh.Minimum = 10; $numThresh.Maximum = 255; $numThresh.Value = 120
$form.Controls.Add($numThresh)

# Save/load settings on mode switch
$cmbMode.Add_SelectedIndexChanged({
    $mode = $cmbMode.SelectedItem
    # Save current values to previous mode
    if ($script:prevMode -eq "Яркость") {
        $script:bx = [int]$numDX.Value; $script:by = [int]$numDY.Value
        $script:bw = [int]$numDW.Value; $script:bh = [int]$numDH.Value
        $script:bt = [int]$numThresh.Value
    } elseif ($script:prevMode -eq "Эталон") {
        $script:rx = [int]$numDX.Value; $script:ry = [int]$numDY.Value
        $script:rw = [int]$numDW.Value; $script:rh = [int]$numDH.Value
    }
    # Load values for new mode
    if ($mode -eq "Яркость") {
        $numDX.Value = $script:bx; $numDY.Value = $script:by
        $numDW.Value = $script:bw; $numDH.Value = $script:bh
        $numThresh.Value = $script:bt
    } else {
        $numDX.Value = $script:rx; $numDY.Value = $script:ry
        $numDW.Value = $script:rw; $numDH.Value = $script:rh
    }
    $script:prevMode = $mode
})
$form.Controls.Add($cmbMode)
$script:prevMode = "Яркость"

function StartFish {
    $script:wait = [int]$numWait.Value; $script:reel = [int]$numReel.Value
    $script:f = $true; $script:st = 1; $script:tk = 0; $script:detectTick = 0; $script:detectHit = 0
    $btnStart.Text = "Стоп"
    $txtStatus.Text = "Заброс..."; $txtStatus.ForeColor = "Green"
}

function StopFish {
    $script:f = $false; $script:st = 0; $script:tk = 0
    [WinAPI]::Rel()
    $btnStart.Text = "Старт"; $txtStatus.Text = "Остановлен"; $txtStatus.ForeColor = "Red"
}

function Scan {
    if ($script:scanning) { return }
    $script:scanning = $true
    $mode = $cmbMode.SelectedItem; $dx = [int]$numDX.Value; $dy = [int]$numDY.Value
    $dw = [int]$numDW.Value; $dh = [int]$numDH.Value
    try {
        if ($mode -eq "Эталон" -and $script:hasRef) {
            $match = [ScreenCapture]::MatchLuma($script:refPixels, $dx, $dy, $dw, $dh, 30)
            $pct = [Math]::Round($match * 100, 1)
            $bmp = New-Object System.Drawing.Bitmap($dw, $dh)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($dx, $dy, 0, 0, [System.Drawing.Size]::new($dw, $dh))
            $g.Dispose()
            $path = "E:\Project\autofish spin\autofish_scan.png"
            $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            $txtStatus.Text = "Совпадение: $pct%`r`nСкрин: $path"
        } else {
            $thresh = [int]$numThresh.Value
            $bright = [ScreenCapture]::CountBrightPixels($dx, $dy, $dw, $dh, $thresh)
            $total = $dw * $dh; $pct = [Math]::Round($bright / $total * 100, 1)
            $bmp = New-Object System.Drawing.Bitmap($dw, $dh)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($dx, $dy, 0, 0, [System.Drawing.Size]::new($dw, $dh))
            $g.Dispose()
            $path = "E:\Project\autofish spin\autofish_scan.png"
            $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            $txtStatus.Text = "Ярких $bright/$total ($pct%). Скрин: $path"
        }
    } catch { $txtStatus.Text = "Ошибка: $_" }
    finally { $script:scanning = $false }
}

function Memorize {
    $dx = [int]$numDX.Value; $dy = [int]$numDY.Value
    $dw = [int]$numDW.Value; $dh = [int]$numDH.Value
    try {
        $script:refPixels = [ScreenCapture]::CaptureLuma($dx, $dy, $dw, $dh)
        $script:hasRef = $true
        $txtStatus.Text = "Эталон запомнен (${dw}x${dh})"
    } catch { $txtStatus.Text = "Ошибка: $_" }
}

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Скан(F6)"; $btnScan.Location = [System.Drawing.Point]::new(270, 160); $btnScan.Size = [System.Drawing.Size]::new(100, 25)
$btnScan.Add_Click({ Scan })
$form.Controls.Add($btnScan)

$btnRef = New-Object System.Windows.Forms.Button
$btnRef.Text = "Запомнить(F5)"
$btnRef.Location = [System.Drawing.Point]::new(270, 193); $btnRef.Size = [System.Drawing.Size]::new(100, 25)
$btnRef.Add_Click({ Memorize })
$form.Controls.Add($btnRef)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Старт"; $btnStart.Location = [System.Drawing.Point]::new(60, 240); $btnStart.Size = [System.Drawing.Size]::new(80, 30)
$btnStart.Add_Click({ if ($script:f) { StopFish } else { StartFish } })
$form.Controls.Add($btnStart)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Выход"; $btnExit.Location = [System.Drawing.Point]::new(170, 240); $btnExit.Size = [System.Drawing.Size]::new(80, 30)
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

$tm = New-Object System.Windows.Forms.Timer
$tm.Interval = 100
$tm.Add_Tick({
    $f3 = [WinAPI]::KeyDown(0x72); $f4 = [WinAPI]::KeyDown(0x73)
    $f5 = [WinAPI]::KeyDown(0x74); $f6 = [WinAPI]::KeyDown(0x75)
    if ($f3 -and -not $script:prevF3 -and -not $script:f) { StartFish }
    if ($f4 -and -not $script:prevF4 -and $script:f) { StopFish }
    if ($f5 -and -not $script:prevF5 -and -not $script:scanning) { Memorize }
    if ($f6 -and -not $script:prevF6 -and -not $script:scanning) { Scan }
    $script:prevF3 = $f3; $script:prevF4 = $f4; $script:prevF5 = $f5; $script:prevF6 = $f6
    if (-not $script:f) { return }

    if ($script:st -eq 1) {
        if ($script:tk -eq 0) { [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD) }
        $script:tk++
        if ($script:tk -ge 10) {
            [WinAPI]::SK(0x10, 2); [WinAPI]::SM([WinAPI]::LMU)
            $script:st = 2; $script:tk = 0; $txtStatus.Text = "Ожидание $($script:wait)с..."
        }
    } elseif ($script:st -eq 2) {
        $script:tk++
        if ($script:tk -ge ($script:wait * 10)) {
            $script:st = 3; $script:tk = 0; $script:detectTick = 0; $script:detectHit = 0
            [WinAPI]::SM([WinAPI]::LMD)
            $txtStatus.Text = "Мотка..."
        }
    } elseif ($script:st -eq 3) {
        $script:tk++; $script:detectTick++
        $mode = $cmbMode.SelectedItem
        if ($mode -eq "Эталон" -and $script:hasRef) {
            if ($script:detectTick -ge 5) {
                $script:detectTick = 0
                try {
                    $match = [ScreenCapture]::MatchLuma($script:refPixels, [int]$numDX.Value, [int]$numDY.Value, [int]$numDW.Value, [int]$numDH.Value, 30)
                    if ($match -gt 0.85) {
                        $script:detectHit++; if ($script:detectHit -ge 3) {
                            [WinAPI]::SM([WinAPI]::LMU)
                            $script:st = 1; $script:tk = 0
                            [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                            $txtStatus.Text = "Заброс..."
                        }
                    } else { $script:detectHit = 0 }
                } catch { }
            }
        } else {
            if ($script:detectTick -ge 5) {
                $script:detectTick = 0
                try {
                    $bright = [ScreenCapture]::CountBrightPixels([int]$numDX.Value, [int]$numDY.Value, [int]$numDW.Value, [int]$numDH.Value, [int]$numThresh.Value)
                    $total = [int]$numDW.Value * [int]$numDH.Value; $pct = $bright / $total
                    if ($pct -gt 0.05) {
                        $script:detectHit++; if ($script:detectHit -ge 3) {
                            [WinAPI]::SM([WinAPI]::LMU)
                            $script:st = 1; $script:tk = 0
                            [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                            $txtStatus.Text = "Заброс..."
                        }
                    } else { $script:detectHit = 0 }
                } catch {}
            }
        }
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
