# Markdown fork

## Why this was forked

Tools that rename attachments or move image files need to edit their paths in
Markdown. The same path can appear in prose, inline code, or a fenced code
example. A text replacement can change those occurrences too.

The upstream parser identifies real links and images, but its nodes retain
normalized `src` and `href` values without their original source positions.
This fork preserves destination ranges so applications can edit the original
Markdown while keeping its formatting, titles, and surrounding text.

Source tracking is always on. The parser carries mapped text through block
and inline parsing, and each input gets its own reference and footnote state.
The package name stays `markdown`, so imports still use
`package:markdown/markdown.dart`. Point your dependency at this fork to use
these changes.

## What the fork supports

`Element.destinationRange` identifies the raw destination in the input.

| Parsed form | Where the range points |
| --- | --- |
| Inline links and images, with bare or angle-bracketed destinations | The destination inside the delimiters, excluding surrounding whitespace and titles. |
| Full, collapsed, and shortcut references | The destination in the winning reference definition. |
| Angle autolinks and email autolinks | The URL or email address inside `<` and `>`. |
| GFM bare links and email addresses | The consumed URL or email text, excluding trailing punctuation. |

Ranges survive the existing block transformations: headings, lists and task
lists, blockquotes, fenced blockquotes, alerts, tables, and footnotes. Enable
the corresponding syntax extensions as usual. The fork adds source tracking
to those syntaxes; their normalized attributes and HTML rendering remain
available.

`SourceRange.start` and `end` are Dart UTF-16 string offsets, with an exclusive
end. They work with `substring` and `replaceRange`. Unicode before a target,
tabs, and LF, CRLF, or CR line endings retain their original offsets. Ranges
include raw escapes and entity text even when the rendered destination is
normalized. Empty destinations have `start == end`.

`Document.parse(source)` reports offsets in that exact source string.
`Document.parseInline(text)` reports offsets in its own input. Both start
with fresh reference definitions and footnote state, so you can reuse a
`Document` for independent inputs.

Elements without a source destination have a null `destinationRange`. This
includes resolver-generated links and footnote navigation. Raw HTML has no
parsed destination metadata. For automatic links, generated `http://` and
`mailto:` prefixes are absent from the source range.

## Reading and editing destinations

```dart
import 'package:markdown/markdown.dart';

void main() {
  const source = '![logo](assets/logo.svg "Logo")';
  final paragraph = Document().parse(source).single as Element;
  final image = paragraph.children!.single as Element;
  final range = image.destinationRange!;

  print(source.substring(range.start, range.end)); // assets/logo.svg
  final updated = source.replaceRange(
    range.start,
    range.end,
    'images/logo.svg',
  );
  print(updated); // ![logo](images/logo.svg "Logo")
}
```

For a whole document, walk the parsed elements and collect the destinations
you intend to change. To update images, collect ranges from `img` elements.
Deduplicate ranges, then apply replacements from right to left so earlier
offsets stay valid. Compute a new set of ranges after editing the input.

Reference uses share one immutable range. If an image and an ordinary link
use the same definition, editing that definition changes both destinations.
The first definition wins when a label is defined more than once. Your
application must decide whether changing a shared definition is appropriate.

Choose replacement text valid for the existing destination syntax, including
any escaping it needs. Editing an automatic link also changes its displayed
text. The library reports locations; your application chooses replacements and
writes the edited source. Completed trees from `Document.parse` and
`parseInline` retain offsets without keeping the source mapping structures
alive.

## Migrating from upstream

Calls to `markdownToHtml` keep the same interface. Code that uses parser
internals or custom syntax extensions needs the changes below.

`Document` now holds reusable settings. Each call to `parse` or `parseInline`
creates a fresh `ParseContext`. It owns the input, reference definitions,
footnote counts, and footnote order. Custom syntaxes share the context of the
parser they receive. Nested parsing of the same document should use that
context; a new call on `Document` starts an independent parse.

| Previous interface | Replacement |
| --- | --- |
| `Document.parseLines` or `Document.parseLineList` | Use `parse(originalSource)`. If only separate lines are available, explicitly join them with `\n`; offsets then refer to that constructed string. |
| Reference and footnote collections on `Document` | Access the corresponding collections through `parser.context`. Use builders or resolvers for externally supplied destinations. |
| `InlineParser(text, document)` | Pass mapped `SourceText` and the existing `ParseContext`. |
| `BlockParser(lines, document)` | Pass mapped `Line` values and the existing `ParseContext`. |
| `Line(text)` or `UnparsedContent(text)` | Pass `SourceText` from the current input. |
| `LinkSyntax.createNode` or `ImageSyntax.createNode` | Accept a required third argument, `SourceRange`, and pass it to the superclass or set it on the returned element. |
| `LinkReference(label, destination, title)` | Supply the destination's `SourceRange` as a required fourth argument. |

Read parser settings through `parser.context.document`. To start low-level
parsing, create `ParseContext(document, source)` and take mapped slices from
`context.source`. Constructing a new `SourceText` from transformed strings
loses the relationship to the original input; the parser rejects text from
another source with `ArgumentError`.

Internal inline parsing no longer calls an overridden `Document.parseInline`.
Use an `InlineSyntax` to customize inline parsing. If a custom block syntax
removes a prefix before deferring inline content, keep the mapped slice:

```dart
// Inside BlockSyntax.parse, after the syntax has matched the current line:
final match = pattern.firstMatch(parser.current.content)!;
final content = parser.current.source.slice(match.end);
parser.advance();
return Element('p', [UnparsedContent(content)]);
```

When replacing a line's content, use
`Line.withSource(content, originalLine)` to keep its original terminator.
Pass `tabRemaining` explicitly when your syntax needs to preserve it.
`Line.join` normalizes actual line endings to LF while retaining their
original ranges.

`SourceText` supports slicing, trimming, splitting lines, and joining mapped
fragments. `SourceTextBuilder` accumulates fragments without rebuilding
earlier text. Inserted padding and synthetic separators have no source
location; requesting a range containing generated text throws `StateError`.
Emit final AST nodes for generated content instead of reparsing it as if it
came from the input.
