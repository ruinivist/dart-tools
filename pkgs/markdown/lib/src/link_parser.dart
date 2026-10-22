// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'block_parser.dart';
import 'block_syntaxes/block_syntax.dart';
import 'charcode.dart';
import 'document.dart';
import 'source_range.dart';
import 'source_text.dart';
import 'util.dart';

class LinkParser {
  final BlockParser _blockParser;

  final _sourceLines = <SourceText>[];
  final _lineStarts = <int>[];
  int _length = 0;

  /// The current read position in the consumed lines.
  int _pos = 0;

  /// How many lines have been consumed from [_blockParser].
  int _linesConsumed = 1;

  /// Link label.
  late String _label;

  /// Link destination.
  late String _destination;
  late SourceRange _destinationRange;

  /// Link title.
  String? _title;

  LinkParser(this._blockParser) {
    _sourceLines.add(_blockParser.current.source);
    _lineStarts.add(0);
    _length = _sourceLines.first.text.length;
    _blockParser.advance();
  }

  int get pos => _pos;

  int get length => _length;

  bool get isDone => _pos == _length;

  int charAt([int? position]) {
    position ??= _pos;
    final line = _lineIndex(position);
    final offset = position - _lineStarts[line];
    return offset == _sourceLines[line].text.length
        ? $lf
        : _sourceLines[line].text.codeUnitAt(offset);
  }

  int _lineIndex(int position) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_lineStarts[mid] <= position) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  void advance() {
    _pos++;
  }

  String substring(int start, [int? end]) {
    end ??= _length;
    final buffer = StringBuffer();
    for (var i = _lineIndex(start); i < _sourceLines.length; i++) {
      final lineStart = _lineStarts[i];
      if (lineStart >= end) break;
      final text = _sourceLines[i].text;
      final left = start > lineStart ? start - lineStart : 0;
      final right = end < lineStart + text.length
          ? end - lineStart
          : text.length;
      buffer.write(text.substring(left, right));
      if (lineStart + text.length < end && i + 1 < _sourceLines.length) {
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }

  void _saveDestination(int start) {
    _destination = substring(start, pos);
    final line = _lineIndex(start);
    _destinationRange = _sourceLines[line].range(
      start - _lineStarts[line],
      pos - _lineStarts[line],
    );
  }

  LinkReference _definition() => LinkReference(
    normalizeLinkLabel(_label),
    _destination,
    _title,
    _destinationRange,
  );

  /// Walks the parser forward through horizontal whitespace on the current
  /// line.
  int moveThroughWhitespace() {
    var i = 0;
    while (!isDone) {
      final char = charAt();
      if (char != $space &&
          char != $tab &&
          char != $vt &&
          char != $cr &&
          char != $ff) {
        return i;
      }
      i++;
      advance();
    }
    return i;
  }

  /// Appends the next line from [_blockParser] if not at a block end.
  bool _tryAdvanceLine() {
    if (BlockSyntax.isAtBlockEnd(_blockParser)) {
      return false;
    }
    _lineStarts.add(_length + 1);
    final source = _blockParser.current.source;
    _sourceLines.add(source);
    _length += 1 + source.text.length;
    _blockParser.advance();
    _linesConsumed++;
    return true;
  }

  void _retreatTo(int targetLinesConsumed) {
    final delta = _linesConsumed - targetLinesConsumed;
    if (delta > 0) {
      _blockParser.retreatBy(delta);
      _linesConsumed = targetLinesConsumed;
    }
  }

  /// Whether [line] begins with optional horizontal whitespace followed by a
  /// link title opening delimiter (`'`, `"`, or `(`).
  static bool _startsWithTitleDelimiter(String line) {
    for (var i = 0; i < line.length; i++) {
      final char = line.codeUnitAt(i);
      if (char == $space ||
          char == $tab ||
          char == $vt ||
          char == $cr ||
          char == $ff) {
        continue;
      }
      return char == $apostrophe || char == $quote || char == $lparen;
    }
    return false;
  }

  /// Returns a complete definition, or null when the syntax is invalid.
  LinkReference? parseDefinition() {
    if (!parseLabel() || isDone || charAt() != $colon) {
      _retreatTo(0);
      return null;
    }

    // Advance to the next character after the colon.
    advance();
    if (!_parseDestination()) {
      _retreatTo(0);
      return null;
    }

    final precedingWhitespaces = moveThroughWhitespace();
    if (!isDone) {
      // A title on the same line as the destination must be preceded by
      // whitespace, and nothing but whitespace may follow the closing delimiter
      // on its line.
      // For example: `[foo]: <bar> "baz` is an invalid definition, and
      // `[foo]: <bar> "baz" hello` is also invalid
      // (see https://spec.commonmark.org/0.30/#example-209).
      if (precedingWhitespaces == 0 || !_parseTitle()) {
        _retreatTo(0);
        return null;
      }
      moveThroughWhitespace();
      if (!isDone) {
        _title = null;
        _retreatTo(0);
        return null;
      }
      return _definition();
    }

    // We reached the end of the destination's line, so `[label]: destination`
    // is already valid even if the next line is not a valid title
    // (see https://spec.commonmark.org/0.30/#example-210).
    final savedLinesConsumed = _linesConsumed;
    if (!_blockParser.isDone &&
        _startsWithTitleDelimiter(_blockParser.current.content) &&
        _tryAdvanceLine()) {
      // Advance past the line feed.
      advance();
      moveThroughWhitespace();
      if (_parseTitle()) {
        moveThroughWhitespace();
        if (!isDone) {
          _title = null;
          _retreatTo(savedLinesConsumed);
        }
      } else {
        _title = null;
        _retreatTo(savedLinesConsumed);
      }
    }

    return _definition();
  }

  /// Parses the link label, returns `true` if there is a valid link label.
  bool parseLabel() {
    moveThroughWhitespace();

    if (isDone || charAt() != $lbracket) {
      return false;
    }

    // Advance past the opening `[`.
    advance();
    final start = pos;

    // A link label can have at most 999 characters inside the square brackets.
    // See https://spec.commonmark.org/0.30/#link-label.
    var maxLoop = 999;
    while (true) {
      if (maxLoop-- < 0) {
        return false;
      }
      if (isDone && !_tryAdvanceLine()) {
        return false;
      }
      final char = charAt();
      if (char == $backslash) {
        advance();
        if (isDone && !_tryAdvanceLine()) {
          return false;
        }
      } else if (char == $lbracket) {
        return false;
      } else if (char == $rbracket) {
        break;
      }
      advance();
    }

    final text = substring(start, pos);
    if (text.isBlank) {
      return false;
    }

    // Advance past the closing `]`.
    advance();
    _label = text;
    return true;
  }

  /// Parses the link destination, returns `true` if there is a valid link
  /// destination.
  bool _parseDestination() {
    moveThroughWhitespace();
    if (isDone) {
      if (!_tryAdvanceLine()) {
        return false;
      }
      // Advance past the line feed.
      advance();
      moveThroughWhitespace();
      if (isDone) {
        return false;
      }
    }

    final isValidDestination = charAt() == $lt
        ? _parseBracketedDestination()
        : _parseBareDestination();

    return isValidDestination;
  }

  /// Parses bracketed destinations (destinations wrapped in `<...>`). The
  /// current position of the parser must be the first character of the
  /// destination.
  ///
  /// Returns `true` if there is a valid link destination.
  bool _parseBracketedDestination() {
    // Walk past the opening `<`.
    advance();
    if (isDone) {
      return false;
    }

    final start = pos;
    while (true) {
      final char = charAt();
      if (char == $backslash) {
        advance();
        if (isDone) {
          return false;
        }
      } else if (char == $lf || char == $cr || char == $ff) {
        return false;
      } else if (char == $gt) {
        break;
      }
      advance();
      if (isDone) {
        return false;
      }
    }

    _saveDestination(start);

    // Advance past the closing `>`.
    advance();
    return true;
  }

  /// Parse "bare" destinations (destinations _not_ wrapped in `<...>`). The
  /// current position of the parser must be the first character of the
  /// destination.
  ///
  /// Returns `true` if there is a valid link destination.
  bool _parseBareDestination() {
    var parenCount = 0;
    final start = pos;

    while (true) {
      final char = charAt();
      if (char == $backslash) {
        advance();
        if (isDone) {
          break;
        }
      } else if (char == $space || char == $lf || char == $cr || char == $ff) {
        break;
      } else if (char == $lparen) {
        parenCount++;
      } else if (char == $rparen) {
        parenCount--;
        if (parenCount < 0) {
          return false;
        }
      }
      advance();

      // There is no ending delimiter, so `isDone` also means it is at the end
      // of a link destination.
      if (isDone) {
        break;
      }
    }

    if (parenCount != 0) {
      return false;
    }

    _saveDestination(start);
    return true;
  }

  /// Parses the **optional** link title, returns `true` if there is a valid
  /// link title.
  bool _parseTitle() {
    // See: https://spec.commonmark.org/0.30/#link-title
    // The whitespace should be followed by a title delimiter.
    final delimiter = charAt();
    if (delimiter != $apostrophe &&
        delimiter != $quote &&
        delimiter != $lparen) {
      return false;
    }

    final closeDelimiter = delimiter == $lparen ? $rparen : delimiter;
    advance();
    final start = pos;

    // Looking for an un-escaped closing delimiter.
    while (true) {
      if (isDone && !_tryAdvanceLine()) {
        return false;
      }
      final char = charAt();
      if (char == $backslash) {
        advance();
        if (isDone && !_tryAdvanceLine()) {
          return false;
        }
      } else if (char == closeDelimiter) {
        break;
      }
      advance();
    }

    _title = substring(start, pos);

    // Advance past the closing delimiter.
    advance();
    return true;
  }
}
