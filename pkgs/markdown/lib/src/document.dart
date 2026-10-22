// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'ast.dart';
import 'block_syntaxes/block_syntax.dart';
import 'extension_set.dart';
import 'inline_parser.dart';
import 'inline_syntaxes/inline_syntax.dart';
import 'parse_context.dart';
import 'source_range.dart';

/// Reusable configuration for independent Markdown parse invocations.
class Document {
  final LinkBuilder? linkBuilder;
  final LinkBuilder? imageLinkBuilder;
  final bool encodeHtml;

  /// Whether to use default block syntaxes.
  final bool withDefaultBlockSyntaxes;

  /// Whether to use default inline syntaxes.
  ///
  /// Need to set both [withDefaultInlineSyntaxes] and [encodeHtml] to
  /// `false` to disable all inline syntaxes including html encoding syntaxes.
  final bool withDefaultInlineSyntaxes;

  final _blockSyntaxes = <BlockSyntax>{};
  final _inlineSyntaxes = <InlineSyntax>{};
  final bool hasCustomInlineSyntaxes;

  Iterable<BlockSyntax> get blockSyntaxes => _blockSyntaxes;

  Iterable<InlineSyntax> get inlineSyntaxes => _inlineSyntaxes;

  Document({
    Iterable<BlockSyntax>? blockSyntaxes,
    Iterable<InlineSyntax>? inlineSyntaxes,
    ExtensionSet? extensionSet,
    Resolver? linkResolver,
    LinkBuilder? linkBuilder,
    Resolver? imageLinkResolver,
    LinkBuilder? imageLinkBuilder,
    this.encodeHtml = true,
    this.withDefaultBlockSyntaxes = true,
    this.withDefaultInlineSyntaxes = true,
  }) : linkBuilder = linkBuilder ?? linkBuilderFromResolver(linkResolver),
       imageLinkBuilder =
           imageLinkBuilder ?? linkBuilderFromResolver(imageLinkResolver),
       hasCustomInlineSyntaxes =
           (inlineSyntaxes?.isNotEmpty ?? false) ||
           (extensionSet?.inlineSyntaxes.isNotEmpty ?? false) {
    if (blockSyntaxes != null) {
      _blockSyntaxes.addAll(blockSyntaxes);
    }
    if (inlineSyntaxes != null) {
      _inlineSyntaxes.addAll(inlineSyntaxes);
    }

    if (extensionSet == null) {
      if (withDefaultBlockSyntaxes) {
        _blockSyntaxes.addAll(ExtensionSet.commonMark.blockSyntaxes);
      }

      if (withDefaultInlineSyntaxes) {
        _inlineSyntaxes.addAll(ExtensionSet.commonMark.inlineSyntaxes);
      }
    } else {
      _blockSyntaxes.addAll(extensionSet.blockSyntaxes);
      _inlineSyntaxes.addAll(extensionSet.inlineSyntaxes);
    }
  }

  Resolver? get linkResolver => linkResolverFromBuilder(linkBuilder);
  Resolver? get imageLinkResolver => linkResolverFromBuilder(imageLinkBuilder);

  /// Parses [text] with fresh references and footnote state for this input.
  List<Node> parse(String text) => ParseContext(this, text).parse();

  /// Parses inline Markdown with offsets relative to [text] and fresh state.
  List<Node> parseInline(String text) {
    final context = ParseContext(this, text);
    return InlineParser(context.source, context).parse();
  }
}

/// A [link reference
/// definition](https://spec.commonmark.org/0.30/#link-reference-definitions).
class LinkReference {
  /// The [link label](https://spec.commonmark.org/0.30/#link-label).

  final String label;

  /// The [link destination](https://spec.commonmark.org/0.30/#link-destination).
  final String destination;

  /// The [link title](https://spec.commonmark.org/0.30/#link-title).
  final String? title;

  /// The raw destination in this parse invocation's original input.
  final SourceRange destinationRange;

  /// Constructs a definition with its raw destination location.
  /// Use null for [title] when no title appears in the input.
  LinkReference(
    this.label,
    this.destination,
    this.title,
    this.destinationRange,
  );
}
