// Defines immutable destination offsets in the original Markdown string.
// Used by parser results and callers that extract or edit destinations.

// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A half-open range of UTF-16 code units in the original input.
final class SourceRange {
  final int start;
  final int end;

  const SourceRange(this.start, this.end)
    : assert(start >= 0),
      assert(end >= start);

  @override
  bool operator ==(Object other) =>
      other is SourceRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SourceRange($start, $end)';
}
