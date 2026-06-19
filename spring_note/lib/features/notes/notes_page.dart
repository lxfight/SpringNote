import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/local_data_state.dart';
import '../../core/models/note_file.dart';
import '../../core/services/ai_client_service.dart';
import '../../core/services/note_service.dart';
import '../../core/theme/app_theme.dart';
import 'markdown_preview.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.localDataState,
    this.noteService = const NoteService(),
    this.aiClientService = const AiClientService(),
  });

  final LocalDataState localDataState;
  final NoteService noteService;
  final AiClientService aiClientService;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _FimTextEditingController _editorController =
      _FimTextEditingController();
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _editorFocusNode;

  NoteKind _kind = NoteKind.daily;
  List<NoteFile> _notes = [];
  NoteFile? _selectedNote;
  bool _loading = true;
  bool _saving = false;
  bool _predicting = false;
  String _statusText = '正在加载';
  String _lastEditorText = '';
  TextSelection _lastEditorSelection = const TextSelection.collapsed(offset: 0);
  Timer? _fimDebounce;
  int _fimGeneration = 0;
  String? _fimPrediction;
  String? _fimMessage;
  bool _consumingFimPrediction = false;

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode(onKeyEvent: _handleEditorKeyEvent);
    _editorController.addListener(_handleEditorChanged);
    _searchController.addListener(() => setState(() {}));
    _loadNotes(kind: _kind);
  }

  @override
  void dispose() {
    _editorController
      ..removeListener(_handleEditorChanged)
      ..dispose();
    _editorFocusNode.dispose();
    _fimDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final logicalKey = event.logicalKey;
    final controlPressed = HardwareKeyboard.instance.isControlPressed;
    if (logicalKey == LogicalKeyboardKey.tab) {
      if (_fimPrediction == null) {
        _insertPlainText('\t');
      } else {
        _acceptFimPrediction(_FimAcceptMode.all);
      }
      return KeyEventResult.handled;
    }
    if (_fimPrediction == null) {
      return KeyEventResult.ignored;
    }
    if (controlPressed && logicalKey == LogicalKeyboardKey.keyL) {
      _acceptFimPrediction(_FimAcceptMode.line);
      return KeyEventResult.handled;
    }
    if (controlPressed && logicalKey == LogicalKeyboardKey.keyK) {
      _acceptFimPrediction(_FimAcceptMode.character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _loadNotes({
    required NoteKind kind,
    String? selectedPath,
  }) async {
    setState(() {
      _kind = kind;
      _loading = true;
      _statusText = '正在加载';
    });

    final directory = _directoryFor(kind);
    var notes = await widget.noteService.listMarkdownFiles(
      directoryPath: directory,
      kind: kind,
    );
    if (notes.isEmpty) {
      final current = await widget.noteService.ensureCurrentMarkdownFile(
        directoryPath: directory,
        kind: kind,
      );
      notes = [current];
    }

    final selected = selectedPath == null
        ? notes.first
        : notes.firstWhere(
            (note) => note.path == selectedPath,
            orElse: () => notes.first,
          );
    final content = await widget.noteService.readMarkdown(selected.path);

    if (!mounted) {
      return;
    }

    setState(() {
      _notes = notes;
      _selectedNote = selected;
      _setEditorText(content);
      _loading = false;
      _statusText = '已加载';
    });
  }

  Future<void> _selectNote(NoteFile note) async {
    setState(() {
      _selectedNote = note;
      _loading = true;
      _statusText = '正在加载';
    });

    final content = await widget.noteService.readMarkdown(note.path);
    if (!mounted) {
      return;
    }

    setState(() {
      _setEditorText(content);
      _loading = false;
      _statusText = '已加载';
    });
  }

  void _handleEditorChanged() {
    final selected = _selectedNote;
    if (_loading || selected == null) {
      return;
    }

    final text = _editorController.text;
    final selection = _editorController.selection;
    final textChanged = text != _lastEditorText;
    final selectionChanged = selection != _lastEditorSelection;

    _lastEditorText = text;
    _lastEditorSelection = selection;

    if (_consumingFimPrediction) {
      if (textChanged) {
        _saveEditorText(selected, text);
      }
      return;
    }

    if (textChanged || selectionChanged) {
      _invalidateFimPrediction(scheduleNext: true);
    }

    if (!textChanged) {
      return;
    }

    _saveEditorText(selected, text);
  }

  Future<void> _saveEditorText(NoteFile selected, String text) async {
    setState(() {
      _saving = true;
      _statusText = '保存中';
    });

    await widget.noteService.writeMarkdown(selected.path, text);
    final updatedNotes = await widget.noteService.listMarkdownFiles(
      directoryPath: _directoryFor(_kind),
      kind: _kind,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _notes = updatedNotes;
      _selectedNote = updatedNotes.firstWhere(
        (note) => note.path == selected.path,
        orElse: () => selected,
      );
      _saving = false;
      _statusText = '已保存';
    });
  }

  void _setEditorText(String value) {
    _editorController
      ..removeListener(_handleEditorChanged)
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length)
      ..addListener(_handleEditorChanged);
    _lastEditorText = value;
    _lastEditorSelection = _editorController.selection;
    _fimGeneration++;
    _fimDebounce?.cancel();
    _fimPrediction = null;
    _predicting = false;
    _fimMessage = null;
    _editorController.clearFimPrediction();
  }

  void _invalidateFimPrediction({required bool scheduleNext}) {
    _fimGeneration++;
    _fimDebounce?.cancel();

    if (_fimPrediction != null || _predicting) {
      setState(() {
        _fimPrediction = null;
        _predicting = false;
        _fimMessage = null;
        _editorController.clearFimPrediction();
      });
    }

    if (!scheduleNext || _selectedNote == null || _loading) {
      return;
    }

    final generation = _fimGeneration;
    final text = _editorController.text;
    final selection = _editorController.selection;

    if (!selection.isValid || !selection.isCollapsed) {
      return;
    }

    final unavailableReason = widget.aiClientService.fimUnavailableReason(
      widget.localDataState.config,
    );
    if (unavailableReason != null) {
      setState(() => _fimMessage = 'FIM 未触发：$unavailableReason');
      return;
    }

    if (_fimMessage != null) {
      setState(() => _fimMessage = null);
    }

    _fimDebounce = Timer(const Duration(milliseconds: 300), () {
      _requestFimPrediction(
        generation: generation,
        text: text,
        selection: selection,
      );
    });
  }

  Future<void> _requestFimPrediction({
    required int generation,
    required String text,
    required TextSelection selection,
  }) async {
    if (!mounted ||
        generation != _fimGeneration ||
        text != _editorController.text ||
        selection != _editorController.selection) {
      return;
    }

    setState(() => _predicting = true);
    final offset = selection.baseOffset;
    String? prediction;
    try {
      prediction = await widget.aiClientService.fimCompleteMarkdown(
        appDataDir: widget.localDataState.dataDirectory,
        config: widget.localDataState.config,
        prompt: text.substring(0, offset),
        suffix: text.substring(offset),
      );
    } catch (_) {
      prediction = null;
    }

    if (!mounted ||
        generation != _fimGeneration ||
        text != _editorController.text ||
        selection != _editorController.selection) {
      return;
    }

    setState(() {
      _predicting = false;
      if (prediction?.isEmpty ?? true) {
        _fimPrediction = null;
        _fimMessage = 'FIM 已请求，但没有返回可用预测';
      } else {
        _fimPrediction = prediction;
        _fimMessage = null;
        _editorController.setFimPrediction(
          prediction!,
          offset: selection.baseOffset,
        );
      }
    });
  }

  void _acceptFimPrediction(_FimAcceptMode mode) {
    final prediction = _fimPrediction;
    final selection = _editorController.selection;
    if (prediction == null || prediction.isEmpty || !selection.isValid) {
      return;
    }

    final accepted = switch (mode) {
      _FimAcceptMode.all => prediction,
      _FimAcceptMode.line => _firstPredictionLine(prediction),
      _FimAcceptMode.character => prediction.characters.first,
    };
    final remaining = prediction.substring(accepted.length);

    final text = _editorController.text;
    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, accepted);
    final nextOffset = start + accepted.length;
    _consumingFimPrediction = true;
    _editorController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    _consumingFimPrediction = false;

    setState(() {
      if (remaining.isEmpty) {
        _fimPrediction = null;
        _editorController.clearFimPrediction();
      } else {
        _fimPrediction = remaining;
        _editorController.setFimPrediction(remaining, offset: nextOffset);
      }
      _fimMessage = null;
    });
  }

  void _insertPlainText(String value) {
    final selection = _editorController.selection;
    if (!selection.isValid) {
      return;
    }

    final text = _editorController.text;
    final start = selection.start;
    final end = selection.end;
    final nextText = text.replaceRange(start, end, value);
    final nextOffset = start + value.length;
    _editorController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  String _firstPredictionLine(String prediction) {
    final newlineIndex = prediction.indexOf('\n');
    if (newlineIndex == -1) {
      return prediction;
    }
    return prediction.substring(0, newlineIndex + 1);
  }

  String _directoryFor(NoteKind kind) {
    return switch (kind) {
      NoteKind.daily => widget.localDataState.dailyNotesDirectory,
      NoteKind.weekly => widget.localDataState.weeklyNotesDirectory,
      NoteKind.monthly => widget.localDataState.monthlyNotesDirectory,
    };
  }

  List<NoteFile> get _filteredNotes {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _notes;
    }
    return _notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(query) ||
              note.name.toLowerCase().contains(query) ||
              note.preview.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedNote;

    return Material(
      color: AppTheme.background,
      child: Row(
        children: [
          _NotesSidebar(
            kind: _kind,
            notes: _filteredNotes,
            selectedPath: selected?.path,
            searchController: _searchController,
            onKindChanged: (kind) => _loadNotes(kind: kind),
            onNoteSelected: _selectNote,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 10, 24),
              child: _EditorPane(
                controller: _editorController,
                focusNode: _editorFocusNode,
                statusText: _editorStatusText,
                enabled: selected != null && !_loading,
                predicting: _predicting,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 24, 24, 24),
              child: _PreviewPane(markdown: _editorController.text),
            ),
          ),
        ],
      ),
    );
  }

  String get _editorStatusText {
    if (_saving) {
      return '保存中';
    }
    if (_predicting) {
      return '补全预测中';
    }
    if (_fimPrediction != null) {
      return 'Tab 全部 · Ctrl+L 单行 · Ctrl+K 单字';
    }
    if (_fimMessage != null) {
      return _fimMessage!;
    }
    return _statusText;
  }
}

enum _FimAcceptMode { all, line, character }

class _FimTextEditingController extends TextEditingController {
  String? _fimPrediction;
  int? _fimOffset;

  void setFimPrediction(String prediction, {required int offset}) {
    final normalizedOffset = offset.clamp(0, text.length);
    if (_fimPrediction == prediction && _fimOffset == normalizedOffset) {
      return;
    }
    _fimPrediction = prediction;
    _fimOffset = normalizedOffset;
    notifyListeners();
  }

  void clearFimPrediction() {
    if (_fimPrediction == null && _fimOffset == null) {
      return;
    }
    _fimPrediction = null;
    _fimOffset = null;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final prediction = _fimPrediction;
    final offset = _fimOffset;
    if (prediction == null ||
        prediction.isEmpty ||
        offset == null ||
        offset < 0 ||
        offset > text.length) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final effectiveStyle = style ?? const TextStyle();
    return TextSpan(
      style: effectiveStyle,
      children: [
        TextSpan(text: text.substring(0, offset)),
        TextSpan(
          text: prediction,
          style: effectiveStyle.copyWith(color: const Color(0xFF94A3B8)),
        ),
        TextSpan(text: text.substring(offset)),
      ],
    );
  }
}

class _NotesSidebar extends StatelessWidget {
  const _NotesSidebar({
    required this.kind,
    required this.notes,
    required this.selectedPath,
    required this.searchController,
    required this.onKindChanged,
    required this.onNoteSelected,
  });

  final NoteKind kind;
  final List<NoteFile> notes;
  final String? selectedPath;
  final TextEditingController searchController;
  final ValueChanged<NoteKind> onKindChanged;
  final ValueChanged<NoteFile> onNoteSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 278,
      padding: const EdgeInsets.fromLTRB(18, 24, 14, 20),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(right: BorderSide(color: Color(0xFFEEF2F7))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('笔记本', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  kind.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Spacer(),
              PopupMenuButton<NoteKind>(
                tooltip: '切换日报/周报/月报',
                icon: const Icon(Icons.more_horiz_rounded, size: 19),
                onSelected: onKindChanged,
                itemBuilder: (context) => [
                  for (final item in NoteKind.values)
                    PopupMenuItem(value: item, child: Text(item.label)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              hintText: '搜索知识记录...',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Text(
                      '没有匹配的便签',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return _NoteListItem(
                        note: note,
                        selected: note.path == selectedPath,
                        onTap: () => onNoteSelected(note),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoteListItem extends StatefulWidget {
  const _NoteListItem({
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final NoteFile note;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NoteListItem> createState() => _NoteListItemState();
}

class _NoteListItemState extends State<_NoteListItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final background = widget.selected
        ? const Color(0xFFF1F5F9).withValues(alpha: 0.8)
        : _hovering
        ? const Color(0xFFF1F5F9).withValues(alpha: 0.6)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatModified(widget.note.modifiedAt),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSubtle,
                      fontSize: 11,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                widget.note.preview.isEmpty
                    ? widget.note.name
                    : widget.note.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: widget.selected
                      ? AppTheme.textMuted
                      : AppTheme.textSubtle,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatModified(DateTime value) {
    final now = DateTime.now();
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.controller,
    required this.focusNode,
    required this.statusText,
    required this.enabled,
    required this.predicting,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String statusText;
  final bool enabled;
  final bool predicting;

  @override
  Widget build(BuildContext context) {
    const editorStyle = TextStyle(
      color: AppTheme.text,
      fontFamily: 'Consolas',
      fontSize: 14,
      height: 1.75,
    );
    return _PaneFrame(
      header: Row(
        children: [
          const Icon(Icons.code_rounded, size: 16, color: AppTheme.textSubtle),
          const SizedBox(width: 8),
          Text(
            'Markdown Source · 源码编辑',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              statusText,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              expands: true,
              maxLines: null,
              minLines: null,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: '# 开始编辑 Markdown...',
                filled: true,
                fillColor: Colors.white,
                hoverColor: Colors.white,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.fromLTRB(26, 24, 26, 24),
              ),
              style: editorStyle,
            ),
          ),
          if (predicting)
            const Positioned(
              right: 22,
              bottom: 18,
              child: _FimPredictingChip(),
            ),
        ],
      ),
    );
  }
}

class _FimPredictingChip extends StatelessWidget {
  const _FimPredictingChip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC).withValues(alpha: 0.92),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(width: 7),
            Text(
              '补全预测中',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    return _PaneFrame(
      header: Row(
        children: [
          Text(
            'Markdown Preview · 渲染预览',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSubtle,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.open_in_full_rounded,
            size: 15,
            color: AppTheme.textSubtle,
          ),
        ],
      ),
      child: MarkdownPreview(markdown: markdown),
    );
  }
}

class _PaneFrame extends StatelessWidget {
  const _PaneFrame({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEEF2F7)),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: [
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: header,
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
