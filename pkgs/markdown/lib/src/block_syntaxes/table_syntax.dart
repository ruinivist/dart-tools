// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast.dart';
import '../block_parser.dart';
import '../charcode.dart';
import '../patterns.dart';
import '../source_text.dart';
import 'block_syntax.dart';

/// Parses tables.
class TableSyntax extends BlockSyntax {
  @override
  bool canEndBlock(BlockParser parser) => true;

  @override
  RegExp get pattern => dummyPattern;

  const TableSyntax();

  @override
  bool canParse(BlockParser parser) {
    // Note: matches *next* line, not the current one. We're looking for the
    // bar separating the head row from the body rows.
    return parser.matchesNext(tablePattern);
  }

  /// Parses a table into its three parts:
  ///
  /// * a head row of head cells (`<th>` cells)
  /// * a divider of hyphens and pipes (not rendered)
  /// * many body rows of body cells (`<td>` cells)
  @override
  Node? parse(BlockParser parser) {
    final alignments = _parseAlignments(parser.next!.content);
    final columnCount = alignments.length;
    final headRow = _parseRow(parser, alignments, 'th');
    if (headRow.children!.length != columnCount) {
      parser.retreat();
      return null;
    }
    final head = Element('thead', [headRow]);

    // Advance past the divider of hyphens.
    parser.advance();

    final rows = <Node>[];
    while (!parser.isDone && !BlockSyntax.isAtBlockEnd(parser)) {
      final row = _parseRow(parser, alignments, 'td');
      final children = row.children!;
      while (children.length < columnCount) {
        // Insert synthetic empty cells.
        children.add(Element('td', []));
      }
      while (children.length > columnCount) {
        children.removeLast();
      }
      rows.add(row);
    }
    if (rows.isEmpty) {
      return Element('table', [head]);
    } else {
      final body = Element('tbody', rows);

      return Element('table', [head, body]);
    }
  }

  List<String?> _parseAlignments(String line) {
    final columns = <String?>[];
    // Set the value to `true` when hitting a non whitespace character other
    // than the first pipe character.
    var started = false;
    var hitDash = false;
    String? alignment;

    for (var i = 0; i < line.length; i++) {
      final char = line.codeUnitAt(i);
      if (char == $space || char == $tab || (!started && char == $pipe)) {
        continue;
      }
      started = true;

      if (char == $colon) {
        if (hitDash) {
          alignment = alignment == 'left' ? 'center' : 'right';
        } else {
          alignment = 'left';
        }
      }

      if (char == $pipe) {
        columns.add(alignment);
        hitDash = false;
        alignment = null;
      } else {
        hitDash = true;
      }
    }

    if (hitDash) {
      columns.add(alignment);
    }

    return columns;
  }

  /// Parses a table row at the current line into a table row element, with
  /// parsed table cells.
  ///
  /// [alignments] is used to annotate an alignment on each cell, and
  /// [cellType] is used to declare either "td" or "th" cells.
  Element _parseRow(
    BlockParser parser,
    List<String?> alignments,
    String cellType,
  ) {
    final line = parser.current;
    final cells = <SourceText>[];
    var index = _walkPastOpeningPipe(line.content);
    var runStart = index;
    var cellBuffer = SourceTextBuilder(line.source.slice(index, index));

    while (true) {
      if (index >= line.content.length) {
        cellBuffer.add(line.source.slice(runStart, index));
        cells.add(cellBuffer.build().trimRight());
        break;
      }
      final ch = line.content.codeUnitAt(index);
      if (ch == $backslash) {
        if (index + 1 < line.content.length) {
          if (line.content.codeUnitAt(index + 1) == $pipe) {
            // Table escaping runs before inline parsing, including code spans.
            cellBuffer.add(line.source.slice(runStart, index));
            cellBuffer.add(
              line.source.slice(index, index + 2).replaceWith('|'),
            );
            runStart = index + 2;
          }
          index += 2;
        } else {
          index++;
        }
      } else if (ch == $pipe) {
        cellBuffer.add(line.source.slice(runStart, index));
        cells.add(cellBuffer.build().trimRight());
        index = _walkPastWhitespace(line.content, index + 1);
        if (index >= line.content.length) break;
        runStart = index;
        cellBuffer = SourceTextBuilder(line.source.slice(index, index));
      } else {
        index++;
      }
    }
    parser.advance();
    final row = [
      for (final cell in cells) Element(cellType, [UnparsedContent(cell)]),
    ];

    for (var i = 0; i < row.length && i < alignments.length; i++) {
      if (alignments[i] == null) continue;
      row[i].attributes['align'] = '${alignments[i]}';
    }

    return Element('tr', <Node>[...row]);
  }

  /// Walks past whitespace in [line] starting at [index].
  ///
  /// Returns the index of the first non-whitespace character.
  int _walkPastWhitespace(String line, int index) {
    while (index < line.length) {
      final ch = line.codeUnitAt(index);
      if (ch != $space && ch != $tab) {
        break;
      }
      index++;
    }
    return index;
  }

  /// Walks past the opening pipe (and any whitespace that surrounds it) in
  /// [line].
  ///
  /// Returns the index of the first non-whitespace character after the pipe.
  /// If no opening pipe is found, this just returns the index of the first
  /// non-whitespace character.
  int _walkPastOpeningPipe(String line) {
    var index = 0;
    while (index < line.length) {
      final ch = line.codeUnitAt(index);
      if (ch == $pipe) {
        index++;
        index = _walkPastWhitespace(line, index);
      }
      if (ch != $space && ch != $tab) {
        // No leading pipe.
        break;
      }
      index++;
    }
    return index;
  }
}
