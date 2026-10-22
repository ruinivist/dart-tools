// Checks source mapping independently of Markdown syntax recognition.
// Guards the text transformations shared by built-in parsers and extensions.

// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:markdown/markdown.dart';
import 'package:test/test.dart';

void main() {
  test('splitting preserves empty lines and original newline widths', () {
    final source = SourceText('a\r\nb\rc\n\n');
    final lines = source.splitLines();
    expect(lines.map((line) => line.text), ['a', 'b', 'c', '']);
    expect(lines.map((line) => line.range(0, line.text.length)), [
      const SourceRange(0, 1),
      const SourceRange(3, 4),
      const SourceRange(5, 6),
      const SourceRange(7, 7),
    ]);
    expect(SourceText('').splitLines(), isEmpty);
    expect(
      SourceText('\r\n').splitLines().single.range(0, 0),
      const SourceRange(0, 0),
    );
  });

  test(
    'nested slicing, trimming, and empty ranges retain original offsets',
    () {
      final source = SourceText('>>  abc  ');
      final content = source.slice(2).trim();
      expect(content.text, 'abc');
      expect(content.range(0, 3), const SourceRange(4, 7));
      expect(content.slice(1, 1).range(0, 0), const SourceRange(5, 5));
      expect(content.slice(3).range(0, 0), const SourceRange(7, 7));
      expect(source.slice(0, 0).range(0, 0), const SourceRange(0, 0));
    },
  );

  test(
    'joins retain source offsets on either side of synthetic separators',
    () {
      final source = SourceText('> abc\r\n> def');
      final content = SourceText.join(
        source.splitLines().map((line) => line.slice(2)),
        '\n',
      );
      expect(content.text, 'abc\ndef');
      expect(content.range(0, 3), const SourceRange(2, 5));
      expect(content.range(4, 7), const SourceRange(9, 12));
      expect(() => content.range(0, 7), throwsStateError);
    },
  );

  test('line joins map normalized LF to original line endings', () {
    final source = SourceText('> abc\r\n> def\r> ghi');
    final lines = source
        .splitLines()
        .map(Line.new)
        .map((line) => Line.withSource(line.source.slice(2), line));
    final content = Line.join(lines);
    expect(content.text, 'abc\ndef\nghi');
    expect(content.range(0, 7), const SourceRange(2, 12));
    expect(content.range(3, 4), const SourceRange(5, 7));
    expect(content.range(7, 8), const SourceRange(12, 13));
  });

  test('replaced characters map to the whole raw escape', () {
    final source = SourceText(r'a\|b');
    final content = SourceText.join([
      source.slice(0, 1),
      source.slice(1, 3).replaceWith('|'),
      source.slice(3),
    ], '');
    expect(content.text, 'a|b');
    expect(content.range(1, 2), const SourceRange(1, 3));
    expect(content.range(0, 3), const SourceRange(0, 4));
    expect(content.slice(1, 2).range(0, 1), const SourceRange(1, 3));
    expect(content.range(1, 1), const SourceRange(1, 1));
    expect(content.range(2, 2), const SourceRange(3, 3));
  });

  test('builder snapshots are stable after further additions', () {
    final source = SourceText('abc');
    final builder = SourceTextBuilder(source)..add(source.slice(0, 1));
    final first = builder.build();
    builder.add(source.slice(1));
    final last = builder.build();
    expect(first.text, 'a');
    expect(first.range(0, 1), const SourceRange(0, 1));
    expect(last.text, 'abc');
    expect(last.range(0, 3), const SourceRange(0, 3));
  });

  test('synthetic padding has no source range', () {
    final source = SourceText('abc');
    final content = SourceText.join([source.synthetic('  '), source], '');
    expect(content.range(2, 5), const SourceRange(0, 3));
    expect(() => content.range(0, 1), throwsStateError);
  });

  test('empty generated slices stay unmapped and can be trimmed', () {
    final source = SourceText('abc').synthetic('  ');
    final empty = source.trim();
    expect(empty.text, '');
    expect(() => empty.range(0, 0), throwsStateError);
    expect(() => source.synthetic('').range(0, 0), throwsStateError);
  });

  test('a range cannot run backward through reordered source fragments', () {
    final source = SourceText('abc');
    final reordered = SourceText.join([
      source.slice(2),
      source.slice(0, 1),
    ], '');
    expect(() => reordered.range(0, 2), throwsStateError);
  });

  test('out-of-bounds spans, empty joins, and mixed sources are rejected', () {
    final source = SourceText('abc');
    expect(() => source.slice(-1), throwsRangeError);
    expect(() => source.range(0, 4), throwsRangeError);
    expect(() => source.range(2, 1), throwsRangeError);
    expect(() => SourceText.join([], ''), throwsArgumentError);
    expect(() => source.replaceWith('too long'), throwsArgumentError);
    expect(() => source.slice(0, 0).replaceWith('|'), throwsArgumentError);
    expect(
      () => (SourceTextBuilder(source)..add(SourceText('other'))).build(),
      throwsArgumentError,
    );
  });
}
