// Preserves original offsets while Markdown text is sliced and transformed.
// Used by block parsers, inline parsers, and source-aware syntax extensions.

// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'source_range.dart';

// ---------- Mapped text ----------

/// Text whose segments refer to one original input string.
/// Extensions must pass slices of this value when deferring inline parsing.
class SourceText {
  final String text;
  final String originalSource;
  final List<_Segment> _segments;
  final int _emptyOffset;

  SourceText(String source)
    : text = source,
      originalSource = source,
      _segments = source.isEmpty
          ? const []
          : [_Segment(0, source.length, 0, source.length)],
      _emptyOffset = 0;

  SourceText._(
    this.text,
    this.originalSource,
    this._segments,
    this._emptyOffset,
  );

  /// Rejects text constructed from a different input instead of a mapped slice.
  void checkSource(SourceText other) {
    if (!identical(originalSource, other.originalSource)) {
      throw ArgumentError('Use a slice of the current parse context source.');
    }
  }

  SourceText slice(int start, [int? end]) {
    end = RangeError.checkValidRange(start, end, text.length);
    if (start == 0 && end == text.length) return this;
    if (start == end) {
      return SourceText._('', originalSource, const [], _boundaryOffset(start));
    }
    final segments = <_Segment>[];
    for (var i = _segmentIndex(start); i < _segments.length; i++) {
      final segment = _segments[i];
      if (segment.start >= end) break;
      final left = start > segment.start ? start : segment.start;
      final right = end < segment.end ? end : segment.end;
      segments.add(
        _Segment(
          left - start,
          right - start,
          segment.sourceStartAt(left),
          segment.sourceEndAt(right),
        ),
      );
    }
    return SourceText._(
      text.substring(start, end),
      originalSource,
      segments,
      _emptyOffset,
    );
  }

  SourceText trimLeft() => slice(text.length - text.trimLeft().length);
  SourceText trimRight() => slice(0, text.trimRight().length);
  SourceText trim() => trimLeft().trimRight();

  /// Replaces a source span with one code unit, as for escaped table pipes.
  SourceText replaceWith(String character) {
    if (character.length != 1 || text.isEmpty) {
      throw ArgumentError(
        'Replacement needs one code unit and nonempty source.',
      );
    }
    final location = range(0, text.length);
    return SourceText._(character, originalSource, [
      _Segment(0, 1, location.start, location.end),
    ], location.start);
  }

  /// Creates inserted text without source locations, such as padding spaces.
  /// Generated links should be emitted as AST nodes instead of reparsed text.
  SourceText synthetic(String text) => SourceText._(
    text,
    originalSource,
    text.isEmpty ? const [] : [_Segment(0, text.length, -1, -1)],
    -1,
  );

  /// Resolves a parsed span, including raw escapes removed by block processing.
  /// Throws when the span includes generated text with no original location.
  SourceRange range(int start, int end) {
    RangeError.checkValidRange(start, end, text.length);
    if (start == end) {
      final offset = _boundaryOffset(start);
      if (offset < 0) throw StateError('Generated text has no source range.');
      return SourceRange(offset, offset);
    }
    final first = _segmentIndex(start);
    final last = _segmentIndex(end - 1);
    var previousEnd = -1;
    for (var i = first; i <= last; i++) {
      if (_segments[i].sourceStart < 0 ||
          _segments[i].sourceStart < previousEnd) {
        throw StateError('Text has no ordered source range.');
      }
      previousEnd = _segments[i].sourceEnd;
    }
    return SourceRange(
      _segments[first].sourceStartAt(start),
      _segments[last].sourceEndAt(end),
    );
  }

  /// Splits LF, CRLF, and CR without discarding their original widths.
  List<SourceText> splitLines() {
    final lines = <SourceText>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text.codeUnitAt(i);
      if (char != 10 && char != 13) continue;
      lines.add(slice(start, i));
      if (char == 13 && i + 1 < text.length && text.codeUnitAt(i + 1) == 10) {
        i++;
      }
      start = i + 1;
    }
    if (start < text.length) lines.add(slice(start));
    return lines;
  }

  /// Joins mapped fragments; separators are parser-inserted characters.
  static SourceText join(Iterable<SourceText> parts, String separator) {
    final iterator = parts.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError('Expected at least one fragment.');
    }
    final first = iterator.current;
    if (!iterator.moveNext()) return first;
    final builder = SourceTextBuilder(first)..add(first);
    do {
      builder.addSynthetic(separator);
      builder.add(iterator.current);
    } while (iterator.moveNext());
    return builder.build();
  }

  int _boundaryOffset(int offset) {
    if (_segments.isEmpty) return _emptyOffset;
    final segment =
        _segments[_segmentIndex(offset == text.length ? offset - 1 : offset)];
    return offset == segment.end
        ? segment.sourceEndAt(offset)
        : segment.sourceStartAt(offset);
  }

  int _segmentIndex(int offset) {
    var low = 0;
    var high = _segments.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_segments[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

// ---------- Accumulation ----------

/// Accumulates text and coalesces adjacent mappings without copying prefixes.
/// Used to build inline content without rebuilding earlier fragments.
class SourceTextBuilder {
  final SourceText _source;
  final _text = StringBuffer();
  final _segments = <_Segment>[];

  SourceTextBuilder(this._source);

  void add(SourceText part) {
    _source.checkSource(part);
    final offset = _text.length;
    for (final segment in part._segments) {
      final next = _Segment(
        offset + segment.start,
        offset + segment.end,
        segment.sourceStart,
        segment.sourceEnd,
      );
      if (_segments.isNotEmpty) {
        final last = _segments.last;
        if (last.isLinear &&
            next.isLinear &&
            last.sourceEnd == next.sourceStart) {
          _segments[_segments.length - 1] = _Segment(
            last.start,
            next.end,
            last.sourceStart,
            next.sourceEnd,
          );
          continue;
        }
      }
      _segments.add(next);
    }
    _text.write(part.text);
  }

  void addSynthetic(String text) {
    if (text.isEmpty) return;
    _segments.add(_Segment(_text.length, _text.length + text.length, -1, -1));
    _text.write(text);
  }

  SourceText build() => SourceText._(
    _text.toString(),
    _source.originalSource,
    List.unmodifiable(_segments),
    _source._boundaryOffset(0),
  );
}

// ---------- Segments ----------

class _Segment {
  final int start;
  final int end;
  final int sourceStart;
  final int sourceEnd;

  const _Segment(this.start, this.end, this.sourceStart, this.sourceEnd);

  bool get isLinear =>
      sourceStart >= 0 && end - start == sourceEnd - sourceStart;
  int sourceStartAt(int offset) => sourceStart < 0
      ? -1
      : isLinear
      ? sourceStart + offset - start
      : sourceStart;
  int sourceEndAt(int offset) => sourceStart < 0
      ? -1
      : isLinear
      ? sourceStart + offset - start
      : sourceEnd;
}
