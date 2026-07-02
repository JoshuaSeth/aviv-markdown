using Aviv.Windows.Core;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml.Controls;

namespace Aviv.Windows.App.Services;

public sealed class WinUiMarkdownFormatter
{
    private const float BodyFontSize = 17;
    private const float CodeFontSize = 15;
    private const float HiddenSyntaxFontSize = 0.1f;

    public void Apply(RichEditBox editor, MarkdownStyleSnapshot snapshot, double viewScale)
    {
        var document = editor.Document;
        var selectionStart = document.Selection.StartPosition;
        var selectionEnd = document.Selection.EndPosition;
        var fullRange = document.GetRange(0, snapshot.Markdown.Length);

        fullRange.CharacterFormat.Name = "Segoe UI";
        fullRange.CharacterFormat.Size = BodyFontSize * (float)viewScale;
        fullRange.CharacterFormat.ForegroundColor = ColorFromHex(0x20, 0x24, 0x2A);
        fullRange.CharacterFormat.BackgroundColor = Colors.Transparent;
        fullRange.CharacterFormat.Hidden = FormatEffect.Off;
        fullRange.CharacterFormat.Bold = FormatEffect.Off;
        fullRange.CharacterFormat.Italic = FormatEffect.Off;
        fullRange.CharacterFormat.Underline = UnderlineType.None;
        fullRange.CharacterFormat.Strikethrough = FormatEffect.Off;

        foreach (var run in snapshot.Runs)
        {
            if (run.Range.Length <= 0 || run.Range.Start >= snapshot.Markdown.Length)
            {
                continue;
            }

            var range = document.GetRange(run.Range.Start, Math.Min(snapshot.Markdown.Length, run.Range.End));
            ApplyRun(range, run, viewScale);
        }

        document.Selection.SetRange(
            Math.Clamp(selectionStart, 0, snapshot.Markdown.Length),
            Math.Clamp(selectionEnd, 0, snapshot.Markdown.Length));
    }

    private static void ApplyRun(ITextRange range, MarkdownStyleRun run, double viewScale)
    {
        switch (run.Role)
        {
            case MarkdownStyleRole.Heading:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Segoe UI Semibold";
                range.CharacterFormat.Size = HeadingSize(run.Detail, viewScale);
                range.CharacterFormat.Bold = FormatEffect.On;
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x20, 0x24, 0x2A);
                break;
            case MarkdownStyleRole.SyntaxHidden:
                range.CharacterFormat.Hidden = FormatEffect.On;
                range.CharacterFormat.Name = "Segoe UI";
                range.CharacterFormat.Size = HiddenSyntaxFontSize;
                range.CharacterFormat.ForegroundColor = Colors.Transparent;
                range.CharacterFormat.BackgroundColor = Colors.Transparent;
                break;
            case MarkdownStyleRole.SyntaxVisible:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Segoe UI";
                range.CharacterFormat.Size = BodyFontSize * (float)viewScale;
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x97, 0xA0, 0xAD);
                break;
            case MarkdownStyleRole.InlineCode:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Cascadia Mono";
                range.CharacterFormat.Size = CodeFontSize * (float)viewScale;
                range.CharacterFormat.BackgroundColor = ColorFromHex(0xF1, 0xF4, 0xF7);
                break;
            case MarkdownStyleRole.CodeBlock:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Cascadia Mono";
                range.CharacterFormat.Size = CodeFontSize * (float)viewScale;
                range.CharacterFormat.BackgroundColor = ColorFromHex(0xF1, 0xF4, 0xF7);
                break;
            case MarkdownStyleRole.LinkText:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x0C, 0x74, 0xB8);
                range.CharacterFormat.Underline = UnderlineType.Single;
                break;
            case MarkdownStyleRole.Bold:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Bold = FormatEffect.On;
                break;
            case MarkdownStyleRole.Italic:
            case MarkdownStyleRole.Quote:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Italic = FormatEffect.On;
                if (run.Role == MarkdownStyleRole.Quote)
                {
                    range.CharacterFormat.ForegroundColor = ColorFromHex(0x6A, 0x72, 0x80);
                }
                break;
            case MarkdownStyleRole.Strikethrough:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Strikethrough = FormatEffect.On;
                break;
            case MarkdownStyleRole.HorizontalRule:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x97, 0xA0, 0xAD);
                range.CharacterFormat.Strikethrough = FormatEffect.On;
                break;
            case MarkdownStyleRole.TaskMarkerChecked:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Cascadia Mono";
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x0C, 0x74, 0xB8);
                break;
            case MarkdownStyleRole.TaskMarkerUnchecked:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Cascadia Mono";
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x6A, 0x72, 0x80);
                break;
            case MarkdownStyleRole.Table:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.Name = "Cascadia Mono";
                range.CharacterFormat.Size = CodeFontSize * (float)viewScale;
                break;
            case MarkdownStyleRole.TableSeparatorHidden:
                range.CharacterFormat.Hidden = FormatEffect.On;
                range.CharacterFormat.Name = "Segoe UI";
                range.CharacterFormat.Size = HiddenSyntaxFontSize;
                range.CharacterFormat.ForegroundColor = Colors.Transparent;
                range.CharacterFormat.BackgroundColor = Colors.Transparent;
                break;
            case MarkdownStyleRole.ImageSource:
                range.CharacterFormat.Hidden = FormatEffect.Off;
                range.CharacterFormat.ForegroundColor = ColorFromHex(0x6A, 0x72, 0x80);
                range.CharacterFormat.BackgroundColor = ColorFromHex(0xF1, 0xF4, 0xF7);
                break;
        }
    }

    private static float HeadingSize(string? detail, double viewScale)
    {
        return (detail switch
        {
            "1" => 34,
            "2" => 27,
            "3" => 22,
            "4" => 19,
            "5" => 17,
            _ => 16
        }) * (float)viewScale;
    }

    private static global::Windows.UI.Color ColorFromHex(byte red, byte green, byte blue)
    {
        return global::Windows.UI.Color.FromArgb(255, red, green, blue);
    }
}
