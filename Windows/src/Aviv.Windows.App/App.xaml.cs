using Aviv.Windows.App.Services;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using Windows.Graphics;
using WinRT.Interop;

namespace Aviv.Windows.App;

public partial class App : Application
{
    private Window? window;

    public App()
    {
        DiagnosticLog.Write("App constructor starting.");
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            if (args.ExceptionObject is Exception exception)
            {
                DiagnosticLog.WriteException("AppDomain unhandled exception", exception);
            }
            else
            {
                DiagnosticLog.Write($"AppDomain unhandled exception object: {args.ExceptionObject}");
            }
        };
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            DiagnosticLog.WriteException("TaskScheduler unobserved exception", args.Exception);
        };
        UnhandledException += (_, args) =>
        {
            DiagnosticLog.WriteException("WinUI unhandled exception", args.Exception);
        };
        InitializeComponent();
        DiagnosticLog.Write("App InitializeComponent completed.");
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            DiagnosticLog.Write("OnLaunched starting.");
            window = new MainWindow();
            DiagnosticLog.Write("MainWindow created.");
            window.Activate();
            DiagnosticLog.Write("MainWindow activated.");
            NativeWindowPlacement.PlaceForVerificationIfRequested(window);
        }
        catch (Exception exception)
        {
            DiagnosticLog.WriteException("OnLaunched failed", exception);
            throw;
        }
    }

    private static class NativeWindowPlacement
    {
        private static readonly IntPtr HwndTopmost = new(-1);

        public static void PlaceForVerificationIfRequested(Window window)
        {
            if (!string.Equals(Environment.GetEnvironmentVariable("AVIV_UI_VERIFY"), "1", StringComparison.Ordinal))
            {
                return;
            }

            var hwnd = WindowNative.GetWindowHandle(window);
            try
            {
                var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
                var appWindow = AppWindow.GetFromWindowId(windowId);
                appWindow.Title = "Aviv";
                appWindow.MoveAndResize(new RectInt32(96, 72, 1160, 760));
                appWindow.Show();
                DiagnosticLog.Write($"Verification AppWindow placement succeeded for hwnd={hwnd}.");
            }
            catch (Exception exception)
            {
                DiagnosticLog.WriteException("Verification AppWindow placement failed", exception);
            }

            var showResult = ShowWindow(hwnd, 9);
            var positionResult = SetWindowPos(hwnd, HwndTopmost, 96, 72, 1160, 760, 0x0040);
            var foregroundResult = SetForegroundWindow(hwnd);
            DiagnosticLog.Write($"Verification placement hwnd={hwnd} ShowWindow={showResult} SetWindowPos={positionResult} SetForegroundWindow={foregroundResult}.");
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint flags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetForegroundWindow(IntPtr hWnd);
    }
}
