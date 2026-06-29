# Manual Edge Cases

These 40 cases are covered by `MarkdownEdgeCaseTests` and are intended as the regression checklist for smooth cursor-line Markdown editing.

The test now verifies more than parser survival:

- The active cursor span exposes exactly the expected Markdown source annotations, with no unrelated inline markers leaking in from the same line.
- Table cases are detected as tables, hide raw source in reading mode, and reveal the active row source for editing.
- False table cases remain visible prose/source and are not converted into rendered tables.
- Link source spans target the full `[label](url)` range, including destinations with parentheses.
- Horizontal rules remain visibly rendered instead of being fully suppressed.

1. H1 heading
2. H6 heading
3. Heading with bold inline text
4. Paragraph bold
5. Underscore italic
6. Star italic
7. Strikethrough
8. Inline code
9. Inline code shielding Markdown markers
10. Basic link
11. Long URL link
12. Image syntax
13. Mixed bold, italic, code, and link
14. Two links on one line
15. Checked task with bold
16. Unchecked task with link
17. Bullet list
18. Ordered list
19. Nested list
20. Blockquote with link
21. Horizontal rule
22. Fenced Swift code
23. Basic table
24. Aligned table
25. Table without outer pipes
26. Table with inline code
27. Table with link
28. Table with escaped pipe text
29. Prose containing a pipe, not a table
30. Pipe rows without separator, not a table
31. Fenced pipe table, not a rendered table
32. Link URL containing parentheses
33. Underscore inside a word
34. Blank lines around bold text
35. Quoted task
36. Ordered list with dot
37. Ordered list with parenthesis
38. Inline HTML passthrough
39. Unicode text with Markdown
40. Mixed heading stress line
