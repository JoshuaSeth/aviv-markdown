using Microsoft.UI.Xaml;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Aviv.Windows.App.Services;

public sealed record OpenedMarkdownDocument(string Path, string Markdown);
public sealed record SavedMarkdownDocument(string Path);

public interface IMarkdownFileService
{
    Task<OpenedMarkdownDocument?> OpenMarkdownAsync();
    Task<string> ReadMarkdownAsync(string path);
    Task SaveMarkdownAsync(string path, string markdown);
    Task<SavedMarkdownDocument?> SaveMarkdownAsAsync(string markdown, string? suggestedPath);
}

public sealed class MarkdownFileService(Window owner) : IMarkdownFileService
{
    public async Task<OpenedMarkdownDocument?> OpenMarkdownAsync()
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeFilter.Add(".md");
        picker.FileTypeFilter.Add(".markdown");
        picker.FileTypeFilter.Add(".txt");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(owner));

        var file = await picker.PickSingleFileAsync();
        if (file is null)
        {
            return null;
        }

        return new OpenedMarkdownDocument(file.Path, await FileIO.ReadTextAsync(file));
    }

    public async Task<string> ReadMarkdownAsync(string path)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        return await FileIO.ReadTextAsync(file);
    }

    public async Task SaveMarkdownAsync(string path, string markdown)
    {
        var file = await StorageFile.GetFileFromPathAsync(path);
        await FileIO.WriteTextAsync(file, markdown);
    }

    public async Task<SavedMarkdownDocument?> SaveMarkdownAsAsync(string markdown, string? suggestedPath)
    {
        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
            SuggestedFileName = suggestedPath is null ? "Untitled.md" : Path.GetFileName(suggestedPath)
        };
        picker.FileTypeChoices.Add("Markdown", [".md"]);
        picker.FileTypeChoices.Add("Text", [".txt"]);
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(owner));

        var file = await picker.PickSaveFileAsync();
        if (file is null)
        {
            return null;
        }

        await FileIO.WriteTextAsync(file, markdown);
        return new SavedMarkdownDocument(file.Path);
    }
}
