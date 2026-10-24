// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:markdown/markdown.dart';
import 'package:test/test.dart';

void main() {
  group('Document', () {
    test('encodeHtml prevents less than and ampersand escaping', () {
      final document = Document(encodeHtml: false);
      final result = document.parseInline('< &');
      expect(result, hasLength(1));
      expect(
        result[0],
        const TypeMatcher<Text>().having((e) => e.text, 'text', equals('< &')),
      );
    });

    test('reentrant quote parsing keeps lazy continuation state local', () {
      late Document document;
      document = Document(
        blockSyntaxes: [
          _ReentrantBlockSyntax(() => document.parse('> nested')),
        ],
      );
      final nodes = document.parse('> first\ncontinued\n===\n---');
      final quote = nodes.first as Element;
      final paragraph = quote.children!.single as Element;
      expect(paragraph.tag, 'p');
      expect(paragraph.textContent, 'first\ncontinued\n===');
    });

    group('with encodeHtml enabled', () {
      final document = Document();

      test('encodes HTML in an inline code snippet', () {
        final result = document.parseInline(
          '``<p>Hello <em>Markdown</em></p>``',
        );
        final codeSnippet = result.single as Element;
        expect(
          codeSnippet.textContent,
          equals('&lt;p&gt;Hello &lt;em&gt;Markdown&lt;/em&gt;&lt;/p&gt;'),
        );
      });

      test('encodes HTML in a fenced code block', () {
        const lines = '```\n<p>Hello <em>Markdown</em></p>\n```\n';
        final result = document.parse(lines);
        final codeBlock = result.single as Element;
        expect(
          codeBlock.textContent,
          equals('&lt;p&gt;Hello &lt;em&gt;Markdown&lt;/em&gt;&lt;/p&gt;\n'),
        );
      });

      test('encodes HTML in an indented code block', () {
        const lines = '    <p>Hello <em>Markdown</em></p>\n';
        final result = document.parse(lines);
        final codeBlock = result.single as Element;
        expect(
          codeBlock.textContent,
          equals('&lt;p&gt;Hello &lt;em&gt;Markdown&lt;/em&gt;&lt;/p&gt;\n'),
        );
      });

      test('encodeHtml spaces are preserved in text', () {
        // Example to get a <p> tag rendered before a text node.
        const contents = 'Sample\n\n<pre>\n A\n B\n</pre>';
        final document = Document();
        final context = ParseContext(document, contents);
        final nodes = BlockParser(
          context.source.splitLines().map(Line.new).toList(),
          context,
        ).parseLines();
        final result = HtmlRenderer().render(nodes);
        expect(result, '<p>\n</p>\n<pre>\n A\n B\n</pre>');
      });

      test(
        'encode double quotes, greater than, and less than when escaped',
        () {
          const contents = r'\>\"\< Hello';
          final document = Document();
          final nodes = document.parseInline(contents);
          expect(nodes, hasLength(1));
          expect(
            nodes.single,
            const TypeMatcher<Text>().having(
              (e) => e.text,
              'text',
              '&gt;&quot;&lt; Hello',
            ),
          );
        },
      );
    });

    group('with encodeHtml disabled', () {
      final document = Document(encodeHtml: false);

      test(
        'keeps image descriptions plain without decoding entities twice',
        () {
          const description = '''Alice's "logo" &quot;''';
          for (final source in [
            '''![Alice's "logo" &amp;quot;](image.png)''',
            '''![Alice's "logo" &amp;quot;][image]\n\n[image]: image.png''',
            '''![![Alice's "logo" &amp;quot;](inner.png)](image.png)''',
          ]) {
            final paragraph = document.parse(source).single as Element;
            final image = paragraph.children!.single as Element;
            expect(image.attributes['alt'], description, reason: source);
          }
        },
      );

      test('leaves HTML alone, in a code snippet', () {
        final result = document.parseInline(
          '```<p>Hello <em>Markdown</em></p>```',
        );
        final codeSnippet = result.single as Element;
        expect(
          codeSnippet.textContent,
          equals('<p>Hello <em>Markdown</em></p>'),
        );
      });

      test('leaves HTML alone, in a fenced code block', () {
        const lines = '```\n<p>Hello <em>Markdown</em></p>\n```\n';
        final result = document.parse(lines);
        final codeBlock = result.single as Element;
        expect(
          codeBlock.textContent,
          equals('<p>Hello <em>Markdown</em></p>\n'),
        );
      });

      test('leaves HTML alone, in an indented code block', () {
        const lines = '    <p>Hello <em>Markdown</em></p>\n';
        final result = document.parse(lines);
        final codeBlock = result.single as Element;
        expect(
          codeBlock.textContent,
          equals('<p>Hello <em>Markdown</em></p>\n'),
        );
      });

      test('leave double quotes, greater than, and less than when escaped', () {
        const contents = r'\>\"\< Hello';
        final document = Document(encodeHtml: false);
        final nodes = document.parseInline(contents);
        expect(nodes, hasLength(1));
        expect(
          nodes.single,
          const TypeMatcher<Text>().having((e) => e.text, 'text', '>"< Hello'),
        );
      });
    });
  });
}

class _ReentrantBlockSyntax extends BlockSyntax {
  final void Function() callback;

  _ReentrantBlockSyntax(this.callback);

  @override
  RegExp get pattern => RegExp('never matches');

  @override
  bool canParse(BlockParser parser) {
    if (parser.current.content == '---') callback();
    return false;
  }

  @override
  Node? parse(BlockParser parser) => null;
}
