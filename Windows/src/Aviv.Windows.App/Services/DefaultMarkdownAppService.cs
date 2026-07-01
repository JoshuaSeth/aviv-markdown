using Microsoft.Win32;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;

namespace Aviv.Windows.App.Services;

public static class DefaultMarkdownAppService
{
    private const string ProgId = "AvivMarkdown.md";
    private const string AppName = "Aviv";
    private const string NeverAskValueName = "NeverAskDefaultMarkdownApp";
    private const string PreferencesKey = @"Software\AvivMarkdown\Preferences";
    private static readonly string[] Extensions = [".md", ".markdown", ".mdown", ".mdwn", ".mkd", ".mkdn", ".mdtxt", ".mdtext", ".mmd", ".rmd", ".rmarkdown", ".qmd"];

    public static bool ShouldPrompt()
    {
        return !ShouldSkipPrompt() && !NeverAskAgain && !IsDefaultForMarkdown();
    }

    public static bool NeverAskAgain
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(PreferencesKey);
            return Convert.ToInt32(key?.GetValue(NeverAskValueName, 0) ?? 0) == 1;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(PreferencesKey);
            key?.SetValue(NeverAskValueName, value ? 1 : 0, RegistryValueKind.DWord);
        }
    }

    public static bool IsDefaultForMarkdown()
    {
        return Extensions.Take(2).All(IsDefaultForExtension);
    }

    public static void RegisterCurrentApp()
    {
        var executablePath = CurrentExecutablePath();
        var command = $"\"{executablePath}\" \"%1\"";
        var icon = $"\"{executablePath}\",0";

        using (var progIdKey = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ProgId}"))
        {
            progIdKey?.SetValue(null, "Aviv Markdown Document");
            progIdKey?.SetValue("FriendlyTypeName", "Aviv Markdown Document");
        }

        using (var iconKey = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ProgId}\DefaultIcon"))
        {
            iconKey?.SetValue(null, icon);
        }

        using (var commandKey = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{ProgId}\shell\open\command"))
        {
            commandKey?.SetValue(null, command);
        }

        foreach (var extension in Extensions)
        {
            using var extensionKey = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{extension}");
            if (extensionKey?.GetValue(null) is null)
            {
                extensionKey?.SetValue(null, ProgId);
            }

            using var openWithProgIds = Registry.CurrentUser.CreateSubKey($@"Software\Classes\{extension}\OpenWithProgids");
            openWithProgIds?.SetValue(ProgId, Array.Empty<byte>(), RegistryValueKind.Binary);
        }

        using (var capabilities = Registry.CurrentUser.CreateSubKey(@"Software\Classes\Applications\Aviv.Windows.App.exe\Capabilities"))
        {
            capabilities?.SetValue("ApplicationName", AppName);
            capabilities?.SetValue("ApplicationDescription", "A hyper-clean native WYSIWYG Markdown editor.");

            using var fileAssociations = capabilities?.CreateSubKey("FileAssociations");
            foreach (var extension in Extensions)
            {
                fileAssociations?.SetValue(extension, ProgId);
            }
        }

        using (var registeredApplications = Registry.CurrentUser.CreateSubKey(@"Software\RegisteredApplications"))
        {
            registeredApplications?.SetValue(AppName, @"Software\Classes\Applications\Aviv.Windows.App.exe\Capabilities");
        }

        SHChangeNotify(0x08000000, 0, IntPtr.Zero, IntPtr.Zero);
    }

    public static void OpenDefaultAppsSettings()
    {
        RegisterCurrentApp();
        Process.Start(new ProcessStartInfo
        {
            FileName = "ms-settings:defaultapps",
            UseShellExecute = true
        });
    }

    private static bool IsDefaultForExtension(string extension)
    {
        using var userChoice = Registry.CurrentUser.OpenSubKey($@"Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\{extension}\UserChoice");
        var userChoiceProgId = userChoice?.GetValue("ProgId") as string;
        if (!string.IsNullOrWhiteSpace(userChoiceProgId))
        {
            return string.Equals(userChoiceProgId, ProgId, StringComparison.OrdinalIgnoreCase);
        }

        using var extensionKey = Registry.CurrentUser.OpenSubKey($@"Software\Classes\{extension}");
        var classProgId = extensionKey?.GetValue(null) as string;
        return string.Equals(classProgId, ProgId, StringComparison.OrdinalIgnoreCase);
    }

    private static bool ShouldSkipPrompt()
    {
        return string.Equals(Environment.GetEnvironmentVariable("AVIV_SKIP_DEFAULT_APP_PROMPT"), "1", StringComparison.Ordinal) ||
            string.Equals(Environment.GetEnvironmentVariable("AVIV_UI_VERIFY"), "1", StringComparison.Ordinal);
    }

    private static string CurrentExecutablePath()
    {
        return Environment.ProcessPath ??
            Assembly.GetEntryAssembly()?.Location ??
            Assembly.GetExecutingAssembly().Location;
    }

    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}
