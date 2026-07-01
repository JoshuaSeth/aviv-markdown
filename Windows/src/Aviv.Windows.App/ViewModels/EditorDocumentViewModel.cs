using Aviv.Windows.App.Services;
using Aviv.Windows.Core;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Aviv.Windows.App.ViewModels;

public sealed partial class EditorDocumentViewModel : ObservableObject
{
    private const double DefaultViewScale = 1.0;
    private const double ZoomStep = 1.12;
    private readonly IMarkdownFileService fileService;
    private string lastSavedMarkdown = MarkdownSamples.Starter;

    public event Action<EditorEditAction>? EditRequested;
    public event Action<EditorCommandKind>? EditorCommandRequested;
    public event Action<double>? ViewScaleChanged;

    private string markdown = MarkdownSamples.Starter;
    private string documentTitle = "Untitled";
    private string? documentPath;
    private bool isEdited;
    private string statusText = DocumentMetrics.For(MarkdownSamples.Starter).DisplayText;
    private double viewScale = DefaultViewScale;

    public string Markdown
    {
        get => markdown;
        set
        {
            if (SetProperty(ref markdown, value))
            {
                StatusText = DocumentMetrics.For(value).DisplayText;
            }
        }
    }

    public string DocumentTitle
    {
        get => documentTitle;
        set => SetProperty(ref documentTitle, value);
    }

    public string? DocumentPath
    {
        get => documentPath;
        set
        {
            if (SetProperty(ref documentPath, value))
            {
                UpdateDocumentTitle();
            }
        }
    }

    public bool IsEdited
    {
        get => isEdited;
        set
        {
            if (SetProperty(ref isEdited, value))
            {
                UpdateDocumentTitle();
            }
        }
    }

    public string StatusText
    {
        get => statusText;
        set => SetProperty(ref statusText, value);
    }

    public double ViewScale
    {
        get => viewScale;
        set => SetProperty(ref viewScale, value);
    }

    public EditorDocumentViewModel(IMarkdownFileService fileService)
    {
        this.fileService = fileService;
    }

    public void UpdateFromEditor(string nextMarkdown)
    {
        if (Markdown == nextMarkdown)
        {
            return;
        }

        Markdown = nextMarkdown;
        IsEdited = Markdown != lastSavedMarkdown;
        UpdateDocumentTitle();
    }

    public async Task OpenPathAsync(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        DocumentPath = path;
        Markdown = await fileService.ReadMarkdownAsync(path);
        lastSavedMarkdown = Markdown;
        IsEdited = false;
    }

    [RelayCommand]
    private void NewDocument()
    {
        DocumentPath = null;
        Markdown = MarkdownSamples.Starter;
        lastSavedMarkdown = Markdown;
        IsEdited = false;
    }

    [RelayCommand]
    private void NewTab()
    {
        NewDocument();
    }

    [RelayCommand]
    private async Task OpenDocument()
    {
        var opened = await fileService.OpenMarkdownAsync();
        if (opened is null)
        {
            return;
        }

        DocumentPath = opened.Path;
        Markdown = opened.Markdown;
        lastSavedMarkdown = Markdown;
        IsEdited = false;
    }

    [RelayCommand]
    private void CloseDocument()
    {
        NewDocument();
    }

    [RelayCommand]
    private async Task SaveDocument()
    {
        if (DocumentPath is null)
        {
            await SaveDocumentAs();
            return;
        }

        await fileService.SaveMarkdownAsync(DocumentPath, Markdown);
        lastSavedMarkdown = Markdown;
        IsEdited = false;
    }

    [RelayCommand]
    private async Task SaveDocumentAs()
    {
        var saved = await fileService.SaveMarkdownAsAsync(Markdown, DocumentPath);
        if (saved is null)
        {
            return;
        }

        DocumentPath = saved.Path;
        lastSavedMarkdown = Markdown;
        IsEdited = false;
    }

    [RelayCommand]
    private async Task RevertDocument()
    {
        if (DocumentPath is null)
        {
            Markdown = lastSavedMarkdown;
            IsEdited = false;
            return;
        }

        Markdown = await fileService.ReadMarkdownAsync(DocumentPath);
        lastSavedMarkdown = Markdown;
        IsEdited = false;
    }

    [RelayCommand]
    private void PrintDocument()
    {
        // The WinUI print pipeline is wired in the runtime verifier milestone.
    }

    [RelayCommand]
    private void PageSetup()
    {
        // Windows has no direct AppKit-style page setup panel; kept as a command parity hook.
    }

    [RelayCommand]
    private void IncreaseTextSize()
    {
        ViewScale = Math.Min(2.2, ViewScale * ZoomStep);
        ViewScaleChanged?.Invoke(ViewScale);
    }

    [RelayCommand]
    private void DecreaseTextSize()
    {
        ViewScale = Math.Max(0.72, ViewScale / ZoomStep);
        ViewScaleChanged?.Invoke(ViewScale);
    }

    [RelayCommand]
    private void ResetTextSize()
    {
        ViewScale = DefaultViewScale;
        ViewScaleChanged?.Invoke(ViewScale);
    }

    [RelayCommand]
    private void ToggleBold() => EditRequested?.Invoke(EditorEditAction.Wrap("**", "**"));

    [RelayCommand]
    private void ToggleItalic() => EditRequested?.Invoke(EditorEditAction.Wrap("_", "_"));

    [RelayCommand]
    private void ToggleCode() => EditRequested?.Invoke(EditorEditAction.Wrap("`", "`"));

    [RelayCommand]
    private void Heading1() => EditRequested?.Invoke(EditorEditAction.Heading(1));

    [RelayCommand]
    private void Heading2() => EditRequested?.Invoke(EditorEditAction.Heading(2));

    [RelayCommand]
    private void Undo() => EditorCommandRequested?.Invoke(EditorCommandKind.Undo);

    [RelayCommand]
    private void Redo() => EditorCommandRequested?.Invoke(EditorCommandKind.Redo);

    [RelayCommand]
    private void Cut() => EditorCommandRequested?.Invoke(EditorCommandKind.Cut);

    [RelayCommand]
    private void Copy() => EditorCommandRequested?.Invoke(EditorCommandKind.Copy);

    [RelayCommand]
    private void Paste() => EditorCommandRequested?.Invoke(EditorCommandKind.Paste);

    [RelayCommand]
    private void PastePlainText() => EditorCommandRequested?.Invoke(EditorCommandKind.PastePlainText);

    [RelayCommand]
    private void SelectAll() => EditorCommandRequested?.Invoke(EditorCommandKind.SelectAll);

    [RelayCommand]
    private void Find() => EditorCommandRequested?.Invoke(EditorCommandKind.Find);

    [RelayCommand]
    private void FindAndReplace() => EditorCommandRequested?.Invoke(EditorCommandKind.FindAndReplace);

    [RelayCommand]
    private void FindNext() => EditorCommandRequested?.Invoke(EditorCommandKind.FindNext);

    [RelayCommand]
    private void FindPrevious() => EditorCommandRequested?.Invoke(EditorCommandKind.FindPrevious);

    [RelayCommand]
    private void ShowPreviousTab()
    {
    }

    [RelayCommand]
    private void ShowNextTab()
    {
    }

    [RelayCommand]
    private void MoveTabToNewWindow()
    {
    }

    [RelayCommand]
    private void MergeAllWindows()
    {
    }

    private void UpdateDocumentTitle()
    {
        var name = DocumentPath is null ? "Untitled" : Path.GetFileName(DocumentPath);
        DocumentTitle = IsEdited ? $"{name} *" : name;
    }
}
