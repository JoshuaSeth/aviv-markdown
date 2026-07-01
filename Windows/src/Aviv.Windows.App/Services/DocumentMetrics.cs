namespace Aviv.Windows.App.Services;

public sealed record DocumentMetrics(int WordCount, int LineCount)
{
    public string DisplayText => $"{WordCount} words  {LineCount} lines";

    public static DocumentMetrics For(string markdown)
    {
        var words = markdown.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length;
        var lines = Math.Max(1, markdown.Split('\n').Length);
        return new DocumentMetrics(words, lines);
    }
}
