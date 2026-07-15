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
    public const uint RMD = 0x0008, RMU = 0x0010;
    public const uint KU = 0x0002;
    public const int IM = 0, IK = 1;
    public static void SM(uint f) { INPUT[] i = new INPUT[1]; i[0].type = IM; i[0].ui.mi.dwFlags = f; SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static void SK(ushort vk, uint f) { INPUT[] i = new INPUT[1]; i[0].type = IK; i[0].ui.ki.wVk = vk; i[0].ui.ki.dwFlags = f; SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static void Rel() { SK(0x10, KU); SM(LMU); SM(RMU); }
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
$script:detectTick = 0; $script:detectHit = 0; $script:scanning = $false; $script:rmbPressed = $false; $script:fishHit = 0; $script:winHit = 0; $script:fishBaseline = 0.0; $script:textBaseline = 0.0; $script:winBaseline = 0.0
$script:refPixels = $null; $script:hasRef = $false

# Mode-specific settings
$script:bx = 900; $script:by = 1386; $script:bw = 40; $script:bh = 11; $script:bt = 80
$script:fx = 850; $script:fy = 1360; $script:fw = 40; $script:fh = 40; $script:ft = 150
$script:wx = 1110; $script:wy = 1260; $script:ww = 80; $script:wh = 25; $script:wt = 80

$form = New-Object System.Windows.Forms.Form
$form.Text = "AutoFish Spin"
$form.Size = [System.Drawing.Size]::new(520, 530)
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
$txtStatus.Location = [System.Drawing.Point]::new(15, 85); $txtStatus.Size = [System.Drawing.Size]::new(480, 40)
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
$numDY.Minimum = 0; $numDY.Maximum = 2160; $numDY.Value = 1386
$form.Controls.Add($numDY)

$numDW = New-Object System.Windows.Forms.NumericUpDown
$numDW.Location = [System.Drawing.Point]::new(155, 160); $numDW.Size = [System.Drawing.Size]::new(60, 25)
$numDW.Minimum = 5; $numDW.Maximum = 500; $numDW.Value = 40
$form.Controls.Add($numDW)

$numDH = New-Object System.Windows.Forms.NumericUpDown
$numDH.Location = [System.Drawing.Point]::new(225, 160); $numDH.Size = [System.Drawing.Size]::new(60, 25)
$numDH.Minimum = 1; $numDH.Maximum = 100; $numDH.Value = 11
$form.Controls.Add($numDH)

$lblFish = New-Object System.Windows.Forms.Label
$lblFish.Text = "Значок рыбы (X,Y,W,H):"
$lblFish.Location = [System.Drawing.Point]::new(15, 195); $lblFish.Size = [System.Drawing.Size]::new(180, 20)
$form.Controls.Add($lblFish)

$numFX = New-Object System.Windows.Forms.NumericUpDown
$numFX.Location = [System.Drawing.Point]::new(15, 220); $numFX.Size = [System.Drawing.Size]::new(60, 25)
$numFX.Minimum = 0; $numFX.Maximum = 3840; $numFX.Value = 850
$form.Controls.Add($numFX)

$numFY = New-Object System.Windows.Forms.NumericUpDown
$numFY.Location = [System.Drawing.Point]::new(85, 220); $numFY.Size = [System.Drawing.Size]::new(60, 25)
$numFY.Minimum = 0; $numFY.Maximum = 2160; $numFY.Value = 1360
$form.Controls.Add($numFY)

$numFW = New-Object System.Windows.Forms.NumericUpDown
$numFW.Location = [System.Drawing.Point]::new(155, 220); $numFW.Size = [System.Drawing.Size]::new(60, 25)
$numFW.Minimum = 5; $numFW.Maximum = 200; $numFW.Value = 40
$form.Controls.Add($numFW)

$numFH = New-Object System.Windows.Forms.NumericUpDown
$numFH.Location = [System.Drawing.Point]::new(225, 220); $numFH.Size = [System.Drawing.Size]::new(60, 25)
$numFH.Minimum = 5; $numFH.Maximum = 200; $numFH.Value = 40
$form.Controls.Add($numFH)

$lblFishThresh = New-Object System.Windows.Forms.Label
$lblFishThresh.Text = "Порог:"
$lblFishThresh.Location = [System.Drawing.Point]::new(295, 222); $lblFishThresh.Size = [System.Drawing.Size]::new(40, 20)
$form.Controls.Add($lblFishThresh)

$numFThresh = New-Object System.Windows.Forms.NumericUpDown
$numFThresh.Location = [System.Drawing.Point]::new(330, 220); $numFThresh.Size = [System.Drawing.Size]::new(50, 25)
$numFThresh.Minimum = 10; $numFThresh.Maximum = 255; $numFThresh.Value = 150
$form.Controls.Add($numFThresh)

$lblWin = New-Object System.Windows.Forms.Label
$lblWin.Text = "Окно рыбы (X,Y,W,H):"
$lblWin.Location = [System.Drawing.Point]::new(15, 255); $lblWin.Size = [System.Drawing.Size]::new(180, 20)
$form.Controls.Add($lblWin)

$numWX = New-Object System.Windows.Forms.NumericUpDown
$numWX.Location = [System.Drawing.Point]::new(15, 280); $numWX.Size = [System.Drawing.Size]::new(60, 25)
$numWX.Minimum = 0; $numWX.Maximum = 3840; $numWX.Value = 1110
$form.Controls.Add($numWX)

$numWY = New-Object System.Windows.Forms.NumericUpDown
$numWY.Location = [System.Drawing.Point]::new(85, 280); $numWY.Size = [System.Drawing.Size]::new(60, 25)
$numWY.Minimum = 0; $numWY.Maximum = 2160; $numWY.Value = 1260
$form.Controls.Add($numWY)

$numWW = New-Object System.Windows.Forms.NumericUpDown
$numWW.Location = [System.Drawing.Point]::new(155, 280); $numWW.Size = [System.Drawing.Size]::new(60, 25)
$numWW.Minimum = 5; $numWW.Maximum = 500; $numWW.Value = 80
$form.Controls.Add($numWW)

$numWH = New-Object System.Windows.Forms.NumericUpDown
$numWH.Location = [System.Drawing.Point]::new(225, 280); $numWH.Size = [System.Drawing.Size]::new(60, 25)
$numWH.Minimum = 5; $numWH.Maximum = 200; $numWH.Value = 25
$form.Controls.Add($numWH)

$lblWinThresh = New-Object System.Windows.Forms.Label
$lblWinThresh.Text = "Порог:"
$lblWinThresh.Location = [System.Drawing.Point]::new(295, 282); $lblWinThresh.Size = [System.Drawing.Size]::new(40, 20)
$form.Controls.Add($lblWinThresh)

$numWThresh = New-Object System.Windows.Forms.NumericUpDown
$numWThresh.Location = [System.Drawing.Point]::new(330, 280); $numWThresh.Size = [System.Drawing.Size]::new(50, 25)
$numWThresh.Minimum = 10; $numWThresh.Maximum = 255; $numWThresh.Value = 80
$form.Controls.Add($numWThresh)

$lblMode = New-Object System.Windows.Forms.Label
$lblMode.Text = "Режим:"; $lblMode.Location = [System.Drawing.Point]::new(15, 315); $lblMode.Size = [System.Drawing.Size]::new(50, 20)
$form.Controls.Add($lblMode)

$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = [System.Drawing.Point]::new(65, 313); $cmbMode.Size = [System.Drawing.Size]::new(100, 25)
$cmbMode.DropDownStyle = "DropDownList"
$cmbMode.Items.Add("Яркость")|Out-Null; $cmbMode.Items.Add("Эталон")|Out-Null; $cmbMode.Items.Add("Ручной")|Out-Null
$cmbMode.SelectedIndex = 0

$lblThresh = New-Object System.Windows.Forms.Label
$lblThresh.Text = "Порог яркости:"
$lblThresh.Location = [System.Drawing.Point]::new(180, 315); $lblThresh.Size = [System.Drawing.Size]::new(100, 20)
$form.Controls.Add($lblThresh)

$numThresh = New-Object System.Windows.Forms.NumericUpDown
$numThresh.Location = [System.Drawing.Point]::new(280, 313); $numThresh.Size = [System.Drawing.Size]::new(60, 25)
$numThresh.Minimum = 10; $numThresh.Maximum = 255; $numThresh.Value = 80
$form.Controls.Add($numThresh)

# Save/load settings on mode switch
$cmbMode.Add_SelectedIndexChanged({
    $mode = $cmbMode.SelectedItem
    $script:bx = [int]$numDX.Value; $script:by = [int]$numDY.Value
    $script:bw = [int]$numDW.Value; $script:bh = [int]$numDH.Value
    $script:bt = [int]$numThresh.Value
    $script:fx = [int]$numFX.Value; $script:fy = [int]$numFY.Value
    $script:fw = [int]$numFW.Value; $script:fh = [int]$numFH.Value; $script:ft = [int]$numFThresh.Value
    $script:wx = [int]$numWX.Value; $script:wy = [int]$numWY.Value
    $script:ww = [int]$numWW.Value; $script:wh = [int]$numWH.Value; $script:wt = [int]$numWThresh.Value
    $numDX.Value = $script:bx; $numDY.Value = $script:by
    $numDW.Value = $script:bw; $numDH.Value = $script:bh
    $numThresh.Value = $script:bt
    $numFX.Value = $script:fx; $numFY.Value = $script:fy
    $numFW.Value = $script:fw; $numFH.Value = $script:fh; $numFThresh.Value = $script:ft
    $numWX.Value = $script:wx; $numWY.Value = $script:wy
    $numWW.Value = $script:ww; $numWH.Value = $script:wh; $numWThresh.Value = $script:wt
    $script:prevMode = $mode
})
$form.Controls.Add($cmbMode)
$script:prevMode = "Яркость"

function StartFish {
    $script:wait = [int]$numWait.Value; $script:reel = [int]$numReel.Value
    $script:f = $true; $script:st = 1; $script:tk = 0; $script:detectTick = 0; $script:detectHit = 0; $script:rmbPressed = $false; $script:fishHit = 0; $script:winHit = 0; $script:fishBaseline = 0.0; $script:textBaseline = 0.0; $script:winBaseline = 0.0
    $btnStart.Text = "Стоп"
    $txtStatus.Text = "Заброс..."; $txtStatus.ForeColor = "Green"
}

function StopFish {
    $script:f = $false; $script:st = 0; $script:tk = 0; $script:rmbPressed = $false; $script:fishHit = 0; $script:winHit = 0; $script:fishBaseline = 0.0; $script:textBaseline = 0.0; $script:winBaseline = 0.0
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
        } elseif ($mode -eq "Ручной") {
            $txtStatus.Text = "Ручной режим — скан не используется"
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
            $fdx = [int]$numFX.Value; $fdy = [int]$numFY.Value; $fdw = [int]$numFW.Value; $fdh = [int]$numFH.Value
            $fthresh = [int]$numFThresh.Value
            $fbright = [ScreenCapture]::CountBrightPixels($fdx, $fdy, $fdw, $fdh, $fthresh)
            $ftotal = $fdw * $fdh; $fpct = [Math]::Round($fbright / $ftotal * 100, 1)
            $fbmp = New-Object System.Drawing.Bitmap($fdw, $fdh)
            $fg = [System.Drawing.Graphics]::FromImage($fbmp)
            $fg.CopyFromScreen($fdx, $fdy, 0, 0, [System.Drawing.Size]::new($fdw, $fdh))
            $fg.Dispose()
            $fpath = "E:\Project\autofish spin\autofish_fish_scan.png"
            $fbmp.Save($fpath, [System.Drawing.Imaging.ImageFormat]::Png); $fbmp.Dispose()
            $wdx = [int]$numWX.Value; $wdy = [int]$numWY.Value; $wdw = [int]$numWW.Value; $wdh = [int]$numWH.Value
            $wthresh = [int]$numWThresh.Value
            $wbright = [ScreenCapture]::CountBrightPixels($wdx, $wdy, $wdw, $wdh, $wthresh)
            $wtotal = $wdw * $wdh; $wpct = [Math]::Round($wbright / $wtotal * 100, 1)
            $wbmp = New-Object System.Drawing.Bitmap($wdw, $wdh)
            $wg = [System.Drawing.Graphics]::FromImage($wbmp)
            $wg.CopyFromScreen($wdx, $wdy, 0, 0, [System.Drawing.Size]::new($wdw, $wdh))
            $wg.Dispose()
            $wpath = "E:\Project\autofish spin\autofish_win_scan.png"
            $wbmp.Save($wpath, [System.Drawing.Imaging.ImageFormat]::Png); $wbmp.Dispose()
            $txtStatus.Text = "Текст: $bright/$total ($pct%). Рыба: $fbright/$ftotal ($fpct%). Окно: $wbright/$wtotal ($wpct%). Файлы сохранены"
        }
    } catch { $txtStatus.Text = "Oшибка: $_" }
    finally { $script:scanning = $false }
}

function Memorize {
    $dx = [int]$numDX.Value; $dy = [int]$numDY.Value
    $dw = [int]$numDW.Value; $dh = [int]$numDH.Value
    $fdx = [int]$numFX.Value; $fdy = [int]$numFY.Value
    $fdw = [int]$numFW.Value; $fdh = [int]$numFH.Value
    $wdx = [int]$numWX.Value; $wdy = [int]$numWY.Value
    $wdw = [int]$numWW.Value; $wdh = [int]$numWH.Value
    try {
        $script:refPixels = [ScreenCapture]::CaptureLuma($dx, $dy, $dw, $dh)
        $script:hasRef = $true
        $bmp = New-Object System.Drawing.Bitmap($dw, $dh)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($dx, $dy, 0, 0, [System.Drawing.Size]::new($dw, $dh))
        $g.Dispose()
        $bmp.Save("E:\Project\autofish spin\autofish_scan.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $fbmp = New-Object System.Drawing.Bitmap($fdw, $fdh)
        $fg = [System.Drawing.Graphics]::FromImage($fbmp)
        $fg.CopyFromScreen($fdx, $fdy, 0, 0, [System.Drawing.Size]::new($fdw, $fdh))
        $fg.Dispose()
        $fbmp.Save("E:\Project\autofish spin\autofish_fish_scan.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $fbmp.Dispose()
        $wbmp = New-Object System.Drawing.Bitmap($wdw, $wdh)
        $wg = [System.Drawing.Graphics]::FromImage($wbmp)
        $wg.CopyFromScreen($wdx, $wdy, 0, 0, [System.Drawing.Size]::new($wdw, $wdh))
        $wg.Dispose()
        $wbmp.Save("E:\Project\autofish spin\autofish_win_scan.png", [System.Drawing.Imaging.ImageFormat]::Png)
        $wbmp.Dispose()
        $txtStatus.Text = "Эталон и скрины сохранены (${dw}x${dh}, ${fdw}x${fdh}, ${wdw}x${wdh})"
    } catch { $txtStatus.Text = "Ошибка: $_" }
}

$btnRef = New-Object System.Windows.Forms.Button
$btnRef.Text = "Запомнить(F5)"; $btnRef.Location = [System.Drawing.Point]::new(15, 350); $btnRef.Size = [System.Drawing.Size]::new(120, 25)
$btnRef.Add_Click({ Memorize })
$form.Controls.Add($btnRef)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Скан(F6)"; $btnScan.Location = [System.Drawing.Point]::new(145, 350); $btnScan.Size = [System.Drawing.Size]::new(120, 25)
$btnScan.Add_Click({ Scan })
$form.Controls.Add($btnScan)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Старт"; $btnStart.Location = [System.Drawing.Point]::new(60, 385); $btnStart.Size = [System.Drawing.Size]::new(80, 30)
$btnStart.Add_Click({ if ($script:f) { StopFish } else { StartFish } })
$form.Controls.Add($btnStart)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Выход"; $btnExit.Location = [System.Drawing.Point]::new(170, 385); $btnExit.Size = [System.Drawing.Size]::new(80, 30)
$btnExit.Add_Click({ $form.Close() })
$form.Controls.Add($btnExit)

$lblHelp = New-Object System.Windows.Forms.Label
$lblHelp.Text = "X:-влево/+вправо Y:-вверх/+вниз W:-уже/+шире H:-ниже/+выше | F5=запом F6=скан F3=пуск F4=стоп"
$lblHelp.Location = [System.Drawing.Point]::new(15, 425); $lblHelp.Size = [System.Drawing.Size]::new(480, 20)
$lblHelp.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblHelp)

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
        if ($script:tk -eq 0) {
            try { $baseBright = [ScreenCapture]::CountBrightPixels([int]$numFX.Value, [int]$numFY.Value, [int]$numFW.Value, [int]$numFH.Value, [int]$numFThresh.Value); $script:fishBaseline = $baseBright / ([int]$numFW.Value * [int]$numFH.Value) } catch { $script:fishBaseline = 0.0 }
            try { $baseText = [ScreenCapture]::CountBrightPixels([int]$numDX.Value, [int]$numDY.Value, [int]$numDW.Value, [int]$numDH.Value, [int]$numThresh.Value); $script:textBaseline = $baseText / ([int]$numDW.Value * [int]$numDH.Value) } catch { $script:textBaseline = 0.0 }
            try { $baseWin = [ScreenCapture]::CountBrightPixels([int]$numWX.Value, [int]$numWY.Value, [int]$numWW.Value, [int]$numWH.Value, [int]$numWThresh.Value); $script:winBaseline = $baseWin / ([int]$numWW.Value * [int]$numWH.Value) } catch { $script:winBaseline = 0.0 }
            [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
        }
        $script:tk++
        if ($script:tk -ge 10) {
            [WinAPI]::SK(0x10, 2); [WinAPI]::SM([WinAPI]::LMU)
            $script:st = 2; $script:tk = 0; $txtStatus.Text = "Ожидание $($script:wait)с..."
        }
    } elseif ($script:st -eq 2) {
        $script:tk++
        if ($script:tk -ge ($script:wait * 10)) {
            $script:st = 3; $script:tk = 0; $script:detectTick = 0; $script:detectHit = 0; $script:rmbPressed = $false; $script:fishHit = 0; $script:winHit = 0
            [WinAPI]::SM([WinAPI]::LMD)
            $txtStatus.Text = "Мотка..."
        }
    } elseif ($script:st -eq 3) {
        $script:tk++
        $mode = $cmbMode.SelectedItem
        if ($mode -eq "Ручной") {
            if ($script:tk -ge ($script:reel * 10)) {
                [WinAPI]::SM([WinAPI]::LMU)
                $script:st = 1; $script:tk = 0
                [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                $txtStatus.Text = "Заброс..."
            }
        } else {
            $script:detectTick++; $releaseAll = $false
            if ($script:detectTick -ge 5) {
                $script:detectTick = 0
                try {
                    # Text detection
                    if ($mode -eq "Эталон" -and $script:hasRef) {
                        $match = [ScreenCapture]::MatchLuma($script:refPixels, [int]$numDX.Value, [int]$numDY.Value, [int]$numDW.Value, [int]$numDH.Value, 30)
                        if ($match -gt 0.85) {
                            $script:detectHit++; if ($script:detectHit -ge 3) { $releaseAll = $true }
                        } else { $script:detectHit = 0 }
                    } else {
                        $bright = [ScreenCapture]::CountBrightPixels([int]$numDX.Value, [int]$numDY.Value, [int]$numDW.Value, [int]$numDH.Value, [int]$numThresh.Value)
                        $total = [int]$numDW.Value * [int]$numDH.Value; $pct = $bright / $total
                        if ($pct -gt ($script:textBaseline * 1.5)) {
                            $script:detectHit++; if ($script:detectHit -ge 3) { $releaseAll = $true }
                        } else { $script:detectHit = 0 }
                    }

                    # Fish detection — only until подсечка
                    if (-not $script:rmbPressed) {
                        $fbright = [ScreenCapture]::CountBrightPixels([int]$numFX.Value, [int]$numFY.Value, [int]$numFW.Value, [int]$numFH.Value, [int]$numFThresh.Value)
                        $ftotal = [int]$numFW.Value * [int]$numFH.Value; $fpct = $fbright / $ftotal
                        if ($fpct -gt ($script:fishBaseline + 0.15) -and $fpct -gt ($script:fishBaseline * 2.0) -and $fpct -lt 0.80) {
                            $script:fishHit++; if ($script:fishHit -ge 6) {
                                [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::RMD); $script:rmbPressed = $true
                                $txtStatus.Text = "Поклёвка! Мотка+Шифт+ПКМ..."
                            }
                        } else { $script:fishHit = 0 }
                    }

                    # Window detection — only after bite
                    if ($script:rmbPressed) {
                        $wbright = [ScreenCapture]::CountBrightPixels([int]$numWX.Value, [int]$numWY.Value, [int]$numWW.Value, [int]$numWH.Value, [int]$numWThresh.Value)
                        $wtotal = [int]$numWW.Value * [int]$numWH.Value; $wpct = $wbright / $wtotal
                        if ($wpct -gt ($script:winBaseline + 0.10) -and $wpct -gt ($script:winBaseline * 1.5)) {
                            $script:winHit++; if ($script:winHit -ge 8) {
                                [WinAPI]::SM([WinAPI]::LMU)
                                [WinAPI]::SM([WinAPI]::RMU); $script:rmbPressed = $false
                                [WinAPI]::SK(0x10, 2); [WinAPI]::SK(0x20, 0); Start-Sleep -Milliseconds 50; [WinAPI]::SK(0x20, 2)
                                $script:st = 4; $script:tk = 0; $script:detectTick = 0; $script:detectHit = 0
                                $txtStatus.Text = "Рыба поймана! Ожидание оснастки..."
                            }
                        } else { $script:winHit = 0 }
                    }
                } catch {}
            }
            if ($script:tk -ge 600) { $releaseAll = $true }
            if ($releaseAll -and $script:st -eq 3) {
                [WinAPI]::SM([WinAPI]::LMU)
                if ($script:rmbPressed) { [WinAPI]::SM([WinAPI]::RMU); $script:rmbPressed = $false }
                $script:st = 1; $script:tk = 0
                [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                $txtStatus.Text = "Заброс..."
            }
        }
    } elseif ($script:st -eq 4) {
        $script:tk++; $script:detectTick++
        if ($script:tk -ge 300) { $script:st = 1; $script:tk = 0; [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD); $txtStatus.Text = "Заброс..." }
        if ($script:detectTick -ge 5) {
            $script:detectTick = 0
            try {
                $bright = [ScreenCapture]::CountBrightPixels([int]$numDX.Value, [int]$numDY.Value, [int]$numDW.Value, [int]$numDH.Value, [int]$numThresh.Value)
                $total = [int]$numDW.Value * [int]$numDH.Value; $pct = $bright / $total
                if ($pct -gt ($script:textBaseline * 1.5)) {
                    $script:detectHit++; if ($script:detectHit -ge 3) {
                        $script:st = 1; $script:tk = 0
                        [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                        $txtStatus.Text = "Заброс..."
                    }
                } else { $script:detectHit = 0 }
            } catch { $script:detectHit = 0 }
        }
    }
})
$tm.Start()

[System.Windows.Forms.Application]::Run($form)
