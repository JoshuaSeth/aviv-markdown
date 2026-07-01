namespace Aviv.Windows.Core;

public static class MarkdownSamples
{
    public const string Starter = """
    # Aviv Markdown

    A native, quiet markdown workspace. Move the insertion point through the document: syntax marks appear only on the active line, while the content keeps its geometry.

    ## Live preview without mode switches

    Write **bold text**, _emphasis_, `inline code`, and [links](https://typora.io) directly in the page. The raw markdown remains editable without a separate preview pane.

    - Open and save `.md` files with native panels
    - Keep layout stable while the cursor moves
    - Style headings, lists, quotes, rules, tables, code, links, and task lists

    > Markdown source should be understandable when you are editing it and calm when you are reading.

    - [x] Reveal syntax on the current line
    - [ ] Keep every glyph position stable when the cursor moves

    | Block | Behavior |
    | ----- | -------- |
    | Heading | Large rendered type with hidden `#` marks |
    | Code | Monospaced text with visible structure |
    | Link | Blue label with editable destination |

    ```swift
    let editor = NativeMarkdownEditor()
    editor.previewMode = .live
    ```

    ---

    A final paragraph gives the verifier a long wrapping line so layout stability is tested across multiple visual fragments, not only single-line headings.
    """;

    public const string LayoutFixture = """
    # Heading Stability

    This paragraph contains **strong text**, _quiet emphasis_, `inline code`, and [a stable link](https://example.com/stable) so the verifier can measure rendered content and hidden markdown syntax before and after cursor movement.

    ## Secondary Heading

    - [x] Checked item with **bold task content**
    - [ ] Open task with [linked text](https://example.com/task)

    > A quote keeps its source marker in layout even when the marker is visually suppressed.

    | One | Two |
    | --- | --- |
    | Alpha | Beta |

    ```swift
    let positions = layout.measure()
    assert(positions.doNotMove)
    ```
    """;
}
