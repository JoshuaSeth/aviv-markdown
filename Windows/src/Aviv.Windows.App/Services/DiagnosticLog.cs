using System.Text;

namespace Aviv.Windows.App.Services;

public static class DiagnosticLog
{
    private static readonly object Sync = new();

    public static string? PathFromEnvironment =>
        Environment.GetEnvironmentVariable("AVIV_DIAGNOSTIC_LOG");

    public static void Write(string message)
    {
        var path = PathFromEnvironment;
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        lock (Sync)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.AppendAllText(path, $"[{DateTimeOffset.Now:O}] {message}{Environment.NewLine}", Encoding.UTF8);
        }
    }

    public static void WriteException(string context, Exception exception)
    {
        Write($"{context}: {exception.GetType().FullName}: {exception.Message}{Environment.NewLine}{exception}");
    }
}
