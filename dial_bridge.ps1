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

    [DllImport("user32.dll")]
    static extern bool SetProcessDPIAware();

    // Call once, before any window exists, so overlays are drawn in real
    // pixels instead of being stretched (blurry) on high-DPI screens.
    public static void DpiAware() {
        try { SetProcessDPIAware(); } catch (Exception) { }
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
[DialNative]::DpiAware()

# Small volume bar shown near the bottom of the screen. It never takes focus
# and lets mouse clicks pass through.
$uiSrc = @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class VolumeBar : Form {
    float level;
    float sc = 1f;
    DateTime hideAt = DateTime.MinValue;

    public VolumeBar() {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        DoubleBuffered = true;
        BackColor = Color.FromArgb(23, 24, 27);
        Opacity = 0.94;
        using (Graphics gg = Graphics.FromHwnd(IntPtr.Zero)) { sc = gg.DpiX / 96f; }
        Size = new Size((int)(300 * sc), (int)(66 * sc));
        Rectangle wa = Screen.PrimaryScreen.WorkingArea;
        Location = new Point(wa.Left + (wa.Width - Width) / 2, wa.Bottom - Height - (int)(60 * sc));
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
            g.DrawString("Volume", f, muted, 18 * sc, 10 * sc);
            string pct = ((int)Math.Round(level * 100)).ToString() + "%";
            SizeF sz = g.MeasureString(pct, f);
            g.DrawString(pct, f, text, Width - 18 * sc - sz.Width, 10 * sc);
            Rectangle bar = new Rectangle((int)(18 * sc), (int)(40 * sc), Width - (int)(36 * sc), (int)(8 * sc));
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
    Add-Type -TypeDefinition $uiSrc -ReferencedAssemblies System.Windows.Forms,System.Drawing -ErrorAction Stop
    $bar = New-Object VolumeBar
} catch {
    $bm = [string]$_.Exception.Message
    if ($bm.Length -gt 400) { $bm = $bm.Substring(0, 400) }
    [Console]::WriteLine("ERR volume bar: " + ($bm -replace '\s+', ' '))
}

# The floating wheel. A layered window drawn with per-pixel alpha (smooth
# round edges). It never takes focus and lets mouse clicks pass through, so
# keyboard shortcuts still reach the app you are working in.
$wheelSrc = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class WheelOverlay : Form {
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct BLENDFUNCTION {
        public byte BlendOp;
        public byte BlendFlags;
        public byte SourceConstantAlpha;
        public byte AlphaFormat;
    }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref Point pptDst, ref Size psize, IntPtr hdcSrc, ref Point pprSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll")]
    static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")]
    static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")]
    static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")]
    static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")]
    static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
    [DllImport("gdi32.dll")]
    static extern bool DeleteObject(IntPtr hObject);

    const int BaseSize = 320;
    string[] keys = new string[0];
    string[] labels = new string[0];
    int sel = 0;
    bool engaged = false;
    float sc = 1f;

    public WheelOverlay() {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) { sc = g.DpiX / 96f; }
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams {
        get {
            CreateParams cp = base.CreateParams;
            // layered, no-activate, tool window (not in Alt+Tab), click-through, topmost
            cp.ExStyle |= 0x00080000 | 0x08000000 | 0x00000080 | 0x00000020 | 0x00000008;
            return cp;
        }
    }

    // text: one item per line, "iconKey<TAB>label"
    public void SetItems(string text) {
        string[] lines = text.Split('\n');
        string[] k = new string[lines.Length];
        string[] l = new string[lines.Length];
        int n = 0;
        foreach (string line in lines) {
            if (line.Length == 0) continue;
            int tab = line.IndexOf('\t');
            if (tab < 0) { k[n] = "dot"; l[n] = line; }
            else { k[n] = line.Substring(0, tab); l[n] = line.Substring(tab + 1); }
            n++;
        }
        keys = new string[n];
        labels = new string[n];
        Array.Copy(k, keys, n);
        Array.Copy(l, labels, n);
    }

    public void Display(bool open, int selected, bool isEngaged) {
        if (!open) {
            if (Visible) Hide();
            return;
        }
        if (keys.Length == 0) return;
        sel = selected;
        engaged = isEngaged;
        int px = (int)Math.Round(BaseSize * sc);
        Rectangle wa = Screen.FromPoint(Cursor.Position).WorkingArea;
        Size = new Size(px, px);
        Location = new Point(wa.Left + (wa.Width - px) / 2, wa.Top + (wa.Height - px) / 2);
        if (!Visible) Show();
        Render(px);
    }

    void Render(int px) {
        Bitmap bmp = new Bitmap(px, px, PixelFormat.Format32bppArgb);
        try {
            using (Graphics g = Graphics.FromImage(bmp)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                g.Clear(Color.Transparent);

                float cx = px / 2f;
                float cy = px / 2f;
                float R = px / 2f - 3f * sc;
                using (Brush bg = new SolidBrush(Color.FromArgb(236, 23, 24, 27)))
                using (Pen edge = new Pen(Color.FromArgb(255, 43, 46, 51), 1.5f * sc)) {
                    g.FillEllipse(bg, cx - R, cy - R, 2 * R, 2 * R);
                    g.DrawEllipse(edge, cx - R, cy - R, 2 * R, 2 * R);
                }

                int n = keys.Length;
                float ring = R - 46f * sc;
                float nodeR = 22f * sc;
                Color accent = Color.FromArgb(255, 108, 156, 255);
                Color muted = Color.FromArgb(255, 139, 143, 151);
                Color dark = Color.FromArgb(255, 11, 18, 32);

                for (int i = 0; i < n; i++) {
                    double a = -Math.PI / 2 + 2 * Math.PI * i / n;
                    float x = cx + (float)(ring * Math.Cos(a));
                    float y = cy + (float)(ring * Math.Sin(a));
                    bool isSel = (i == sel);
                    if (isSel) {
                        using (Brush nb = new SolidBrush(accent)) {
                            g.FillEllipse(nb, x - nodeR, y - nodeR, 2 * nodeR, 2 * nodeR);
                        }
                        if (engaged) {
                            float o = nodeR + 3f * sc;
                            using (Pen rp = new Pen(Color.FromArgb(255, 236, 237, 239), 2f * sc)) {
                                g.DrawEllipse(rp, x - o, y - o, 2 * o, 2 * o);
                            }
                        }
                    }
                    DrawIcon(g, keys[i], x, y, 10f * sc, isSel ? dark : muted);
                }

                string title = (sel >= 0 && sel < n) ? labels[sel] : "";
                string sub = engaged ? "Turn to adjust" : (n.ToString() + " items");
                using (Font tf = new Font("Segoe UI Semibold", 13f))
                using (Font sf = new Font("Segoe UI", 9f))
                using (Brush tb = new SolidBrush(Color.FromArgb(255, 236, 237, 239)))
                using (Brush sb = new SolidBrush(muted))
                using (StringFormat fmt = new StringFormat()) {
                    fmt.Alignment = StringAlignment.Center;
                    fmt.LineAlignment = StringAlignment.Center;
                    fmt.Trimming = StringTrimming.EllipsisCharacter;
                    fmt.FormatFlags = StringFormatFlags.NoWrap;
                    RectangleF r1 = new RectangleF(cx - ring * 0.75f, cy - 22f * sc, ring * 1.5f, 24f * sc);
                    RectangleF r2 = new RectangleF(cx - ring * 0.75f, cy + 4f * sc, ring * 1.5f, 20f * sc);
                    g.DrawString(title, tf, tb, r1, fmt);
                    g.DrawString(sub, sf, sb, r2, fmt);
                }
            }
            SetBitmap(bmp);
        } finally {
            bmp.Dispose();
        }
    }

    void DrawIcon(Graphics g, string key, float cx, float cy, float s, Color c) {
        using (Pen p = new Pen(c, 1.8f * sc))
        using (Brush b = new SolidBrush(c)) {
            p.StartCap = LineCap.Round;
            p.EndCap = LineCap.Round;
            p.LineJoin = LineJoin.Round;
            if (key == "volume" || key == "mute") {
                PointF[] sp = new PointF[] {
                    new PointF(cx - s * 0.9f, cy - s * 0.35f),
                    new PointF(cx - s * 0.4f, cy - s * 0.35f),
                    new PointF(cx + s * 0.1f, cy - s * 0.8f),
                    new PointF(cx + s * 0.1f, cy + s * 0.8f),
                    new PointF(cx - s * 0.4f, cy + s * 0.35f),
                    new PointF(cx - s * 0.9f, cy + s * 0.35f)
                };
                g.DrawPolygon(p, sp);
                if (key == "volume") {
                    g.DrawArc(p, cx + s * 0.1f - s * 0.45f, cy - s * 0.45f, s * 0.9f, s * 0.9f, -50f, 100f);
                    g.DrawArc(p, cx + s * 0.1f - s * 0.9f, cy - s * 0.9f, s * 1.8f, s * 1.8f, -50f, 100f);
                } else {
                    g.DrawLine(p, cx + s * 0.45f, cy - s * 0.4f, cx + s * 1.05f, cy + s * 0.4f);
                    g.DrawLine(p, cx + s * 0.45f, cy + s * 0.4f, cx + s * 1.05f, cy - s * 0.4f);
                }
            } else if (key == "play") {
                PointF[] tri = new PointF[] {
                    new PointF(cx - s * 0.45f, cy - s * 0.75f),
                    new PointF(cx + s * 0.75f, cy),
                    new PointF(cx - s * 0.45f, cy + s * 0.75f)
                };
                g.DrawPolygon(p, tri);
            } else if (key == "next") {
                PointF[] tri = new PointF[] {
                    new PointF(cx - s * 0.7f, cy - s * 0.6f),
                    new PointF(cx + s * 0.3f, cy),
                    new PointF(cx - s * 0.7f, cy + s * 0.6f)
                };
                g.DrawPolygon(p, tri);
                g.DrawLine(p, cx + s * 0.65f, cy - s * 0.6f, cx + s * 0.65f, cy + s * 0.6f);
            } else if (key == "previous") {
                PointF[] tri = new PointF[] {
                    new PointF(cx + s * 0.7f, cy - s * 0.6f),
                    new PointF(cx - s * 0.3f, cy),
                    new PointF(cx + s * 0.7f, cy + s * 0.6f)
                };
                g.DrawPolygon(p, tri);
                g.DrawLine(p, cx - s * 0.65f, cy - s * 0.6f, cx - s * 0.65f, cy + s * 0.6f);
            } else if (key == "windows") {
                g.DrawRectangle(p, cx - s * 0.9f, cy - s * 0.7f, s * 1.8f, s * 1.4f);
                g.DrawLine(p, cx - s * 0.9f, cy - s * 0.25f, cx + s * 0.9f, cy - s * 0.25f);
            } else if (key == "desktops") {
                g.DrawRectangle(p, cx - s, cy - s * 0.8f, s * 2f, s * 1.3f);
                g.DrawLine(p, cx, cy + s * 0.5f, cx, cy + s * 0.85f);
                g.DrawLine(p, cx - s * 0.5f, cy + s * 0.85f, cx + s * 0.5f, cy + s * 0.85f);
            } else if (key == "tabs") {
                g.DrawRectangle(p, cx - s * 0.9f, cy - s * 0.45f, s * 1.8f, s * 1.35f);
                PointF[] tab = new PointF[] {
                    new PointF(cx - s * 0.9f, cy - s * 0.45f),
                    new PointF(cx - s * 0.9f, cy - s * 0.85f),
                    new PointF(cx - s * 0.1f, cy - s * 0.85f),
                    new PointF(cx - s * 0.1f, cy - s * 0.45f)
                };
                g.DrawLines(p, tab);
            } else if (key == "scroll") {
                g.DrawEllipse(p, cx - s * 0.6f, cy - s * 0.95f, s * 1.2f, s * 1.9f);
                g.DrawLine(p, cx, cy - s * 0.95f, cx, cy - s * 0.2f);
            } else if (key == "keyboard") {
                g.DrawRectangle(p, cx - s, cy - s * 0.6f, s * 2f, s * 1.2f);
                for (int i = 0; i < 4; i++) {
                    g.FillRectangle(b, cx - s * 0.7f + i * s * 0.45f, cy - s * 0.3f, s * 0.22f, s * 0.2f);
                }
                g.DrawLine(p, cx - s * 0.5f, cy + s * 0.3f, cx + s * 0.5f, cy + s * 0.3f);
            } else if (key == "zoom") {
                g.DrawEllipse(p, cx - s * 0.8f, cy - s * 0.8f, s * 1.3f, s * 1.3f);
                g.DrawLine(p, cx + s * 0.3f, cy + s * 0.3f, cx + s * 0.9f, cy + s * 0.9f);
                g.DrawLine(p, cx - s * 0.45f, cy - s * 0.15f, cx + s * 0.15f, cy - s * 0.15f);
                g.DrawLine(p, cx - s * 0.15f, cy - s * 0.45f, cx - s * 0.15f, cy + s * 0.15f);
            } else {
                g.FillEllipse(b, cx - s * 0.25f, cy - s * 0.25f, s * 0.5f, s * 0.5f);
            }
        }
    }

    void SetBitmap(Bitmap bmp) {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = IntPtr.Zero;
        IntPtr old = IntPtr.Zero;
        try {
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            old = SelectObject(memDc, hBmp);
            Size size = bmp.Size;
            Point src = new Point(0, 0);
            Point top = new Point(Left, Top);
            BLENDFUNCTION blend = new BLENDFUNCTION();
            blend.BlendOp = 0;
            blend.BlendFlags = 0;
            blend.SourceConstantAlpha = 255;
            blend.AlphaFormat = 1;
            UpdateLayeredWindow(Handle, screenDc, ref top, ref size, memDc, ref src, 0, ref blend, 2);
        } finally {
            ReleaseDC(IntPtr.Zero, screenDc);
            if (hBmp != IntPtr.Zero) {
                SelectObject(memDc, old);
                DeleteObject(hBmp);
            }
            DeleteDC(memDc);
        }
    }
}
"@

$wheelOv = $null
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -TypeDefinition $wheelSrc -ReferencedAssemblies System.Windows.Forms,System.Drawing -ErrorAction Stop
    $wheelOv = New-Object WheelOverlay
} catch {
    $wm = [string]$_.Exception.Message
    if ($wm.Length -gt 400) { $wm = $wm.Substring(0, 400) }
    [Console]::WriteLine("ERR wheel overlay: " + ($wm -replace '\s+', ' '))
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
$fileOffset = [long]0
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
            # Read only what was added since last time (the file is plain
            # ASCII, so characters and bytes are the same thing here).
            if ($fileOffset -le $fs.Length) { [void]$fs.Seek($fileOffset, [System.IO.SeekOrigin]::Begin) }
            $sr = New-Object System.IO.StreamReader($fs)
            $txt = $sr.ReadToEnd()
            $sr.Close()
            # Only whole lines: the app may be halfway through writing one.
            $cut = $txt.LastIndexOf("`n")
            if ($cut -ge 0) {
                $fileOffset += ($cut + 1)
                foreach ($ln in ($txt.Substring(0, $cut) -split '\r?\n')) {
                    if ($ln.Trim() -ne "") { [void]$raw.Add($ln) }
                }
            }
        } catch { }
    }
    # Collect new commands, then run them in sequence order.
    $pending = New-Object 'System.Collections.Generic.SortedDictionary[long,string]'
    foreach ($item in $raw) {
        $parts = $item.Trim().Split([char[]]@(' '), 2)
        if ($parts.Length -lt 2) { continue }
        $n0 = [long]0
        if (-not [long]::TryParse($parts[0], [ref]$n0)) { continue }
        if ($n0 -le $lastSeq) { continue }
        $pending[$n0] = $parts[1]
    }
    foreach ($kv in @($pending.GetEnumerator())) {
        $seq = [long]$kv.Key
        # "COMMAND" or "COMMAND argument"
        $cp = ([string]$kv.Value).Split([char[]]@(' '), 2)
        $cmd = $cp[0]
        $arg = ""
        if ($cp.Length -gt 1) { $arg = $cp[1] }
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
                "WITEMS" {
                    # Wheel items: base64 of UTF-8 lines "iconKey<TAB>label"
                    if ($wheelOv -ne $null -and $arg -ne "") {
                        $wtext = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($arg))
                        $wheelOv.SetItems($wtext)
                    }
                }
                "WSTATE" {
                    # Wheel state: "<open 0/1> <selected index> <engaged 0/1>"
                    if ($wheelOv -ne $null) {
                        $wa = $arg.Split([char[]]@(' '))
                        if ($wa.Length -ge 3) {
                            $wheelOv.Display(($wa[0] -eq "1"), [int]$wa[1], ($wa[2] -eq "1"))
                        }
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

    if ($bar -ne $null -or $wheelOv -ne $null) {
        try {
            if ($bar -ne $null) { $bar.Tick() }
            [System.Windows.Forms.Application]::DoEvents()
        } catch { }
    }

    Start-Sleep -Milliseconds 30
}

if ($parked -and $saved -ge 0) { [DialNative]::SetVol([single]$saved) }
