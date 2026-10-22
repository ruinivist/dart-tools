// Checks destination locations against the original Markdown input.
// Exercises parser transformations, extensions, and caller-side editing.

// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:markdown/markdown.dart';
import 'package:test/test.dart';

// ---------- Destination behavior ----------

void main() {
  test('ranges use value equality and hashing', () {
    final ranges = {const SourceRange(2, 5)};
    expect(ranges.add(const SourceRange(2, 5)), isFalse);
    expect(const SourceRange(2, 5), isNot(const SourceRange(2, 6)));
  });

  test('bare, bracketed, empty, titled, and repeated destinations', () {
    const source =
        '![](a.png "title") [b](<b c>) ![]() [d](<> "title") '
        '![](a.png) [e](a(b)c)';
    final nodes = _destinations(Document().parse(source)).toList();
    final cases = [
      (4, 'a.png'),
      (24, 'b c'),
      (34, ''),
      (41, ''),
      (56, 'a.png'),
      (67, 'a(b)c'),
    ];
    expect(nodes, hasLength(cases.length));
    for (var i = 0; i < cases.length; i++) {
      _expectRange(source, nodes[i], cases[i].$1, cases[i].$2);
    }
    expect(nodes[0].attributes['title'], 'title');
    expect(nodes[1].attributes['href'], 'b%20c');
  });

  test('raw escapes and entities survive destination normalization', () {
    const source = r'![](a\(b\).png) [x](<a\>b&amp;c>)';
    final nodes = _destinations(Document().parse(source)).toList();
    _expectRange(source, nodes[0], 4, r'a\(b\).png');
    _expectRange(source, nodes[1], 21, r'a\>b&amp;c');
    expect(nodes[0].attributes['src'], 'a(b).png');
    expect(nodes[1].attributes['href'], 'a%3Eb&c');
  });

  test('prose, escaped syntax, code, and HTML have no image destinations', () {
    const prefix = 'old.png ![real](';
    const source =
        '${prefix}old.png)\n\n'
        r'\!\[fake\]\(old.png\)'
        '\n\n`![inline](old.png)`\n\n'
        '~~~\n![fenced](old.png)\n~~~\n\n'
        '    ![indented](old.png)\n\n<a href="old.png">link</a>\n';
    final nodes = _destinations(Document().parse(source)).toList();
    expect(nodes, hasLength(1));
    _expectRange(source, nodes.single, prefix.length, 'old.png');
  });

  final blocks = <String, (String, String, List<BlockSyntax>)>{
    'paragraph': ('  ', '  \n', []),
    'heading': ('## ', ' ##', []),
    'heading with id': ('# ', '', [const HeaderWithIdSyntax()]),
    'setext': ('', '\n---', []),
    'setext with id': ('', '\n===', [const SetextHeaderWithIdSyntax()]),
    'unordered list': ('- ', '', []),
    'ordered list': ('1. ', '', []),
    'task list': ('- [x] ', '', []),
    'ordered task list': ('1. [ ] ', '', []),
    'blockquote': ('> ', '', []),
    'nested list and quote': ('1. outer\n   - nested\n     > - [x] ', '', []),
    'lazy continuation': ('> first\n', '', []),
    'alert': ('> [!NOTE]\n> ', '', [const AlertBlockSyntax()]),
    'table': ('| head |\n| --- |\n| ', ' |', []),
    'footnote': ('Use [^n].\n\n[^n]: ', '', []),
    'footnote continuation': ('Use [^n].\n\n[^n]: first\n    ', '', []),
    'fenced blockquote': ('>>>\n', '\n>>>', [const FencedBlockquoteSyntax()]),
  };
  for (final entry in blocks.entries) {
    test('destinations inside ${entry.key}', () {
      final (prefix, suffix, syntaxes) = entry.value;
      final source = '$prefix![x](old.png) [y](<old.png>)$suffix';
      final document = Document(
        extensionSet: ExtensionSet.gitHubWeb,
        blockSyntaxes: syntaxes,
      );
      final nodes = _destinations(
        document.parse(source),
      ).where((node) => node.destinationRange != null).toList();
      expect(nodes, hasLength(2));
      _expectRange(source, nodes[0], prefix.length + 5, 'old.png');
      _expectRange(source, nodes[1], prefix.length + 19, 'old.png');
    });
  }

  test('dummy blocks preserve mapped inline content', () {
    const source = '  ![](a)\n![](b)';
    final nodes = _destinations(
      Document(withDefaultBlockSyntaxes: false).parse(source),
    ).toList();
    _expectRange(source, nodes[0], 6, 'a');
    _expectRange(source, nodes[1], 13, 'b');
  });

  test('table unescaping preserves complete raw destination spans', () {
    const prefix = '| h |\n| --- |\n| ';
    const source = '$prefix![](<\\|a\\|b>) [x](c\\|d) |';
    final nodes = _destinations(
      Document(extensionSet: ExtensionSet.gitHubFlavored).parse(source),
    ).toList();
    _expectRange(source, nodes[0], prefix.length + 5, r'\|a\|b');
    _expectRange(source, nodes[1], prefix.length + 18, r'c\|d');
    expect(nodes[0].attributes['src'], '%7Ca%7Cb');
    expect(nodes[1].attributes['href'], 'c%7Cd');
  });

  test('table destinations after repeated escaped pipes stay aligned', () {
    const prefix = '| h |\n| --- |\n| a\\|b\\|c ![](';
    const source = '${prefix}last.png) |';
    final node = _destinations(
      Document(extensionSet: ExtensionSet.gitHubFlavored).parse(source),
    ).single;
    _expectRange(source, node, prefix.length, 'last.png');
  });

  for (final ending in ['\n', '\r\n', '\r']) {
    test('Unicode, tabs, nesting, and line ending ${ending.codeUnits}', () {
      final prefix = '😀 e\u0301\t$ending$ending> - [x] ';
      final source = '$prefix![](<a\\(b\\).png> "title")';
      final node = _destinations(
        Document(extensionSet: ExtensionSet.gitHubFlavored).parse(source),
      ).single;
      _expectRange(source, node, prefix.length + 5, r'a\(b\).png');
      expect(prefix.codeUnits.length, prefix.length);
    });
  }

  test('escaped newlines in bare destinations preserve existing parsing', () {
    const source = '> ![](a\\\r\n> b)';
    final node = _destinations(Document().parse(source)).single;
    _expectRange(source, node, 6, 'a\\\r\n> b');
    expect(node.attributes['src'], 'a%5C%0Ab');
    expect(
      markdownToHtml(source),
      '<blockquote>\n<p><img src="a%5C%0Ab" alt="" /></p>\n</blockquote>\n',
    );
  });

  test('standalone inline parsing uses its own UTF-16 input offsets', () {
    const source = '😀\t![](a)\r\n[x](<b>)';
    final nodes = _destinations(Document().parseInline(source)).toList();
    _expectRange(source, nodes[0], 7, 'a');
    _expectRange(source, nodes[1], 16, 'b');
  });

  test(
    'full, collapsed, shortcut, and ordinary references share a definition',
    () {
      const prefix = '![full][ref] ![ref][] ![ref] [ordinary][REF]\n\n[ref]: <';
      const source = '${prefix}old.png> "title"';
      final context = ParseContext(Document(), source);
      final nodes = _destinations(context.parse()).toList();
      expect(nodes, hasLength(4));
      for (final node in nodes) {
        _expectRange(source, node, prefix.length, 'old.png');
        expect(node.attributes['title'], 'title');
        expect(
          identical(
            node.destinationRange,
            context.linkReferences['ref']!.destinationRange,
          ),
          isTrue,
        );
      }
    },
  );

  test('the first definition wins, before or after use', () {
    for (final definitionFirst in [true, false]) {
      const definition = '[ref]: first.png\n\n';
      const use = '![ref] [ref][]\n\n';
      final source = definitionFirst
          ? '$definition$use[ref]: second.png'
          : '$use$definition[ref]: second.png';
      final nodes = _destinations(Document().parse(source)).toList();
      expect(nodes, hasLength(2));
      for (final node in nodes) {
        _expectRange(
          source,
          node,
          (definitionFirst ? 0 : use.length) + 7,
          'first.png',
        );
      }
    }
  });

  test('multiline definitions retain destination and title boundaries', () {
    const prefix = '![A B]\r\n\r\n[a\r\nb]:\r\n  <';
    const source = '${prefix}a\\>b.png>\r\n  "multi\r\nline title"';
    final node = _destinations(Document().parse(source)).single;
    _expectRange(source, node, prefix.length, r'a\>b.png');
    expect(node.attributes['title'], 'multi\nline title');
  });

  for (final prefix in [
    '![ref]\n\n> [ref]: <',
    '![ref]\n\n- [ref]: <',
    '![ref]\n\n> [!NOTE]\n> [ref]: <',
    '![ref] [^n]\n\n[^n]: [ref]: <',
  ]) {
    test('reference definitions inside containers: $prefix', () {
      final source = '${prefix}a.png>';
      final node = _destinations(
        Document(extensionSet: ExtensionSet.gitHubWeb).parse(source),
      ).firstWhere((node) => node.tag == 'img');
      _expectRange(source, node, prefix.length, 'a.png');
    });
  }

  test('empty reference destinations keep an insertion location', () {
    const prefix = '![x]\n\n[x]: <';
    const source = '$prefix>';
    _expectRange(
      source,
      _destinations(Document().parse(source)).single,
      prefix.length,
      '',
    );
  });

  test('failed links and definitions do not produce destination nodes', () {
    const source = '![](a "unterminated)\n\n![ref]\n\n[ref]: <broken';
    expect(_destinations(Document().parse(source)), isEmpty);
  });

  test(
    'autolinks retain raw text without generated schemes or punctuation',
    () {
      const source =
          '<https://a.test/x> <a@b.test> www.c.test, '
          'https://d.test/a(b). e@f.test!';
      final nodes = _destinations(
        Document(extensionSet: ExtensionSet.gitHubFlavored).parse(source),
      ).toList();
      final cases = [
        (1, 'https://a.test/x'),
        (20, 'a@b.test'),
        (30, 'www.c.test'),
        (42, 'https://d.test/a(b)'),
        (63, 'e@f.test'),
      ];
      expect(nodes, hasLength(cases.length));
      for (var i = 0; i < cases.length; i++) {
        _expectRange(source, nodes[i], cases[i].$1, cases[i].$2);
      }
      expect(nodes[1].attributes['href'], 'mailto:a@b.test');
      expect(nodes[2].attributes['href'], 'http://www.c.test');
    },
  );

  test(
    'configuration reuse isolates references and leaves old ASTs intact',
    () {
      final document = Document(extensionSet: ExtensionSet.gitHubWeb);
      const first = '![ref]\n\n[ref]: first.png';
      final old = _destinations(document.parse(first)).single;
      expect(_destinations(document.parseInline('![ref]')), isEmpty);
      expect(_destinations(document.parse('![ref]')), isEmpty);
      const second = '[ref]: second.png\n\n![ref]';
      final fresh = _destinations(document.parse(second)).single;
      _expectRange(second, fresh, 7, 'second.png');
      _expectRange(first, old, 15, 'first.png');
      document.parse('[^one]\n\n[^one]: first');
      final footnotes = _destinations(document.parse('[^two]\n\n[^two]: next'));
      expect(footnotes.first.textContent, '1');
      expect(footnotes.every((node) => node.destinationRange == null), isTrue);
    },
  );

  test('reentrant parsing uses independent reference state', () {
    const innerSource = '![inner][same]\n\n[same]: inner.png';
    late List<Node> inner;
    late Document document;
    document = Document(
      imageLinkResolver: (label, [title]) {
        inner = document.parse(innerSource);
        return Element.empty('img')..attributes['src'] = 'generated.png';
      },
    );
    const prefix = '![outer][same] ![trigger] ![outer][same]\n\n[same]: ';
    const source = '${prefix}outer.png';
    final outer = _destinations(document.parse(source)).toList();
    expect(outer, hasLength(3));
    _expectRange(source, outer[0], prefix.length, 'outer.png');
    expect(outer[1].destinationRange, isNull);
    _expectRange(source, outer[2], prefix.length, 'outer.png');
    _expectRange(innerSource, _destinations(inner).single, 24, 'inner.png');
  });

  test('resolver-generated destinations have no source ranges', () {
    final document = Document(
      linkResolver: (label, [title]) =>
          Element.text('a', label)..attributes['href'] = 'external',
      imageLinkResolver: (label, [title]) =>
          Element.empty('img')..attributes['src'] = 'external',
    );
    final nodes = _destinations(document.parse('[missing] ![missing]'));
    expect(nodes, hasLength(2));
    expect(nodes.every((node) => node.destinationRange == null), isTrue);
  });

  test('custom block and inline syntaxes preserve mapped slices', () {
    const source = ':: ~![x](a) [ref]~\n\n[ref]: b';
    final nodes = _destinations(
      Document(
        blockSyntaxes: [const _MappedBlockSyntax()],
        inlineSyntaxes: [_MappedInlineSyntax()],
      ).parse(source),
    ).toList();
    _expectRange(source, nodes[0], 9, 'a');
    _expectRange(source, nodes[1], 27, 'b');
  });

  test('custom node creation receives required destination metadata', () {
    const source = '![](a)';
    final node = _destinations(
      Document(inlineSyntaxes: [_StyledImageSyntax()]).parse(source),
    ).single;
    _expectRange(source, node, 4, 'a');
    expect(node.attributes['class'], 'styled');
  });

  test(
    'unmapped extension input is rejected instead of given false offsets',
    () {
      final context = ParseContext(Document(), 'original input');
      expect(
        () => InlineParser(SourceText('![](generated)'), context),
        throwsArgumentError,
      );
      expect(
        () => BlockParser([Line(SourceText('generated'))], context),
        throwsArgumentError,
      );
    },
  );

  test('image destination edits preserve matching prose and code exactly', () {
    const source =
        'Prose old.png.\r\n\r\n'
        '![one](old.png) ![two](<old.png> "title")\r\n\r\n'
        '`![inline](old.png)`\r\n\r\n'
        '~~~\r\n![fenced](old.png)\r\n~~~\r\n\r\n'
        '![shared] ![shared][] [ordinary][shared]\r\n\r\n'
        '[shared]: old.png "shared title"\r\n';
    final images = _destinations(
      Document().parse(source),
    ).where((node) => node.tag == 'img').toList();
    expect(images, hasLength(4));
    final ranges = images.map((node) => node.destinationRange!).toSet().toList()
      ..sort((a, b) => b.start.compareTo(a.start));
    expect(ranges, hasLength(3));
    var edited = source;
    for (final range in ranges) {
      edited = edited.replaceRange(range.start, range.end, 'new.png');
    }
    expect(
      edited,
      'Prose old.png.\r\n\r\n'
      '![one](new.png) ![two](<new.png> "title")\r\n\r\n'
      '`![inline](old.png)`\r\n\r\n'
      '~~~\r\n![fenced](old.png)\r\n~~~\r\n\r\n'
      '![shared] ![shared][] [ordinary][shared]\r\n\r\n'
      '[shared]: new.png "shared title"\r\n',
    );
  });

  test('many mapped lines and destinations do not cause quadratic work', () {
    const count = 20000;
    final source = List.filled(count, '> [x](a)').join('\n');
    final watch = Stopwatch()..start();
    final nodes = _destinations(Document().parse(source)).toList();
    expect(nodes, hasLength(count));
    _expectRange(source, nodes.last, (count - 1) * 9 + 6, 'a');
    expect(watch.elapsedMilliseconds, lessThan(10000));
  });
}

// ---------- Assertions and traversal ----------

Iterable<Element> _destinations(List<Node> nodes) sync* {
  for (final node in nodes) {
    if (node is! Element) continue;
    if (node.tag == 'a' || node.tag == 'img') yield node;
    if (node.children != null) yield* _destinations(node.children!);
  }
}

void _expectRange(String source, Element node, int start, String raw) {
  final range = node.destinationRange;
  expect(range, SourceRange(start, start + raw.length));
  expect(source.substring(range!.start, range.end), raw);
}

// ---------- Source-aware extension examples ----------

class _MappedBlockSyntax extends BlockSyntax {
  const _MappedBlockSyntax();

  @override
  RegExp get pattern => RegExp('^:: ');

  @override
  Node parse(BlockParser parser) {
    final source = parser.current.source.slice(3);
    parser.advance();
    return Element('p', [UnparsedContent(source)]);
  }
}

class _MappedInlineSyntax extends InlineSyntax {
  _MappedInlineSyntax() : super('~([^~]+)~');

  @override
  bool onMatch(InlineParser parser, Match match) {
    final source = parser.sourceText.slice(match.start + 1, match.end - 1);
    final children = InlineParser(source, parser.context).parse();
    parser.addNode(Element('span', children));
    return true;
  }
}

class _StyledImageSyntax extends ImageSyntax {
  @override
  Element createNode(
    String destination,
    String? title,
    SourceRange range, {
    required List<Node> Function() getChildren,
  }) =>
      super.createNode(destination, title, range, getChildren: getChildren)
        ..attributes['class'] = 'styled';
}
