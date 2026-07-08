namespace Aviv.Windows.App.Services;

public sealed record DocumentMetrics(int WordCount, int LineCount)
{
    public string DisplayText => $"{WordCount} words  {LineCount} lines";

    public static DocumentMetrics For(string markdown)
    {
        var words = 0;
        var lines = 1;
        var insideWord = false;

        foreach (var character in markdown)
        {
            if (character == '\n')
            {
                lines++;
            }

            if (char.IsWhiteSpace(character))
            {
                insideWord = false;
            }
            else if (!insideWord)
            {
                words++;
                insideWord = true;
            }
        }

        return new DocumentMetrics(words, lines);
    }
}
