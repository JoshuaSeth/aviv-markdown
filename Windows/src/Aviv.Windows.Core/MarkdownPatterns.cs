using System.Text.RegularExpressions;

namespace Aviv.Windows.Core;

public static partial class MarkdownPatterns
{
    public const string Destination = @"((?:[^()\n\\]|\\.|\([^()\n]*\))+)";
    public const string Image = @"!\[([^\]\n]*)\]\(" + Destination + @"\)";
    public const string Link = @"(?<!!)\[([^\]\n]+)\]\(" + Destination + @"\)";

    public static readonly Regex ImageRegex = new(Image, RegexOptions.Compiled | RegexOptions.CultureInvariant);
    public static readonly Regex LinkRegex = new(Link, RegexOptions.Compiled | RegexOptions.CultureInvariant);
}
