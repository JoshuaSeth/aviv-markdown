using Aviv.Windows.App.Services;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using System.Text.RegularExpressions;
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
        AppDomain.CurrentDomain.ProcessExit += (_, _) => DiagnosticLog.Write("ProcessExit raised.");
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
            window = new MainWindow(LaunchArgumentParser.FirstFilePath(args.Arguments));
            window.Closed += (_, _) => DiagnosticLog.Write("MainWindow closed.");
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
        public static void PlaceForVerificationIfRequested(Window window)
        {
            if (!string.Equals(Environment.GetEnvironmentVariable("AVIV_UI_VERIFY"), "1", StringComparison.Ordinal))
            {
                return;
            }

            var hwnd = WindowNative.GetWindowHandle(window);
            DiagnosticLog.Write($"Verification initial window state: {DescribeWindow(hwnd)}.");
            try
            {
                var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
                var appWindow = AppWindow.GetFromWindowId(windowId);
                appWindow.Title = "Aviv";
                appWindow.MoveAndResize(new RectInt32(96, 72, 1160, 760));
                DiagnosticLog.Write($"Verification AppWindow placement succeeded for hwnd={hwnd}: {DescribeWindow(hwnd)}.");
            }
            catch (Exception exception)
            {
                DiagnosticLog.WriteException("Verification AppWindow placement failed", exception);
            }

            DiagnosticLog.Write($"Verification placement completed for hwnd={hwnd}: {DescribeWindow(hwnd)}.");
        }

        private static string DescribeWindow(IntPtr hwnd)
        {
            var rectText = GetWindowRect(hwnd, out var rect)
                ? $"{rect.Left},{rect.Top},{rect.Right},{rect.Bottom} {rect.Right - rect.Left}x{rect.Bottom - rect.Top}"
                : "unavailable";
            return $"visible={IsWindowVisible(hwnd)} iconic={IsIconic(hwnd)} rect={rectText}";
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr hWnd, out NativeRect rect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr hWnd);

        [StructLayout(LayoutKind.Sequential)]
        private struct NativeRect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }
    }

    private static partial class LaunchArgumentParser
    {
        public static string? FirstFilePath(string arguments)
        {
            if (string.IsNullOrWhiteSpace(arguments))
            {
                return null;
            }

            foreach (Match match in TokenRegex().Matches(arguments))
            {
                var token = match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value;
                if (string.IsNullOrWhiteSpace(token) || token.StartsWith("--", StringComparison.Ordinal))
                {
                    continue;
                }

                return token;
            }

            return null;
        }

        [GeneratedRegex("\"([^\"]+)\"|(\\S+)")]
        private static partial Regex TokenRegex();
    }
}
