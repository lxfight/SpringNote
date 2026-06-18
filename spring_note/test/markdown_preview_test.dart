import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/notes/markdown_preview.dart';

void main() {
  testWidgets('markdown preview renders strong emphasis', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: MarkdownPreview(markdown: '这里要强调 **SQL 注入** 风险。'),
        ),
      ),
    );

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    final plainText = richTexts
        .map((richText) => richText.text.toPlainText())
        .join('\n');

    expect(plainText, contains('SQL 注入'));
    expect(plainText, isNot(contains('**SQL 注入**')));
    expect(_hasBoldText(richTexts, 'SQL 注入'), isTrue);
  });
}

bool _hasBoldText(Iterable<RichText> richTexts, String text) {
  for (final richText in richTexts) {
    if (_spanHasBoldText(richText.text, text, null)) {
      return true;
    }
  }
  return false;
}

bool _spanHasBoldText(InlineSpan span, String text, TextStyle? inheritedStyle) {
  final style = inheritedStyle?.merge(span.style) ?? span.style;

  if (span is TextSpan) {
    if ((span.text ?? '').contains(text) &&
        style?.fontWeight == FontWeight.w700) {
      return true;
    }

    final children = span.children;
    if (children != null) {
      for (final child in children) {
        if (_spanHasBoldText(child, text, style)) {
          return true;
        }
      }
    }
  }

  return false;
}
