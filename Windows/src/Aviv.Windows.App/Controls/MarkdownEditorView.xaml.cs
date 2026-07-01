using Aviv.Windows.App.Services;
using Aviv.Windows.App.ViewModels;
using Aviv.Windows.Core;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace Aviv.Windows.App.Controls;

public sealed partial class MarkdownEditorView : UserControl
{
    private readonly RichEditBox Editor;
    private readonly MarkdownMinimapView Minimap;
    private readonly Popup SourcePopup;
    private readonly TextBox SourceEditor;
    private readonly MarkdownStyler styler = new();
    private readonly WinUiMarkdownFormatter formatter = new();
    private bool applying;
    private bool isLoaded;
    private double viewScale = 1.0;
    private MarkdownEditableSourceSpan? activeSourceSpan;

    public event Action<string>? MarkdownChanged;

    public string Markdown { get; private set; } = string.Empty;

    public MarkdownEditorView()
    {
        DiagnosticLog.Write("MarkdownEditorView constructor starting.");
        (Editor, Minimap, SourcePopup, SourceEditor) = BuildLayout();
        Minimap.ScrollRatioRequested += ScrollToRatio;
        Loaded += OnLoaded;
        DiagnosticLog.Write("MarkdownEditorView constructor completed.");
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        DiagnosticLog.Write("MarkdownEditorView loaded.");
        isLoaded = true;
        DiagnosticLog.Write("MarkdownEditorView initial style starting.");
        ApplyMarkdownStyle();
        DiagnosticLog.Write("MarkdownEditorView initial style completed.");
        Editor.Focus(FocusState.Programmatic);
        DiagnosticLog.Write("MarkdownEditorView initial focus completed.");
    }

    private (RichEditBox Editor, MarkdownMinimapView Minimap, Popup SourcePopup, TextBox SourceEditor) BuildLayout()
    {
        var root = new Grid
        {
            Background = Brush(0xFF, 0xFB, 0xFC, 0xFD)
        };

        var editor = new RichEditBox
        {
            AcceptsReturn = true,
            BorderThickness = new Thickness(0),
            Background = Brush(0x00, 0xFF, 0xFF, 0xFF),
            FontFamily = new FontFamily("Segoe UI"),
            FontSize = 17,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            IsSpellCheckEnabled = true,
            Padding = new Thickness(64, 72, 122, 52),
            SelectionHighlightColor = Brush(0x33, 0x24, 0x8A, 0xCB),
            TextWrapping = TextWrapping.Wrap,
            VerticalAlignment = VerticalAlignment.Stretch
        };
        root.Children.Add(editor);

        var titleText = new TextBlock
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 12,
            Foreground = Brush(0xFF, 0x6A, 0x72, 0x80)
        };
        titleText.SetBinding(TextBlock.TextProperty, new Binding { Path = new PropertyPath("DocumentTitle") });

        var titleBar = new Border
        {
            Height = 54,
            VerticalAlignment = VerticalAlignment.Top,
            Background = Brush(0xDD, 0xFD, 0xFE, 0xFF),
            BorderBrush = Brush(0x1F, 0x6B, 0x72, 0x80),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Child = titleText
        };
        root.Children.Add(titleBar);

        var minimap = new MarkdownMinimapView
        {
            Margin = new Thickness(5)
        };
        var minimapChrome = new Border
        {
            Width = 86,
            Margin = new Thickness(0, 58, 12, 40),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Stretch,
            Background = Brush(0xDD, 0xFD, 0xFE, 0xFF),
            BorderBrush = Brush(0x1F, 0x6B, 0x72, 0x80),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(7),
            Child = minimap
        };
        root.Children.Add(minimapChrome);

        var statusText = new TextBlock
        {
            Margin = new Thickness(0, 0, 18, 12),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            FontSize = 12,
            Foreground = Brush(0xFF, 0x6A, 0x72, 0x80)
        };
        statusText.SetBinding(TextBlock.TextProperty, new Binding { Path = new PropertyPath("StatusText") });
        root.Children.Add(statusText);

        var sourceEditor = new TextBox
        {
            MinWidth = 280,
            BorderThickness = new Thickness(0),
            FontFamily = new FontFamily("Cascadia Mono"),
            FontSize = 12
        };
        var sourcePopup = new Popup
        {
            IsLightDismissEnabled = true,
            Child = new Border
            {
                Background = Brush(0xDD, 0xFD, 0xFE, 0xFF),
                BorderBrush = Brush(0x1F, 0x6B, 0x72, 0x80),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(6),
                Padding = new Thickness(6),
                Child = sourceEditor
            }
        };

        editor.TextChanged += OnTextChanged;
        editor.SelectionChanged += OnSelectionChanged;
        sourceEditor.KeyDown += OnSourceEditorKeyDown;
        root.Children.Add(sourcePopup);
        Content = root;

        return (editor, minimap, sourcePopup, sourceEditor);
    }

    private static SolidColorBrush Brush(byte a, byte r, byte g, byte b)
    {
        return new SolidColorBrush(global::Windows.UI.Color.FromArgb(a, r, g, b));
    }

    public void LoadMarkdown(string markdown)
    {
        DiagnosticLog.Write($"MarkdownEditorView.LoadMarkdown length={markdown.Length}.");
        applying = true;
        Markdown = markdown;
        Editor.Document.SetText(TextSetOptions.None, markdown);
        applying = false;
        if (isLoaded)
        {
            ApplyMarkdownStyle();
            Editor.Focus(FocusState.Programmatic);
        }
    }

    public void SetViewScale(double scale)
    {
        viewScale = scale;
        Editor.FontSize = 17 * viewScale;
        Editor.Padding = new Thickness(64 * viewScale, 72 * viewScale, 122 * viewScale, 52 * viewScale);
        ApplyMarkdownStyle();
    }

    public void ApplyEditAction(EditorEditAction action)
    {
        var selection = CurrentSelection();
        var result = action.Kind switch
        {
            EditorEditActionKind.Wrap => MarkdownEditTransformer.WrapSelection(Markdown, selection, action.Prefix, action.Suffix),
            EditorEditActionKind.Heading => MarkdownEditTransformer.MakeHeading(Markdown, selection, action.HeadingLevel),
            _ => new MarkdownEditResult(Markdown, selection)
        };

        LoadMarkdown(result.Markdown);
        Editor.Document.Selection.SetRange(result.Selection.Start, result.Selection.End);
        Editor.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
        MarkdownChanged?.Invoke(Markdown);
    }

    public void PerformEditorCommand(EditorCommandKind command)
    {
        switch (command)
        {
            case EditorCommandKind.Undo:
                Editor.Document.Undo();
                break;
            case EditorCommandKind.Redo:
                Editor.Document.Redo();
                break;
            case EditorCommandKind.Cut:
                Editor.Document.Selection.Cut();
                break;
            case EditorCommandKind.Copy:
                Editor.Document.Selection.Copy();
                break;
            case EditorCommandKind.Paste:
            case EditorCommandKind.PastePlainText:
                Editor.Document.Selection.Paste(0);
                break;
            case EditorCommandKind.SelectAll:
                Editor.Document.Selection.SetRange(0, Markdown.Length);
                break;
            case EditorCommandKind.Find:
            case EditorCommandKind.FindAndReplace:
            case EditorCommandKind.FindNext:
            case EditorCommandKind.FindPrevious:
                Editor.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
                break;
        }
    }

    private void OnTextChanged(object sender, RoutedEventArgs args)
    {
        if (applying || !isLoaded)
        {
            return;
        }

        Markdown = ReadEditorText();
        MarkdownChanged?.Invoke(Markdown);
        ApplyMarkdownStyle();
    }

    private void OnSelectionChanged(object sender, RoutedEventArgs args)
    {
        if (!applying)
        {
            ApplyMarkdownStyle();
            UpdateSourceEditor();
        }
    }

    private void ApplyMarkdownStyle()
    {
        if (applying || !isLoaded)
        {
            return;
        }

        DiagnosticLog.Write($"MarkdownEditorView.ApplyMarkdownStyle starting length={Markdown.Length}.");
        applying = true;
        Markdown = ReadEditorText();
        var snapshot = styler.Snapshot(Markdown, [CurrentSelection()]);
        formatter.Apply(Editor, snapshot, viewScale);
        RenderMinimap();
        applying = false;
        DiagnosticLog.Write("MarkdownEditorView.ApplyMarkdownStyle completed.");
    }

    private void UpdateSourceEditor()
    {
        var selection = CurrentSelection();
        if (selection.Length != 0)
        {
            SourcePopup.IsOpen = false;
            activeSourceSpan = null;
            return;
        }

        activeSourceSpan = MarkdownSourceSpanParser.EditableSpanContaining(selection.Start, Markdown);
        if (activeSourceSpan is null)
        {
            SourcePopup.IsOpen = false;
            return;
        }

        SourceEditor.Text = activeSourceSpan.Source;
        SourcePopup.XamlRoot = XamlRoot;
        SourcePopup.HorizontalOffset = 80;
        SourcePopup.VerticalOffset = 58;
        SourcePopup.IsOpen = true;
    }

    private void OnSourceEditorKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key != global::Windows.System.VirtualKey.Enter || activeSourceSpan is null)
        {
            return;
        }

        var span = activeSourceSpan;
        var next = Markdown.Remove(span.Range.Start, span.Range.Length).Insert(span.Range.Start, SourceEditor.Text);
        LoadMarkdown(next);
        Editor.Document.Selection.SetRange(span.Range.Start, span.Range.Start + SourceEditor.Text.Length);
        MarkdownChanged?.Invoke(Markdown);
        SourcePopup.IsOpen = false;
        args.Handled = true;
    }

    private TextRange CurrentSelection()
    {
        var selection = Editor.Document.Selection;
        var start = Math.Clamp(Math.Min(selection.StartPosition, selection.EndPosition), 0, Math.Max(0, Markdown.Length));
        var end = Math.Clamp(Math.Max(selection.StartPosition, selection.EndPosition), 0, Math.Max(0, Markdown.Length));
        return new TextRange(start, end - start);
    }

    private string ReadEditorText()
    {
        Editor.Document.GetText(TextGetOptions.None, out var text);
        return text.Replace("\r", string.Empty, StringComparison.Ordinal);
    }

    private void RenderMinimap()
    {
        var lines = Math.Max(1, Markdown.Split('\n').Length);
        var visibleLines = 28 / Math.Max(0.72, viewScale);
        var currentLine = Markdown[..Math.Clamp(CurrentSelection().Start, 0, Markdown.Length)].Count(character => character == '\n');
        var documentHeight = Math.Max(visibleLines, lines);
        var visibleMinY = Math.Min(Math.Max(0, currentLine - visibleLines / 2), Math.Max(0, documentHeight - visibleLines));
        Minimap.Render(Markdown, visibleMinY, visibleLines, documentHeight);
    }

    private void ScrollToRatio(double ratio)
    {
        var targetLine = (int)Math.Round(Math.Clamp(ratio, 0, 1) * Math.Max(0, Markdown.Split('\n').Length - 1));
        var index = 0;
        for (var line = 0; line < targetLine && index < Markdown.Length; line++)
        {
            var next = Markdown.IndexOf('\n', index);
            if (next < 0)
            {
                break;
            }

            index = next + 1;
        }

        Editor.Document.Selection.SetRange(index, index);
        Editor.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
    }
}
