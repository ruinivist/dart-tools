// Owns mutable state for one Markdown input and completes its parsed AST.
// Shared by nested parsers created from Document configuration.

// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'ast.dart';
import 'block_parser.dart';
import 'document.dart';
import 'inline_parser.dart';
import 'line.dart';
import 'source_text.dart';

/// The source and mutable reference state of one parse invocation.
/// Syntax extensions use the context shared by their block and inline parsers.
class ParseContext {
  final Document document;
  final SourceText source;

  ParseContext(this.document, String source) : source = SourceText(source);

  final Map<String, LinkReference> linkReferences = {};

  /// Footnote ref count, keys are case-sensitive and added by define syntax.
  final footnoteReferences = <String, int>{};

  /// Footnote labels by appearing order.
  ///
  /// They are case-insensitive and added by ref syntax.
  final footnoteLabels = <String>[];

  // ---------- AST completion ----------

  List<Node> parse() => parseBlocks(source.splitLines().map(Line.new).toList());

  /// Parses mapped lines from this input, including deferred inline content.
  List<Node> parseBlocks(List<Line> lines) {
    final nodes = BlockParser(lines, this).parseLines();
    _parseInlineContent(nodes);
    return _filterFootnotes(nodes);
  }

  void _parseInlineContent(List<Node> nodes) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node is UnparsedContent) {
        final inlineNodes = InlineParser(node.source, this).parse();
        nodes.removeAt(i);
        nodes.insertAll(i, inlineNodes);
        i += inlineNodes.length - 1;
      } else if (node is Element && node.children != null) {
        _parseInlineContent(node.children!);
      }
    }
  }

  /// Footnotes could be defined in arbitrary positions of a document, we need
  /// to distinguish them and put them behind; and every footnote definition
  /// may have multiple backrefs, we need to append backrefs for it.
  List<Node> _filterFootnotes(List<Node> nodes) {
    final footnotes = <Element>[];
    final blocks = <Node>[];
    for (final node in nodes) {
      if (node is Element &&
          node.tag == 'li' &&
          footnoteReferences.containsKey(node.footnoteLabel)) {
        final label = node.footnoteLabel;
        var count = 0;
        if (label != null && (count = footnoteReferences[label] ?? 0) > 0) {
          footnotes.add(node);
          final children = node.children;
          if (children != null) {
            _appendBackref(children, Uri.encodeComponent(label), count);
          }
        }
      } else {
        blocks.add(node);
      }
    }

    if (footnotes.isNotEmpty) {
      // Sort footnotes by appearing order.
      final ordinal = {
        for (var i = 0; i < footnoteLabels.length; i++)
          'fn-${footnoteLabels[i]}': i,
      };
      footnotes.sort((l, r) {
        final idl = l.attributes['id']?.toLowerCase() ?? '';
        final idr = r.attributes['id']?.toLowerCase() ?? '';
        return (ordinal[idl] ?? 0) - (ordinal[idr] ?? 0);
      });
      final list = Element('ol', <Node>[...footnotes]);

      // Ignore GFM attribute: <data-footnotes>.
      final section = Element('section', [list])
        ..attributes['class'] = 'footnotes';
      blocks.add(section);
    }
    return blocks;
  }

  /// Generate backref nodes, append them to footnote definition's last child.
  void _appendBackref(List<Node> children, String ref, int count) {
    final refs = [
      for (var i = 0; i < count; i++) ...[
        Text(' '),
        _ElementExt.footnoteAnchor(ref, i),
      ],
    ];
    if (children.isEmpty) {
      children.addAll(refs);
    } else {
      final last = children.last;
      if (last is Element && last.children != null) {
        last.children!.addAll(refs);
      } else if (last is Element) {
        children.addAll(refs);
      } else {
        children.last = Element('p', [last, ...refs]);
      }
    }
  }
}

extension _ElementExt on Element {
  static Element footnoteAnchor(String ref, int i) {
    final num = '${i + 1}';
    final suffix = i > 0 ? '-$num' : '';
    return Element('a', [
        Text('\u21a9'),
        if (i > 0)
          Element('sup', [Text(num)])..attributes['class'] = 'footnote-ref',
      ])
      // Ignore GFM's attributes:
      // <data-footnote-backref aria-label="Back to content">.
      ..attributes['href'] = '#fnref-$ref$suffix'
      ..attributes['class'] = 'footnote-backref';
  }
}
