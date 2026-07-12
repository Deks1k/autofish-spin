#Requires -Version 5.0
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    powershell -STA -File $MyInvocation.MyCommand.Path
    return
}

# ===== НАСТРОЙКИ =====
$waitAfterCast = 3    # секунд ждать после заброса
$reelDuration = 15    # секунд длится мотка
# =====================

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

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
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int i, uint m, uint v);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int i);

    public const uint LMD = 0x0002, LMU = 0x0004, RMD = 0x0008, RMU = 0x0010;
    public const uint KU = 0x0002;
    public const int IM = 0, IK = 1;

    public static void SM(uint f) { INPUT[] i = new INPUT[1]; i[0].type = IM; i[0].ui.mi.dwFlags = f; SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static void SK(ushort vk, uint f) { INPUT[] i = new INPUT[1]; i[0].type = IK; i[0].ui.ki.wVk = vk; i[0].ui.ki.dwFlags = f; SendInput(1, i, Marshal.SizeOf(typeof(INPUT))); }
    public static void Rel() { SK(0x10, KU); SM(LMU); SM(RMU); }
}

public class HKForm : Form {
    public delegate void HkDel(int id);
    public event HkDel HK;
    public HKForm() { WindowState = FormWindowState.Minimized; ShowInTaskbar = false; Load += (s, e) => Hide(); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312 && HK != null) HK(m.WParam.ToInt32());
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing"

$hkForm = New-Object HKForm
$null = $hkForm.Handle
[WinAPI]::RegisterHotKey($hkForm.Handle, 1, 0, 0x72)
[WinAPI]::RegisterHotKey($hkForm.Handle, 2, 0, 0x73)

$script:f = $false
$script:st = 0
$script:tk = 0
$script:tm = $null

function StopFish {
    $script:f = $false; $script:st = 0; $script:tk = 0
    if ($script:tm) { $script:tm.Stop() }
    [WinAPI]::Rel()
    Write-Host "[FISH] STOP"
}

$hkForm.Add_HK({
    param($id)
    if ($id -eq 1) {
        if ($script:f) { StopFish; return }
        $script:f = $true; $script:st = 1; $script:tk = 0
        Write-Host "[FISH] START"

        $script:tm = New-Object System.Windows.Forms.Timer
        $script:tm.Interval = 100
        $script:tm.Add_Tick({
            if (-not $script:f) { $script:tm.Stop(); return }

            if ($script:st -eq 1) {
                if ($script:tk -eq 0) {
                    [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                    Write-Host "[FISH] Cast..."
                }
                $script:tk++
                if ($script:tk -ge 10) {
                    [WinAPI]::SK(0x10, 2); [WinAPI]::SM([WinAPI]::LMU)
                    $script:st = 2; $script:tk = 0
                    Write-Host "[FISH] Wait ${waitAfterCast}s..."
                }
            }
            elseif ($script:st -eq 2) {
                $script:tk++
                if ($script:tk -ge ($waitAfterCast * 10)) {
                    $script:st = 3; $script:tk = 0
                    [WinAPI]::SM([WinAPI]::LMD)
                    Write-Host "[FISH] Reel ${reelDuration}s..."
                }
            }
            elseif ($script:st -eq 3) {
                $script:tk++
                if ($script:tk -ge ($reelDuration * 10)) {
                    [WinAPI]::SM([WinAPI]::LMU)
                    $script:st = 1; $script:tk = 0
                    [WinAPI]::SK(0x10, 0); [WinAPI]::SM([WinAPI]::LMD)
                    Write-Host "[FISH] Cast..."
                }
            }
        })
        $script:tm.Start()
    }
    elseif ($id -eq 2) { StopFish }
})

Write-Host "=== AutoFish Spin ==="
Write-Host "F3 - Start"
Write-Host "F4 - Stop"
Write-Host "Cycle: cast(1s) -> wait(${waitAfterCast}s) -> reel(${reelDuration}s) -> repeat"
Write-Host "Edit `$waitAfterCast and `$reelDuration at top of script"
Write-Host "Close this window to exit."
[System.Windows.Forms.Application]::Run($hkForm)
