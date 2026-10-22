// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast.dart';
import '../block_parser.dart';
import '../link_parser.dart';
import '../patterns.dart';
import 'block_syntax.dart';

class LinkReferenceDefinitionSyntax extends BlockSyntax {
  @override
  RegExp get pattern => linkReferenceDefinitionPattern;

  @override
  bool canEndBlock(BlockParser parser) => false;

  const LinkReferenceDefinitionSyntax();

  @override
  Node? parse(BlockParser parser) {
    final definition = LinkParser(parser).parseDefinition();
    if (definition != null) {
      parser.context.linkReferences.putIfAbsent(
        definition.label,
        () => definition,
      );
    }

    return null;
  }
}
