// Blue View OS for Windows 11: tile all windows, and swap tiles by dragging.
//
// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0. See LICENSE.
//
//   Win + Shift + T   tile every window on the screen under the pointer in an
//                     even grid; press again to put them back where they were
//   Drag a tile       onto another tile (a faint glass outline marks it) to swap
//
// Runs in the tray. install.ps1 compiles it with the C# compiler that ships with
// Windows (.NET Framework 4.x), so it's written in C# 5.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace BlueViewOS
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            bool created;
            using (var mutex = new Mutex(true, "BlueViewOS.Tiling", out created))
            {
                if (!created)
                    return;

                // Physical pixels everywhere, so window and monitor rectangles agree.
                try { Native.SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch (EntryPointNotFoundException) { }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TilingApp());
                GC.KeepAlive(mutex);
            }
        }
    }

    internal sealed class TilingApp : ApplicationContext
    {
        private const int HotkeyId = 0xB705;

        private readonly NotifyIcon tray;
        private readonly HotkeyWindow hotkeys;
        private readonly Tiler tiler = new Tiler();
        private readonly Native.WinEventProc moveSizeProc;
        private readonly IntPtr moveSizeHook;

        public TilingApp()
        {
            var menu = new ContextMenuStrip();
            menu.Items.Add("Tile all windows\tWin+Shift+T", null, delegate { tiler.Toggle(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quit Blue View tiling", null, delegate { ExitThread(); });

            tray = new NotifyIcon();
            tray.Icon = LogoIcon.Create();
            tray.Text = "Blue View OS tiling (Win+Shift+T)";
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += delegate { tiler.Toggle(); };
            tray.Visible = true;

            hotkeys = new HotkeyWindow();
            hotkeys.Pressed += delegate { tiler.Toggle(); };
            if (!Native.RegisterHotKey(hotkeys.Handle, HotkeyId, Native.MOD_WIN | Native.MOD_SHIFT | Native.MOD_NOREPEAT, (uint)Keys.T))
            {
                tray.ShowBalloonTip(8000, "Blue View OS tiling", "Win+Shift+T is taken by another app. Double-click this icon to tile windows.", ToolTipIcon.Warning);
            }

            // Keep the delegate alive for as long as the hook is installed.
            moveSizeProc = OnMoveSize;
            moveSizeHook = Native.SetWinEventHook(Native.EVENT_SYSTEM_MOVESIZESTART, Native.EVENT_SYSTEM_MOVESIZEEND, IntPtr.Zero, moveSizeProc, 0, 0, Native.WINEVENT_OUTOFCONTEXT);
        }

        private void OnMoveSize(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time)
        {
            if (idObject != 0)
                return;
            if (eventType == Native.EVENT_SYSTEM_MOVESIZESTART)
                tiler.DragStarted(hwnd);
            else
                tiler.DragEnded(hwnd);
        }

        protected override void ExitThreadCore()
        {
            Native.UnregisterHotKey(hotkeys.Handle, HotkeyId);
            if (moveSizeHook != IntPtr.Zero)
                Native.UnhookWinEvent(moveSizeHook);
            tiler.Dispose();
            tray.Visible = false;
            tray.Dispose();
            hotkeys.DestroyHandle();
            base.ExitThreadCore();
        }
    }

    internal sealed class HotkeyWindow : NativeWindow
    {
        public event EventHandler Pressed;

        public HotkeyWindow()
        {
            CreateHandle(new CreateParams());
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.WM_HOTKEY && Pressed != null)
                Pressed(this, EventArgs.Empty);
            base.WndProc(ref m);
        }
    }

    internal sealed class Tile
    {
        public IntPtr Window;
        public Native.WINDOWPLACEMENT Before; // where it was before tiling
        public Rectangle Cell;                // its tile, as the visible frame
    }

    internal sealed class Tiler : IDisposable
    {
        private readonly List<Tile> tiles = new List<Tile>();
        private readonly TileOutline outline = new TileOutline();
        private readonly System.Windows.Forms.Timer dragTimer = new System.Windows.Forms.Timer();
        private Tile dragging;
        private Tile dropTarget;

        public Tiler()
        {
            dragTimer.Interval = 40;
            dragTimer.Tick += delegate { TrackDrag(); };
        }

        // ---- Tile all / put back -------------------------------------------------

        public void Toggle()
        {
            IntPtr monitor = Native.MonitorFromPoint(Cursor.Position, Native.MONITOR_DEFAULTTONEAREST);
            List<IntPtr> windows = WindowsOn(monitor);
            Forget(delegate (Tile t) { return !Native.IsWindow(t.Window); });

            if (tiles.Count > 0 && AllInPlace(windows))
            {
                PutBack();
                return;
            }
            TileAll(windows, monitor);
        }

        // True when every window on the screen is one of ours, still in its tile.
        private bool AllInPlace(List<IntPtr> windows)
        {
            foreach (IntPtr w in windows)
            {
                Tile t = Find(w);
                if (t == null || !Near(Frame(w), t.Cell))
                    return false;
            }
            return true;
        }

        private void TileAll(List<IntPtr> windows, IntPtr monitor)
        {
            if (windows.Count == 0)
                return;

            Rectangle area = WorkArea(monitor);
            int gap = Scale(8, monitor);
            area.Inflate(-gap, -gap);

            // Keep the order people see: top to bottom, then left to right.
            windows.Sort(delegate (IntPtr a, IntPtr b)
            {
                Rectangle ra = Frame(a), rb = Frame(b);
                int rowA = ra.Top / Math.Max(1, area.Height / 4), rowB = rb.Top / Math.Max(1, area.Height / 4);
                return rowA != rowB ? rowA.CompareTo(rowB) : ra.Left.CompareTo(rb.Left);
            });

            int count = windows.Count;
            int columns = (int)Math.Ceiling(Math.Sqrt(count));
            int rows = (int)Math.Ceiling(count / (double)columns);

            var next = new List<Tile>();
            int index = 0;
            for (int row = 0; row < rows; row++)
            {
                int inRow = row == rows - 1 ? count - columns * (rows - 1) : columns;
                for (int column = 0; column < inRow; column++, index++)
                {
                    int x0 = area.Left + (area.Width + gap) * column / inRow;
                    int x1 = area.Left + (area.Width + gap) * (column + 1) / inRow - gap;
                    int y0 = area.Top + (area.Height + gap) * row / rows;
                    int y1 = area.Top + (area.Height + gap) * (row + 1) / rows - gap;

                    IntPtr w = windows[index];
                    Tile existing = Find(w);
                    var tile = new Tile();
                    tile.Window = w;
                    tile.Before = existing != null ? existing.Before : Placement(w);
                    tile.Cell = Rectangle.FromLTRB(x0, y0, x1, y1);
                    next.Add(tile);
                }
            }

            tiles.Clear();
            tiles.AddRange(next);
            foreach (Tile t in tiles)
                MoveTo(t.Window, t.Cell);
        }

        private void PutBack()
        {
            foreach (Tile t in tiles)
            {
                if (!Native.IsWindow(t.Window))
                    continue;
                Native.WINDOWPLACEMENT placement = t.Before;
                placement.length = Marshal.SizeOf(typeof(Native.WINDOWPLACEMENT));
                if (placement.showCmd == Native.SW_SHOWMINIMIZED)
                    placement.showCmd = Native.SW_SHOWNORMAL;
                Native.SetWindowPlacement(t.Window, ref placement);
            }
            tiles.Clear();
        }

        // ---- Swap by drag --------------------------------------------------------

        public void DragStarted(IntPtr window)
        {
            dragging = Find(window);
            dropTarget = null;
            if (dragging != null)
                dragTimer.Start();
        }

        private void TrackDrag()
        {
            if (dragging == null)
                return;
            Point pointer = Cursor.Position;
            Tile over = null;
            foreach (Tile t in tiles)
            {
                if (t != dragging && t.Cell.Contains(pointer) && Native.IsWindow(t.Window))
                {
                    over = t;
                    break;
                }
            }
            if (over == dropTarget)
                return;
            dropTarget = over;
            if (over != null)
                outline.ShowAt(over.Cell);
            else
                outline.HideOutline();
        }

        public void DragEnded(IntPtr window)
        {
            dragTimer.Stop();
            outline.HideOutline();
            Tile dragged = dragging, target = dropTarget;
            dragging = null;
            dropTarget = null;

            if (dragged == null || dragged.Window != window)
                return;

            if (target != null && Native.IsWindow(target.Window))
            {
                Rectangle cell = dragged.Cell;
                dragged.Cell = target.Cell;
                target.Cell = cell;
                MoveTo(dragged.Window, dragged.Cell);
                MoveTo(target.Window, target.Cell);
            }
            // Dropped anywhere else: it's simply no longer in its tile, and the
            // next Win+Shift+T tiles it again.
        }

        // ---- Windows -------------------------------------------------------------

        private static List<IntPtr> WindowsOn(IntPtr monitor)
        {
            var result = new List<IntPtr>();
            Native.EnumWindows(delegate (IntPtr w, IntPtr unused)
            {
                if (IsTileable(w) && Native.MonitorFromWindow(w, Native.MONITOR_DEFAULTTONEAREST) == monitor)
                    result.Add(w);
                return true;
            }, IntPtr.Zero);
            return result;
        }

        private static readonly HashSet<string> SkippedClasses = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow", "BlueViewOS.TileOutline"
        };

        // Ordinary app windows: visible, on this desktop, not minimized, resizable, with a title.
        private static bool IsTileable(IntPtr w)
        {
            if (!Native.IsWindowVisible(w) || Native.IsIconic(w) || Native.GetWindowTextLength(w) == 0)
                return false;

            long style = Native.GetWindowLongPtr(w, Native.GWL_STYLE).ToInt64();
            long exStyle = Native.GetWindowLongPtr(w, Native.GWL_EXSTYLE).ToInt64();
            if ((exStyle & Native.WS_EX_TOOLWINDOW) != 0 || (style & Native.WS_THICKFRAME) == 0)
                return false;
            if (Native.GetWindow(w, Native.GW_OWNER) != IntPtr.Zero && (exStyle & Native.WS_EX_APPWINDOW) == 0)
                return false;

            int cloaked;
            if (Native.DwmGetWindowAttribute(w, Native.DWMWA_CLOAKED, out cloaked, sizeof(int)) == 0 && cloaked != 0)
                return false;

            var className = new StringBuilder(256);
            Native.GetClassName(w, className, className.Capacity);
            return !SkippedClasses.Contains(className.ToString());
        }

        // The visible frame, without the invisible resize borders Windows adds around windows.
        private static Rectangle Frame(IntPtr w)
        {
            Native.RECT r;
            if (Native.DwmGetWindowAttribute(w, Native.DWMWA_EXTENDED_FRAME_BOUNDS, out r, Marshal.SizeOf(typeof(Native.RECT))) != 0)
                Native.GetWindowRect(w, out r);
            return Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom);
        }

        private static void MoveTo(IntPtr w, Rectangle frame)
        {
            if (Native.IsZoomed(w) || Native.IsIconic(w))
                Native.ShowWindow(w, Native.SW_RESTORE);

            // Account for the invisible borders so the visible frame lands on the tile.
            Native.RECT outer;
            Native.GetWindowRect(w, out outer);
            Rectangle visible = Frame(w);
            int left = visible.Left - outer.Left, top = visible.Top - outer.Top;
            int right = outer.Right - visible.Right, bottom = outer.Bottom - visible.Bottom;

            Native.SetWindowPos(w, IntPtr.Zero, frame.Left - left, frame.Top - top, frame.Width + left + right, frame.Height + top + bottom,
                Native.SWP_NOZORDER | Native.SWP_NOACTIVATE | Native.SWP_NOOWNERZORDER);
        }

        private static Native.WINDOWPLACEMENT Placement(IntPtr w)
        {
            var placement = new Native.WINDOWPLACEMENT();
            placement.length = Marshal.SizeOf(typeof(Native.WINDOWPLACEMENT));
            Native.GetWindowPlacement(w, ref placement);
            return placement;
        }

        private static Rectangle WorkArea(IntPtr monitor)
        {
            var info = new Native.MONITORINFO();
            info.cbSize = Marshal.SizeOf(typeof(Native.MONITORINFO));
            Native.GetMonitorInfo(monitor, ref info);
            return Rectangle.FromLTRB(info.rcWork.Left, info.rcWork.Top, info.rcWork.Right, info.rcWork.Bottom);
        }

        private static int Scale(int pixels, IntPtr monitor)
        {
            uint dpiX, dpiY;
            try
            {
                if (Native.GetDpiForMonitor(monitor, 0, out dpiX, out dpiY) == 0)
                    return pixels * (int)dpiX / 96;
            }
            catch (DllNotFoundException) { }
            return pixels;
        }

        private static bool Near(Rectangle a, Rectangle b)
        {
            const int slack = 12;
            return Math.Abs(a.Left - b.Left) <= slack && Math.Abs(a.Top - b.Top) <= slack &&
                   Math.Abs(a.Right - b.Right) <= slack && Math.Abs(a.Bottom - b.Bottom) <= slack;
        }

        private Tile Find(IntPtr w)
        {
            foreach (Tile t in tiles)
                if (t.Window == w)
                    return t;
            return null;
        }

        private void Forget(Predicate<Tile> match)
        {
            tiles.RemoveAll(match);
        }

        public void Dispose()
        {
            dragTimer.Dispose();
            outline.Dispose();
        }
    }

    // A faint Blue View glass outline over the tile a dragged window will swap with.
    internal sealed class TileOutline : Form
    {
        public TileOutline()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            BackColor = Color.FromArgb(56, 182, 255);
            Opacity = 0.22;
            Text = "Blue View OS tile";
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOPMOST;
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            int round = Native.DWMWCP_ROUND;
            Native.DwmSetWindowAttribute(Handle, Native.DWMWA_WINDOW_CORNER_PREFERENCE, ref round, sizeof(int));
        }

        // Shown and hidden directly, without activating it or going through WinForms' visibility.
        public void ShowAt(Rectangle cell)
        {
            Native.SetWindowPos(Handle, Native.HWND_TOPMOST, cell.Left, cell.Top, cell.Width, cell.Height, Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
        }

        public void HideOutline()
        {
            if (IsHandleCreated)
                Native.ShowWindow(Handle, Native.SW_HIDE);
        }
    }

    // The tray icon: the Blue View logo's yellow and blue ovals.
    internal static class LogoIcon
    {
        public static Icon Create()
        {
            using (var bitmap = new Bitmap(32, 32))
            using (Graphics g = Graphics.FromImage(bitmap))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                using (var yellow = new SolidBrush(Color.FromArgb(255, 222, 89)))
                using (var blue = new SolidBrush(Color.FromArgb(56, 182, 255)))
                {
                    g.FillEllipse(yellow, 13, 5, 17, 11);
                    g.FillEllipse(blue, 2, 16, 17, 11);
                }
                return Icon.FromHandle(bitmap.GetHicon());
            }
        }
    }

    internal static class Native
    {
        public const int WM_HOTKEY = 0x0312;
        public const uint MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;
        public const uint EVENT_SYSTEM_MOVESIZESTART = 0x000A, EVENT_SYSTEM_MOVESIZEEND = 0x000B, WINEVENT_OUTOFCONTEXT = 0;
        public const int GWL_STYLE = -16, GWL_EXSTYLE = -20;
        public const long WS_THICKFRAME = 0x00040000;
        public const int WS_EX_TOOLWINDOW = 0x80, WS_EX_APPWINDOW = 0x40000, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TRANSPARENT = 0x20, WS_EX_TOPMOST = 0x8;
        public const uint GW_OWNER = 4;
        public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9, DWMWA_CLOAKED = 14, DWMWA_WINDOW_CORNER_PREFERENCE = 33, DWMWCP_ROUND = 2;
        public const int SW_HIDE = 0, SW_SHOWNORMAL = 1, SW_SHOWMINIMIZED = 2, SW_RESTORE = 9;
        public const uint SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40, SWP_NOOWNERZORDER = 0x200;
        public const uint MONITOR_DEFAULTTONEAREST = 2;
        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);

        public delegate void WinEventProc(IntPtr hook, uint eventType, IntPtr hwnd, int idObject, int idChild, uint thread, uint time);
        public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; }

        [StructLayout(LayoutKind.Sequential)]
        public struct WINDOWPLACEMENT
        {
            public int length, flags, showCmd;
            public POINT ptMinPosition, ptMaxPosition;
            public RECT rcNormalPosition;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MONITORINFO
        {
            public int cbSize;
            public RECT rcMonitor, rcWork;
            public uint dwFlags;
        }

        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll")] public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax, IntPtr hmod, WinEventProc proc, uint process, uint thread, uint flags);
        [DllImport("user32.dll")] public static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder name, int max);
        [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int index);
        [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
        [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT placement);
        [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(Point pt, uint flags);
        [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
        [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
        [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out RECT value, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hWnd, int attribute, ref int value, int size);
    }
}
