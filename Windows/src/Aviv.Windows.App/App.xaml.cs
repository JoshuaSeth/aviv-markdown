using Aviv.Windows.App.Services;
using Microsoft.UI.Xaml;

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
        }
        catch (Exception exception)
        {
            DiagnosticLog.WriteException("OnLaunched failed", exception);
            throw;
        }
    }
}
