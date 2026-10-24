// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:markdown/markdown.dart';
import 'package:test/test.dart';

void main() {
  for (final encodeHtml in [true, false]) {
    test(
      'escapes image descriptions at HTML output, encodeHtml: $encodeHtml',
      () {
        const source = '![<b x=" onerror=alert(1) y=">](bad)';
        final nodes = Document(
          encodeHtml: encodeHtml,
          inlineSyntaxes: [InlineHtmlSyntax()],
        ).parse(source);
        expect(
          renderToHtml(nodes),
          '<p><img src="bad" alt="&lt;b x=&quot; onerror=alert(1) y=&quot;&gt;" /></p>',
        );
      },
    );
  }

  test('preserves encoded ampersands in image descriptions', () {
    expect(
      markdownToHtml('![a & " b](bad)'),
      '<p><img src="bad" alt="a &amp; &quot; b" /></p>\n',
    );
    expect(
      markdownToHtml('![&amp;amp;](bad)'),
      '<p><img src="bad" alt="&amp;amp;" /></p>\n',
    );
  });

  group('markdownToHtml', () {
    const text = '# Hello **Markdown<em>!</em>**\n***';

    test('with no syntaxes', () {
      final result = markdownToHtml(
        text,
        withDefaultBlockSyntaxes: false,
        withDefaultInlineSyntaxes: false,
        encodeHtml: false,
      );
      expect(result, equals('# Hello **Markdown<em>!</em>**\n***\n'));
    });

    test('with no default syntaxes but with custom syntaxes', () {
      final result = markdownToHtml(
        text,
        withDefaultBlockSyntaxes: false,
        withDefaultInlineSyntaxes: false,
        encodeHtml: false,
        blockSyntaxes: [const HorizontalRuleSyntax()],
        inlineSyntaxes: [EmphasisSyntax.asterisk()],
      );

      expect(
        result,
        equals('# Hello <strong>Markdown<em>!</em></strong>\n<hr />\n'),
      );
    });

    test('with only default block syntaxes', () {
      final result = markdownToHtml(
        text,
        withDefaultInlineSyntaxes: false,
        encodeHtml: false,
      );

      expect(result, equals('<h1>Hello **Markdown<em>!</em>**</h1>\n<hr />\n'));
    });

    test('with only default inline syntaxes', () {
      final result = markdownToHtml(
        text,
        withDefaultBlockSyntaxes: false,
        encodeHtml: false,
      );

      expect(
        result,
        equals('# Hello <strong>Markdown<em>!</em></strong>\n***\n'),
      );
    });

    test('with no default syntaxes but with encodeHtml enabled', () {
      final result = markdownToHtml(
        text,
        withDefaultBlockSyntaxes: false,
        withDefaultInlineSyntaxes: false,
      );

      expect(
        result,
        equals('# Hello **Markdown&lt;em&gt;!&lt;/em&gt;**\n***\n'),
      );
    });
  });

  group('test InlineSyntax caseSensitive parameter', () {
    const text = 'one BREAK two';

    test('with caseSensitive enabled', () {
      final result = markdownToHtml(
        text,
        inlineOnly: true,
        inlineSyntaxes: [_BreakSyntax(true)],
      );

      expect(result, equals('one BREAK two'));
    });

    test('with caseSensitive disabled', () {
      final result = markdownToHtml(
        text,
        inlineOnly: true,
        inlineSyntaxes: [_BreakSyntax(false)],
      );

      expect(result, equals('one <break /> two'));
    });
  });
}

class _BreakSyntax extends InlineSyntax {
  _BreakSyntax(bool caseSensitive)
    : super('break', caseSensitive: caseSensitive);

  @override
  bool onMatch(InlineParser parser, Match match) {
    parser.addNode(Element.empty('break'));
    return true;
  }
}
