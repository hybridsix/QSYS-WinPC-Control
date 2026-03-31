# test-audio.ps1 - Multi-method diagnostic for SetVolume
# Run this in an interactive (non-elevated) PowerShell window.

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid iid, uint dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    int OpenPropertyStore(uint stgmAccess, out IntPtr ppProperties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out uint pdwState);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(uint dataFlow, uint dwStateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(uint dataFlow, uint role, out IMMDevice ppEndpoint);
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out uint pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
    int GetMute([MarshalAs(UnmanagedType.Bool)] out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(ref Guid pguidEventContext);
    int VolumeStepDown(ref Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

public static class TestAudio {
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const byte VK_VOLUME_UP   = 0xAF;
    private const byte VK_VOLUME_DOWN = 0xAE;

    private static IAudioEndpointVolume GetVol() {
        var t = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var e = (IMMDeviceEnumerator)Activator.CreateInstance(t);
        IMMDevice d; e.GetDefaultAudioEndpoint(0, 1, out d);
        Guid iid = typeof(IAudioEndpointVolume).GUID;
        object o; d.Activate(ref iid, 1, IntPtr.Zero, out o);
        return (IAudioEndpointVolume)o;
    }

    public static int GetVolume() {
        float s; GetVol().GetMasterVolumeLevelScalar(out s);
        return (int)Math.Round(s * 100);
    }

    // Method 1: SetMasterVolumeLevelScalar (already known broken)
    public static string TestScalar(int pct) {
        var v = GetVol(); Guid g = Guid.Empty;
        float before; v.GetMasterVolumeLevelScalar(out before);
        int hr = v.SetMasterVolumeLevelScalar(pct / 100f, ref g);
        System.Threading.Thread.Sleep(100);
        float after; v.GetMasterVolumeLevelScalar(out after);
        bool ok = Math.Abs(after - pct / 100f) < 0.02f;
        return string.Format("{0}  hr=0x{1:X8}  {2}%->{3}%", ok ? "OK" : "FAIL", hr,
            (int)Math.Round(before*100), (int)Math.Round(after*100));
    }

    // Method 2: SetMasterVolumeLevel (dB variant)
    public static string TestDB(int pct) {
        var v = GetVol(); Guid g = Guid.Empty;
        float minDB, maxDB, inc;
        v.GetVolumeRange(out minDB, out maxDB, out inc);
        float before; v.GetMasterVolumeLevelScalar(out before);
        // Map percent to dB linearly (crude but tests if the API responds)
        float targetDB = minDB + (maxDB - minDB) * (pct / 100f);
        int hr = v.SetMasterVolumeLevel(targetDB, ref g);
        System.Threading.Thread.Sleep(100);
        float after; v.GetMasterVolumeLevelScalar(out after);
        bool ok = Math.Abs(after - pct / 100f) < 0.05f;
        return string.Format("{0}  hr=0x{1:X8}  {2}%->{3}%  dBrange=[{4:F1},{5:F1}] targetDB={6:F1}",
            ok ? "OK" : "FAIL", hr, (int)Math.Round(before*100), (int)Math.Round(after*100),
            minDB, maxDB, targetDB);
    }

    // Method 3: Per-channel SetChannelVolumeLevelScalar
    public static string TestChannel(int pct) {
        var v = GetVol(); Guid g = Guid.Empty;
        uint chCount; v.GetChannelCount(out chCount);
        float before; v.GetMasterVolumeLevelScalar(out before);
        int hr = 0;
        for (uint ch = 0; ch < chCount; ch++) {
            hr = v.SetChannelVolumeLevelScalar(ch, pct / 100f, ref g);
        }
        System.Threading.Thread.Sleep(100);
        float after; v.GetMasterVolumeLevelScalar(out after);
        bool ok = Math.Abs(after - pct / 100f) < 0.02f;
        return string.Format("{0}  hr=0x{1:X8}  {2}%->{3}%  channels={4}",
            ok ? "OK" : "FAIL", hr, (int)Math.Round(before*100), (int)Math.Round(after*100), chCount);
    }

    // Method 4: VolumeStepUp / VolumeStepDown
    public static string TestSteps(int targetPct) {
        var v = GetVol(); Guid g = Guid.Empty;
        float before; v.GetMasterVolumeLevelScalar(out before);
        int beforePct = (int)Math.Round(before * 100);
        int delta = targetPct - beforePct;
        int steps = Math.Abs(delta);
        if (steps > 25) steps = 25; // cap to prevent long waits
        for (int i = 0; i < steps; i++) {
            if (delta > 0) v.VolumeStepUp(ref g);
            else v.VolumeStepDown(ref g);
            System.Threading.Thread.Sleep(10);
        }
        System.Threading.Thread.Sleep(100);
        float after; v.GetMasterVolumeLevelScalar(out after);
        bool ok = Math.Abs(after - before) > 0.01f; // did it move at all?
        return string.Format("{0}  {1}%->{2}%  (sent {3} steps)",
            ok ? "OK" : "FAIL", beforePct, (int)Math.Round(after*100), steps);
    }

    // Method 5: keybd_event with VK_VOLUME_DOWN/UP
    public static string TestKeybd(int targetPct) {
        float before; GetVol().GetMasterVolumeLevelScalar(out before);
        int beforePct = (int)Math.Round(before * 100);
        int delta = targetPct - beforePct;
        int presses = Math.Abs(delta / 2); // each key press = 2%
        if (presses > 15) presses = 15;
        byte vk = delta > 0 ? VK_VOLUME_UP : VK_VOLUME_DOWN;
        for (int i = 0; i < presses; i++) {
            keybd_event(vk, 0, 0, UIntPtr.Zero);          // key down
            keybd_event(vk, 0, 2, UIntPtr.Zero);          // key up
            System.Threading.Thread.Sleep(30);
        }
        System.Threading.Thread.Sleep(200);
        float after; GetVol().GetMasterVolumeLevelScalar(out after);
        bool ok = Math.Abs(after - before) > 0.01f;
        return string.Format("{0}  {1}%->{2}%  (sent {3} key presses)",
            ok ? "OK" : "FAIL", beforePct, (int)Math.Round(after*100), presses);
    }
}
"@

Write-Host ""
Write-Host "=== Audio SetVolume Multi-Method Diagnostic ===" -ForegroundColor Cyan
Write-Host ""

$orig = [TestAudio]::GetVolume()
Write-Host "Current volume: $orig%" -ForegroundColor White
Write-Host ""

$target = if ($orig -gt 50) { 20 } else { 80 }

Write-Host "Method 1: SetMasterVolumeLevelScalar -> $target%" -ForegroundColor Yellow
Write-Host "  $([TestAudio]::TestScalar($target))"
[TestAudio]::TestScalar($orig) | Out-Null  # restore

Write-Host ""
Write-Host "Method 2: SetMasterVolumeLevel (dB) -> $target%" -ForegroundColor Yellow
Write-Host "  $([TestAudio]::TestDB($target))"
[TestAudio]::TestScalar($orig) | Out-Null  # restore

Write-Host ""
Write-Host "Method 3: SetChannelVolumeLevelScalar -> $target%" -ForegroundColor Yellow
Write-Host "  $([TestAudio]::TestChannel($target))"
[TestAudio]::TestScalar($orig) | Out-Null  # restore

Write-Host ""
Write-Host "Method 4: VolumeStepUp/Down (25 steps toward $target%)" -ForegroundColor Yellow
Write-Host "  $([TestAudio]::TestSteps($target))"
# Restore with steps back
[TestAudio]::TestSteps($orig) | Out-Null

Write-Host ""
Write-Host "Method 5: keybd_event VK_VOLUME keys (toward $target%)" -ForegroundColor Yellow
Write-Host "  $([TestAudio]::TestKeybd($target))"
# Restore with keys back
[TestAudio]::TestKeybd($orig) | Out-Null

Write-Host ""
$final = [TestAudio]::GetVolume()
Write-Host "Final volume: $final%  (was $orig%)" -ForegroundColor White
Write-Host ""
Read-Host "Press Enter to close"
