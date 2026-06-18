import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/theme/app_theme.dart';

class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    if (markdown.trim().isEmpty) {
      return Center(
        child: Text(
          '预览区域会随着 Markdown 源码实时刷新',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(34, 30, 34, 48),
        child: DefaultTextStyle.merge(
          style: textTheme.bodyLarge?.copyWith(
            color: AppTheme.text,
            height: 1.68,
          ),
          child: GptMarkdown(
            markdown,
            followLinkColor: true,
            useDollarSignsForLatex: true,
            style: textTheme.bodyLarge?.copyWith(
              color: AppTheme.text,
              height: 1.68,
            ),
            onLinkTap: (url, title) {},
          ),
        ),
      ),
    );
  }
}
