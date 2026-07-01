namespace Aviv.Windows.Core;

public readonly record struct TextRange(int Start, int Length)
{
    public int End => Start + Length;

    public bool IsEmpty => Length == 0;

    public static TextRange Empty => new(0, 0);

    public bool Contains(int location, bool includeEnd = false)
    {
        return includeEnd
            ? location >= Start && location <= End
            : location >= Start && location < End;
    }

    public bool Intersects(TextRange other)
    {
        if (Length == 0 || other.Length == 0)
        {
            return Contains(other.Start, includeEnd: true) || other.Contains(Start, includeEnd: true);
        }

        return Start < other.End && other.Start < End;
    }

    public TextRange? Intersection(TextRange other)
    {
        var start = Math.Max(Start, other.Start);
        var end = Math.Min(End, other.End);
        return end >= start ? new TextRange(start, end - start) : null;
    }

    public TextRange OffsetBy(int offset) => new(Start + offset, Length);
}
