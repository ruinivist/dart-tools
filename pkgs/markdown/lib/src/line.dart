// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'patterns.dart';
import 'source_text.dart';

/// A [Line] is a sequence of zero or more characters other than line feed
/// (`U+000A`) or carriage return (`U+000D`), followed by a line ending or by
/// the end of file.
// See https://spec.commonmark.org/0.30/#line.
class Line {
  /// A sequence of zero or more characters other than the line ending.
  final SourceText source;

  /// The original line terminator, empty at the end of input.
  final SourceText lineEnding;

  String get content => source.text;

  /// How many spaces of a tab that remains after part of it has been consumed.
  // See: https://spec.commonmark.org/0.30/#example-6
  // We cannot simply expand the `tabRemaining` to spaces, for example
  //
  // `>\t\tfoo`
  //
  // If we expand the 2 space width `tabRemaining` from blockquote block into 2
  // spaces, so the string segment for the indented code block is:
  //
  // `  \tfoo`,
  //
  // then the output will be:
  // ```html
  // <pre><code>foo
  // </code></pre>
  // ```
  // instead of the expected:
  // ```html
  // <pre><code>  foo
  // </code></pre>
  // ```
  final int? tabRemaining;

  // A line containing no characters, or a line containing only spaces
  // (`U+0020`) or tabs (`U+0009`), is called a blank line.
  // https://spec.commonmark.org/0.30/#blank-line
  final bool isBlankLine;

  Line(this.source, {this.tabRemaining})
    : lineEnding = _lineEnding(source),
      isBlankLine = emptyPattern.hasMatch(source.text);

  /// Replaces parsed content while retaining this line's original terminator.
  Line.withSource(this.source, Line original, {this.tabRemaining})
    : lineEnding = original.lineEnding,
      isBlankLine = emptyPattern.hasMatch(source.text);

  static SourceText _lineEnding(SourceText source) {
    final start = source.range(source.text.length, source.text.length).end;
    final original = source.originalSource;
    var end = start;
    if (end < original.length) {
      final char = original.codeUnitAt(end);
      if (char == 10 || char == 13) {
        end++;
        if (char == 13 &&
            end < original.length &&
            original.codeUnitAt(end) == 10) {
          end++;
        }
      }
    }
    return SourceText(original).slice(start, end);
  }

  /// Joins logical lines with LF while preserving their original terminators.
  static SourceText join(Iterable<Line> lines) {
    final iterator = lines.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError('Expected at least one line.');
    }
    var previous = iterator.current;
    if (!iterator.moveNext()) return previous.source;
    final builder = SourceTextBuilder(previous.source)..add(previous.source);
    do {
      final ending = previous.lineEnding;
      if (ending.text.isEmpty) {
        throw StateError('Joined lines need a source terminator.');
      }
      builder.add(ending.text == '\n' ? ending : ending.replaceWith('\n'));
      builder.add(iterator.current.source);
      previous = iterator.current;
    } while (iterator.moveNext());
    return builder.build();
  }
}
