/// PowerShell helper that the app starts in the background.
///
/// It watches two things Windows exposes for the CMF case dial:
///   * the master volume (each dial click = one 1/16 step)
///   * the media session play/pause state (each dial press = one flip)
///
/// It prints lines to stdout:   READY | ROT <steps> | FLIP <Playing|Paused>
/// and reads commands on stdin: PARK | RESTORE | PLAYPAUSE | QUIT
///
/// PARK saves the volume and holds it at 50% so a turn is never blocked at
/// 0% or 100%. RESTORE puts the saved volume back.
const bridgeScript = r'''
param([string]$CmdFile = "", [int]$ParentPid = 0)
$ErrorActionPreference = "Continue"

$src = @"
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject { }

[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out object devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
        [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr p);
    int UnregisterControlChangeNotify(IntPtr p);
    int GetChannelCount(out uint count);
    int SetMasterVolumeLevel(float level, ref Guid ctx);
    int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
    int GetMasterVolumeLevel(out float level);
    int GetMasterVolumeLevelScalar(out float level);
}

public static class DialNative {
    [DllImport("user32.dll")]
    static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

    static IAudioEndpointVolume vol;
    static int acquiredAt;

    static IAudioEndpointVolume Acquire() {
        int now = Environment.TickCount;
        if (vol != null && now - acquiredAt < 3000) return vol;
        try {
            IMMDeviceEnumerator en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
            IMMDevice dev;
            if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) { vol = null; return null; }
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object o;
            if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) { vol = null; return null; }
            vol = (IAudioEndpointVolume)o;
            acquiredAt = now;
            return vol;
        } catch (Exception) { vol = null; return null; }
    }

    public static float GetVol() {
        IAudioEndpointVolume v = Acquire();
        if (v == null) return -1f;
        try {
            float x;
            if (v.GetMasterVolumeLevelScalar(out x) == 0) return x;
        } catch (Exception) { vol = null; }
        return -1f;
    }

    public static void SetVol(float x) {
        IAudioEndpointVolume v = Acquire();
        if (v == null) return;
        Guid g = Guid.Empty;
        try { v.SetMasterVolumeLevelScalar(x, ref g); } catch (Exception) { vol = null; }
    }

    public static void PlayPause() {
        keybd_event(0xB3, 0, 0, UIntPtr.Zero);
        keybd_event(0xB3, 0, 2, UIntPtr.Zero);
    }
}

public static class DialIn {
    public static ConcurrentQueue<string> Q = new ConcurrentQueue<string>();
    public static volatile bool Closed = false;
    public static void Start() {
        Thread t = new Thread(delegate () {
            string l;
            while ((l = Console.In.ReadLine()) != null) Q.Enqueue(l);
            Closed = true;
        });
        t.IsBackground = true;
        t.Start();
    }
}
"@

Add-Type -TypeDefinition $src
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# Small volume bar shown near the bottom of the screen. It never takes focus
# and lets mouse clicks pass through.
$uiSrc = @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class VolumeBar : Form {
    float level;
    DateTime hideAt = DateTime.MinValue;

    public VolumeBar() {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;
        BackColor = Color.FromArgb(23, 24, 27);
        Opacity = 0.94;
        Size = new Size(300, 66);
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        Location = new Point(wa.Left + (wa.Width - Width) / 2, wa.Bottom - Height - 60);
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000020;
            return cp;
        }
    }

    public void ShowLevel(float v) {
        level = Math.Max(0f, Math.Min(1f, v));
        hideAt = DateTime.UtcNow.AddMilliseconds(1400);
        if (!Visible) Show();
        Invalidate();
    }

    public void Tick() {
        if (Visible && DateTime.UtcNow > hideAt) Hide();
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        using (Font f = new Font("Segoe UI", 11f, FontStyle.Regular))
        using (Brush text = new SolidBrush(Color.FromArgb(236, 237, 239)))
        using (Brush muted = new SolidBrush(Color.FromArgb(139, 143, 151)))
        using (Brush track = new SolidBrush(Color.FromArgb(43, 46, 51)))
        using (Brush fill = new SolidBrush(Color.FromArgb(108, 156, 255))) {
            g.DrawString("Volume", f, muted, 18, 10);
            string pct = ((int)Math.Round(level * 100)).ToString() + "%";
            SizeF sz = g.MeasureString(pct, f);
            g.DrawString(pct, f, text, Width - 18 - sz.Width, 10);
            Rectangle bar = new Rectangle(18, 40, Width - 36, 8);
            g.FillRectangle(track, bar);
            g.FillRectangle(fill, bar.X, bar.Y, (int)(bar.Width * level), bar.Height);
        }
    }
}
"@

$bar = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition $uiSrc -ReferencedAssemblies System.Windows.Forms,System.Drawing
    $bar = New-Object VolumeBar
} catch {
    [Console]::WriteLine("ERR volume bar: " + $_.Exception.Message)
}

$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($op, $type) {
    $t = $asTask.MakeGenericMethod($type).Invoke($null, @($op))
    [void]$t.Wait(-1)
    return $t.Result
}

$mgrType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
$mgr = Await ($mgrType::RequestAsync()) $mgrType
$propType = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties,Windows.Media.Control,ContentType=WindowsRuntime]
$lastTitle = ""
$lastTitleCheck = 0

[DialIn]::Start()

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$parked = $false
$saved = -1.0
$last = [DialNative]::GetVol()
$status = ""
$suppress = 0
$suppressUntil = 0
$quit = $false
$step = 0.0625
$lastSeq = [long]0
$nextParentCheck = 0
$beforeFlip = ""
$boolType = [bool]
$undoDue = 0
$undoTarget = ""
$undoTries = 0

[Console]::WriteLine("READY")

while (-not [DialIn]::Closed -and -not $quit) {
    # Safety: if the app that started this helper is gone, stop. The cleanup
    # after the loop puts the user's volume back.
    if ($ParentPid -gt 0 -and $sw.ElapsedMilliseconds -ge $nextParentCheck) {
        $nextParentCheck = $sw.ElapsedMilliseconds + 1000
        if (-not (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue)) { break }
    }

    # Commands from the app arrive on two channels (stdin lines and a command
    # file) as "<seq> <COMMAND>". A sequence number that was already seen is
    # ignored, so a command that arrives on both channels runs once.
    $raw = New-Object System.Collections.ArrayList
    $line = $null
    while ([DialIn]::Q.TryDequeue([ref]$line)) {
        [void]$raw.Add([string]$line)
        $line = $null
    }
    if ($CmdFile -ne "" -and (Test-Path -LiteralPath $CmdFile)) {
        try {
            # The app appends one line per command. Open with sharing so the
            # app can keep writing while we read.
            $fs = New-Object System.IO.FileStream($CmdFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $sr = New-Object System.IO.StreamReader($fs)
            $txt = $sr.ReadToEnd()
            $sr.Close()
            # Only whole lines: the app may be halfway through writing one.
            $cut = $txt.LastIndexOf("`n")
            if ($cut -ge 0) {
                foreach ($ln in ($txt.Substring(0, $cut) -split '\r?\n')) {
                    if ($ln.Trim() -ne "") { [void]$raw.Add($ln) }
                }
            }
        } catch { }
    }
    # Collect new commands, then run them in sequence order.
    $pending = New-Object 'System.Collections.Generic.SortedDictionary[long,string]'
    foreach ($item in $raw) {
        $parts = $item.Trim().Split(" ")
        if ($parts.Length -lt 2) { continue }
        $n0 = [long]0
        if (-not [long]::TryParse($parts[0], [ref]$n0)) { continue }
        if ($n0 -le $lastSeq) { continue }
        $pending[$n0] = $parts[1]
    }
    foreach ($kv in @($pending.GetEnumerator())) {
        $seq = [long]$kv.Key
        $cmd = [string]$kv.Value
        $lastSeq = $seq
        [Console]::WriteLine("CMD " + $seq + " " + $cmd)
        try {
            switch ($cmd) {
                "PARK" {
                    if (-not $parked) {
                        $saved = [DialNative]::GetVol()
                        if ($saved -ge 0) {
                            [DialNative]::SetVol(0.5)
                            $last = [DialNative]::GetVol()
                            $parked = $true
                            [Console]::WriteLine("PARKED saved=" + [math]::Round($saved, 3) + " now=" + [math]::Round($last, 3))
                        } else {
                            [Console]::WriteLine("PARK failed: no audio device")
                        }
                    }
                }
                "RESTORE" {
                    if ($parked) {
                        if ($saved -ge 0) { [DialNative]::SetVol([single]$saved) }
                        $last = [DialNative]::GetVol()
                        $parked = $false
                    }
                }
                "PLAYPAUSE" {
                    $suppress++
                    $suppressUntil = $sw.ElapsedMilliseconds + 2000
                    [DialNative]::PlayPause()
                }
                "UNDOFLIP" {
                    # Put the music back to the state it had before the last
                    # dial press, with an explicit play or pause request
                    # instead of another toggle.
                    # The check runs a moment later, in the main loop, so the
                    # music app has finished reacting to the press first.
                    if ($beforeFlip -ne "") {
                        $undoTarget = $beforeFlip
                        $undoTries = 0
                        $undoDue = $sw.ElapsedMilliseconds + 200
                    }
                }
                "QUIT" { $quit = $true }
            }
        } catch {
            [Console]::WriteLine("ERR " + $cmd + ": " + $_.Exception.Message)
        }
    }

    # Put the music back the way it was before a dial press (see UNDOFLIP).
    if ($undoDue -gt 0 -and $sw.ElapsedMilliseconds -ge $undoDue) {
        $undoDue = 0
        try {
            $s3 = $mgr.GetCurrentSession()
            if ($s3 -ne $null -and $undoTarget -ne "") {
                $cur3 = [string]$s3.GetPlaybackInfo().PlaybackStatus
                [Console]::WriteLine("UNDO check now=" + $cur3 + " want=" + $undoTarget + " try=" + $undoTries)
                if ($cur3 -ne $undoTarget -and ($cur3 -eq "Playing" -or $cur3 -eq "Paused")) {
                    $suppress++
                    $suppressUntil = $sw.ElapsedMilliseconds + 2000
                    if ($undoTries -eq 0) {
                        if ($undoTarget -eq "Playing") { [void](Await ($s3.TryPlayAsync()) $boolType) }
                        else { [void](Await ($s3.TryPauseAsync()) $boolType) }
                    } else {
                        [DialNative]::PlayPause()
                    }
                    $undoTries++
                    if ($undoTries -lt 3) { $undoDue = $sw.ElapsedMilliseconds + 400 }
                }
            }
        } catch {
            [Console]::WriteLine("ERR undo: " + $_.Exception.Message)
        }
    }

    # Dial turns show up as volume steps
    $v = [DialNative]::GetVol()
    if ($v -ge 0 -and $last -ge 0) {
        $d = $v - $last
        if ([math]::Abs($d) -gt 0.0005) {
            [Console]::WriteLine("VOL " + [math]::Round($v, 3) + " was " + [math]::Round($last, 3) + " parked=" + $parked)
            if ($parked) {
                $n = [int][math]::Round($d / $step)
                if ($n -eq 0) { if ($d -gt 0) { $n = 1 } else { $n = -1 } }
                [Console]::WriteLine("ROT " + $n + " at " + $sw.ElapsedMilliseconds + " ms")
                [DialNative]::SetVol(0.5)
                $last = [DialNative]::GetVol()
            } else {
                $last = $v
                if ($bar -ne $null) {
                    try { $bar.ShowLevel([single]$v) } catch { }
                }
            }
        }
    } elseif ($v -ge 0) {
        $last = $v
    }

    # Dial presses show up as play/pause flips
    if ($sw.ElapsedMilliseconds -ge $suppressUntil) { $suppress = 0 }
    $s = $mgr.GetCurrentSession()
    if ($s -ne $null) {
        $st = [string]$s.GetPlaybackInfo().PlaybackStatus
        if ($st -ne $status) {
            [Console]::WriteLine("STATE " + $st + " at " + $sw.ElapsedMilliseconds + " ms")
            if ($status -ne "" -and ($st -eq "Playing" -or $st -eq "Paused")) {
                if ($suppress -gt 0) { $suppress-- }
                else {
                    [Console]::WriteLine("FLIP " + $st + " at " + $sw.ElapsedMilliseconds + " ms")
                    $beforeFlip = $status
                }
            }
            $status = $st
        }
        if (($sw.ElapsedMilliseconds - $lastTitleCheck) -gt 300) {
            $lastTitleCheck = $sw.ElapsedMilliseconds
            try {
                $p = Await ($s.TryGetMediaPropertiesAsync()) $propType
                $title = [string]$p.Title
                if ($title -ne $lastTitle) {
                    [Console]::WriteLine("TRACK " + $title + " at " + $sw.ElapsedMilliseconds + " ms")
                    $lastTitle = $title
                }
            } catch { }
        }
    }

    if ($bar -ne $null) {
        try {
            $bar.Tick()
            [System.Windows.Forms.Application]::DoEvents()
        } catch { }
    }

    Start-Sleep -Milliseconds 30
}

if ($parked -and $saved -ge 0) { [DialNative]::SetVol([single]$saved) }
''';
