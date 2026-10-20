import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/autotag.dart';
import '../../core/library_folders.dart';
import '../../core/models.dart';

/// Per-person / inbox categories, not content folders — mirrors EXCLUDED_FOLDER_CATEGORIES.
const _personCategories = {'Onlyfans Girls', 'Onlyfans Boys', 'Pornstars', 'Aktor', 'Stash'};

/// Groups the tagger never predicts — mirrors EXCLUDED_KEYS in autotag/config.py.
const _manualKeys = {'Model'};

class AutotagScreen extends StatefulWidget {
  const AutotagScreen({super.key});

  @override
  State<AutotagScreen> createState() => _AutotagScreenState();
}

class _AutotagScreenState extends State<AutotagScreen> {
  late final AutotagService _svc;
  AutotagPredictions? _preds;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc = AutotagService(context.read<AppState>());
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final preds = await _svc.loadPredictions();
    if (mounted) setState(() { _preds = preds; _loading = false; });
    await _svc.refreshNeedsReview(preds);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.play_circle_outline), text: 'Run'),
              Tab(icon: ReviewMarker(child: Icon(Icons.fact_check_outlined)), text: 'Review'),
              Tab(icon: Icon(Icons.school_outlined), text: 'Training files'),
              Tab(icon: Icon(Icons.rule), text: 'Rules'),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _RunTab(svc: _svc, preds: _preds, onPredictionsChanged: _reload),
                      _ReviewTab(svc: _svc, preds: _preds, onPredictionsChanged: _reload),
                      _TrainingTab(svc: _svc),
                      _RulesTab(svc: _svc),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Run tab: analyze/retrain, apply confident tags, reliability table
// ─────────────────────────────────────────────────────────────────────────────

class _RunTab extends StatefulWidget {
  final AutotagService svc;
  final AutotagPredictions? preds;
  final Future<void> Function() onPredictionsChanged;

  const _RunTab({required this.svc, required this.preds, required this.onPredictionsChanged});

  @override
  State<_RunTab> createState() => _RunTabState();
}

class _RunTabState extends State<_RunTab> with AutomaticKeepAliveClientMixin {
  final List<String> _log = [];
  final _logScroll = ScrollController();
  String? _stage;
  double? _progress;
  bool _running = false;
  bool _applying = false;
  bool _moveFolders = true;
  bool _autoApply = true;          // after Analyze, apply confident tags to the inbox
  bool _wholeLibrary = false;      // apply scope: inbox only, or fill gaps everywhere
  List<MediaItem> _inbox = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInbox();
  }

  Future<void> _loadInbox() async {
    final app = context.read<AppState>();
    final stash = app.stashCategoryId;
    final list = <MediaItem>[];
    if (stash != null) {
      for (final s in app.subcategoriesFor(stash)) {
        list.addAll(await app.items!.listItemsInSubcategory(s.id));
      }
    }
    if (mounted) setState(() => _inbox = list);
  }

  Future<void> _run(String command) async {
    setState(() { _running = true; _log.clear(); _stage = 'starting'; _progress = null; });
    int? exitCode;
    await for (final e in widget.svc.run(command)) {
      if (!mounted) return;
      setState(() {
        if (e.line != null) {
          _log.add(e.line!);
          if (_log.length > 400) _log.removeAt(0);
        }
        if (e.stage != null) {
          _stage = switch (e.stage) {
            'embed' => 'Analyzing files (1/2) ${e.done}/${e.total}',
            'embed2' => 'Analyzing files in detail (2/2) ${e.done}/${e.total}',
            'sheets' => 'Building previews ${e.done}/${e.total}',
            'train' => 'Learning tags ${e.done}/${e.total}',
            _ => '${e.stage} ${e.done}/${e.total}',
          };
          _progress = e.total == 0 ? null : e.done / e.total;
        }
        if (e.exitCode != null) exitCode = e.exitCode;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      });
    }
    if (!mounted) return;
    setState(() { _running = false; _stage = exitCode == 0 ? 'Done' : 'Failed (exit code $exitCode)'; _progress = null; });
    if (exitCode == 0) {
      await widget.onPredictionsChanged();
      if (command == 'run' && _autoApply && _inbox.isNotEmpty && mounted) {
        await _apply(inboxOnly: true);
      }
    }
  }

  Future<void> _apply({bool inboxOnly = false}) async {
    final app = context.read<AppState>();
    final preds = widget.preds ?? await widget.svc.loadPredictions();
    if (preds == null || !mounted) return;
    setState(() => _applying = true);
    // whole library: every analyzed file; only empty tags/groups are filled, nothing is
    // overwritten, and only inbox files are ever moved
    final items = inboxOnly || !_wholeLibrary
        ? _inbox
        : await app.items!.listItemsByIds(preds.items.keys.toList());
    final res = await widget.svc.applyConfident(preds, items, moveFolders: _moveFolders);
    await _loadInbox();
    if (!mounted) return;
    setState(() => _applying = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Tagged ${res.files} files (${res.tags} tags, ${res.groups} groups), '
            'moved ${res.moved} to folders.')));
  }

  Future<void> _pickTaggerFolder() async {
    final app = context.read<AppState>();
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select the Lewdex (tagger) folder');
    if (dir == null) return;
    await app.updateSettings(app.settings.copyWith(taggerPath: dir));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final preds = widget.preds;
    final tagger = widget.svc.findTagger();
    final python = tagger == null ? null : AutotagService.pythonFor(tagger);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Lewdex', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Drop new files into the inbox (Stash), analyze, then apply the confident tags. '
            'Everything the model is unsure about goes to Review.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(python != null ? Icons.check_circle : Icons.error_outline,
                color: python != null ? Colors.green : theme.colorScheme.error),
            title: const Text('Tagger'),
            subtitle: Text(tagger == null
                ? 'Not found. Put it in a "Tagger" folder next to the app or the Library, or choose it.'
                : python == null
                    ? '$tagger\nNo Python environment inside (.venv or python folder).'
                    : tagger),
            trailing: OutlinedButton(onPressed: _pickTaggerFolder, child: const Text('Choose…')),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preds == null
                    ? 'No analysis yet.'
                    : 'Last analysis: ${_fmtDate(preds.generatedAt)} · ${preds.items.length} files'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _running || python == null ? null : () => _run('run'),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Analyze new files & retrain'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _running || python == null || preds == null ? null : () => _run('predict'),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retrain only'),
                  ),
                  if (_running)
                    TextButton.icon(
                      onPressed: widget.svc.cancel,
                      icon: const Icon(Icons.stop),
                      label: const Text('Cancel'),
                    ),
                ]),
                if (_stage != null) ...[
                  const SizedBox(height: 12),
                  Text(_stage!),
                  if (_running) ...[const SizedBox(height: 6), LinearProgressIndicator(value: _progress)],
                ],
                if (_log.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    height: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListView(
                      controller: _logScroll,
                      children: [
                        for (final l in _log)
                          Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Apply confident tags', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Only predictions the model is confident about are applied; the rest goes to Review. '
                    'Your own tags are never changed.',
                    style: TextStyle(color: theme.hintColor)),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text('Inbox (${_inbox.length})'), icon: const Icon(Icons.inbox)),
                    ButtonSegment(
                        value: true,
                        label: Text('Whole library${preds == null ? '' : ' (${preds.items.length})'}'),
                        icon: const Icon(Icons.video_library)),
                  ],
                  selected: {_wholeLibrary},
                  onSelectionChanged: (s) => setState(() => _wholeLibrary = s.first),
                ),
                const SizedBox(height: 4),
                Text(_wholeLibrary
                    ? 'Fills in missing tags on every file. Sorted files stay where they are.'
                    : 'New files in Stash: tags them and moves them to their folder.',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _moveFolders,
                  onChanged: (v) => setState(() => _moveFolders = v ?? true),
                  title: const Text('Move inbox files to their predicted folder'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoApply,
                  onChanged: (v) => setState(() => _autoApply = v ?? true),
                  title: const Text('Do this automatically for the inbox after "Analyze new files"'),
                ),
                FilledButton.icon(
                  onPressed: preds == null || _applying || _running || (!_wholeLibrary && _inbox.isEmpty)
                      ? null
                      : _apply,
                  icon: _applying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.done_all),
                  label: Text(_wholeLibrary ? 'Fill in missing tags (whole library)' : 'Apply to inbox (${_inbox.length} files)'),
                ),
              ],
            ),
          ),
        ),
        if (preds != null) _ReliabilityCard(preds: preds),
      ],
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// "74% (71% ↑)": current score with the previous retrain's score and a coloured arrow.
class _QualityTrend extends StatelessWidget {
  final double now;
  final double? before;
  const _QualityTrend({required this.now, required this.before});

  @override
  Widget build(BuildContext context) {
    final nowPct = (now * 100).round();
    final beforePct = before == null ? null : (before! * 100).round();
    final hint = Theme.of(context).hintColor;
    return Row(children: [
      Text('$nowPct%'),
      if (beforePct != null) ...[
        const SizedBox(width: 6),
        Text('($beforePct%', style: TextStyle(color: hint, fontSize: 12)),
        if (nowPct != beforePct)
          Icon(nowPct > beforePct ? Icons.arrow_upward : Icons.arrow_downward,
              size: 13, color: nowPct > beforePct ? Colors.green : Colors.redAccent),
        Text(')', style: TextStyle(color: hint, fontSize: 12)),
      ],
    ]);
  }
}

class _ReliabilityCard extends StatelessWidget {
  final AutotagPredictions preds;
  const _ReliabilityCard({required this.preds});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = preds.labels.values.toList()
      ..sort((a, b) => a.kind != b.kind ? b.kind.index.compareTo(a.kind.index) : b.quality.compareTo(a.quality));
    return Card(
      child: ExpansionTile(
        title: const Text('How reliable is each tag?'),
        subtitle: Text('Tested on your own tagged files. "Auto" = confident enough to apply without asking.',
            style: TextStyle(color: theme.hintColor)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(3), 3: FlexColumnWidth(1)},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                const TableRow(children: [
                  Text('Tag', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Examples', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Quality', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Auto', style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
                for (final l in labels)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(l.name)),
                    Text('${l.examples}'),
                    Row(children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: l.quality,
                          color: l.quality >= 0.8 ? Colors.green : l.quality >= 0.55 ? Colors.amber : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(width: 110, child: _QualityTrend(now: l.quality, before: preds.previousQuality[l.id])),
                    ]),
                    Icon(l.autoThreshold != null ? Icons.check : Icons.remove, size: 16,
                        color: l.autoThreshold != null ? Colors.green : theme.hintColor),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Review tab: answer the files the model is least sure about, one batch at a time
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewTab extends StatefulWidget {
  final AutotagService svc;
  final AutotagPredictions? preds;
  final Future<void> Function() onPredictionsChanged;

  const _ReviewTab({required this.svc, required this.preds, required this.onPredictionsChanged});

  @override
  State<_ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends State<_ReviewTab> with AutomaticKeepAliveClientMixin {
  final Set<String> _selected = {};
  List<String>? _queue;      // item ids, null = not started
  /// "Needs review" mode: item id -> the only labels to ask for that item
  Map<String, List<String>>? _restrict;
  /// Where the current file is, and where it should be (preselected; Save moves it if different)
  String? _currentFolder;
  String? _folderChoice;
  /// Tags Lewdex didn't ask about that the user adds by hand ("+ Add tag…")
  final Set<String> _extraTags = {};
  int _pos = 0;
  int _answered = 0;
  bool _retraining = false;

  // current item
  MediaItem? _item;
  ItemLabelState? _state;
  List<AutotagLabelInfo> _pending = [];
  final Map<String, Object?> _answers = {};   // label id -> bool / String / null(not visible)

  static const _skip = '__skip__';

  @override
  bool get wantKeepAlive => true;

  AutotagPredictions get preds => widget.preds!;

  Map<String, List<String>> _presets(AppState app) {
    final tagLabelsByGroup = <String, List<String>>{};
    final groupNames = {for (final g in app.tagGroupList) g.id: g.name};
    for (final t in app.tagList) {
      final id = tagLabel(t.name);
      if (!preds.labels.containsKey(id)) continue;
      tagLabelsByGroup.putIfAbsent(groupNames[t.groupId] ?? 'Other', () => []).add(id);
    }
    bool has(String id) => preds.labels.containsKey(id);
    return {
      'Basics': ['kv:Genre', 'kv:Scene Type', 'kv:Ethnicity', 'kv:Allure'].where(has).toList(),
      'Body': ['kv:Body Type', 'kv:Tits size', 'kv:Ass size'].where(has).toList(),
      for (final e in tagLabelsByGroup.entries) e.key: e.value,
      if (has('folder')) 'Folder': ['folder'],
    }..removeWhere((_, v) => v.isEmpty);
  }

  void _startNeedsReview() {
    _restrict = preds.attention;
    _selected
      ..clear()
      ..addAll(preds.attention.values.expand((l) => l));
    setState(() { _queue = preds.attention.keys.toList(); _pos = 0; _answered = 0; });
    _loadCurrent();
  }

  void _start() {
    _restrict = null;
    // round-robin merge of each label's "hardest first" list
    final lists = [for (final id in _selected) preds.review[id] ?? const <String>[]];
    final seen = <String>{};
    final queue = <String>[];
    for (var i = 0; lists.any((l) => i < l.length); i++) {
      for (final l in lists) {
        if (i < l.length && seen.add(l[i])) queue.add(l[i]);
      }
    }
    setState(() { _queue = queue; _pos = 0; _answered = 0; });
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final app = context.read<AppState>();
    while (_queue != null && _pos < _queue!.length) {
      final id = _queue![_pos];
      final items = await app.items!.listItemsByIds([id]);
      final pred = preds.items[id];
      if (items.isEmpty || pred == null) { _pos++; continue; }
      final state = await widget.svc.stateFor(id);
      final pending = [
        for (final lid in _restrict?[id] ?? _selected)
          if (preds.labels[lid] case final info?)
            if (!widget.svc.isKnown(preds, info, state, items.first)) info,
      ];
      if (pending.isEmpty) { _pos++; continue; }
      _answers
        ..clear()
        ..addAll({for (final info in pending) info.id: _guess(info, pred)});
      if (!mounted) return;
      final current = _folderOf(app, items.first.subcategoryId);
      final inStash = app.stashCategoryId != null &&
          app.subcategoriesFor(app.stashCategoryId!).any((sub) => sub.id == items.first.subcategoryId);
      setState(() {
        _item = items.first;
        _state = state;
        _pending = pending;
        _currentFolder = current;
        // inbox files: the model's folder is preselected, so Enter accepts and moves it
        _folderChoice = inStash && pred.folders.isNotEmpty ? pred.folders.first.folder : current;
        _extraTags.clear();
      });
      return;
    }
    if (mounted) setState(() { _item = null; _pending = []; });
  }

  /// Pre-selected answer = model's best guess, so a correct guess is one keypress.
  Object? _guess(AutotagLabelInfo info, AutotagItemPrediction pred) {
    switch (info.kind) {
      case AutotagLabelKind.tag:
        return pred.tag(info.name) >= (info.suggestThreshold ?? 0.5);
      case AutotagLabelKind.kv:
        final top = pred.topKv(info.name);
        if (top == null || top.value == preds.noneValue) return GroupEmpty.notVisible;
        return top.value;
      case AutotagLabelKind.folder:
        return pred.folders.isEmpty ? _skip : pred.folders.first.folder;
    }
  }

  /// Groups in this batch that can be left empty.
  List<AutotagLabelInfo> get _noneCapable => _pending
      .where((i) => i.kind == AutotagLabelKind.kv && i.classes.contains(preds.noneValue))
      .toList();

  /// For files where the body groups make no sense (e.g. a guy).
  void _setAllNotApplicable() {
    setState(() {
      for (final info in _noneCapable) {
        _answers[info.id] = GroupEmpty.notApplicable;
      }
    });
  }

  Future<void> _save() async {
    final item = _item;
    if (item == null) return;
    final answers = <ReviewAnswer>[];
    for (final info in _pending) {
      final a = _answers[info.id];
      if (a == _skip) continue;
      switch (info.kind) {
        case AutotagLabelKind.tag:
          answers.add(TagAnswer(info.name, a as bool));
        case AutotagLabelKind.kv:
          answers.add(a is GroupEmpty ? GroupAnswer.empty(info.name, a) : GroupAnswer(info.name, a as String));
        case AutotagLabelKind.folder:
          break;   // handled by the folder row below
      }
    }
    for (final t in _extraTags) {
      answers.add(TagAnswer(t, true));
    }
    final choice = _folderChoice;
    if (choice != null && choice != _currentFolder) {
      final subId = widget.svc.subcategoryIdForFolder(choice);
      if (subId != null) answers.add(FolderAnswer(subId));
    }
    await widget.svc.saveReview(item, answers, preds.noneValue);
    unawaited(widget.svc.refreshNeedsReview(preds));
    _answered++;
    _pos++;
    await _loadCurrent();
  }

  void _skipFile() {
    _pos++;
    _loadCurrent();
  }

  Future<void> _retrain() async {
    setState(() => _retraining = true);
    int? code;
    await for (final e in widget.svc.run('predict')) {
      if (e.exitCode != null) code = e.exitCode;
    }
    if (!mounted) return;
    setState(() => _retraining = false);
    if (code == 0) {
      await widget.onPredictionsChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retraining failed — see the Run tab (Retrain only) for the log.')));
    }
  }

  @override
  void didUpdateWidget(covariant _ReviewTab old) {
    super.didUpdateWidget(old);
    if (old.preds != widget.preds && _queue != null) {   // retrained: fresh queue
      _restrict != null ? _startNeedsReview() : _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.preds == null) {
      return const Center(child: Text('Run an analysis first (Run tab).'));
    }
    return _queue == null ? _buildPicker(context) : _buildSession(context);
  }

  Widget _buildPicker(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final presets = _presets(app);
    final all = [...preds.groupLabels, ...preds.tagLabels, if (preds.folder != null) preds.folder!];
    final counts = {for (final l in all) l.id: preds.review[l.id]?.length ?? 0};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Review', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Pick a few tags to work on. You get the files the model is least sure about first; '
            'each answer teaches it. Press Enter to accept the highlighted answers.\n'
            "Not visible = it's there but you can't judge it. Doesn't apply = the group doesn't belong "
            'on this file (e.g. body groups for a guy). Both teach the model to leave the group empty.',
            style: TextStyle(color: theme.hintColor)),
        const SizedBox(height: 16),
        ValueListenableBuilder<bool>(
          valueListenable: AutotagService.needsReview,
          builder: (context, pending, _) => pending
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FilledButton.icon(
                    onPressed: _startNeedsReview,
                    icon: const ReviewMarker(child: Icon(Icons.priority_high)),
                    label: const Text('Needs review: new files the model is unsure about'),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Text('Batches', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in presets.entries)
            ActionChip(
              label: Text(e.key),
              onPressed: () => setState(() => _selected
                ..clear()
                ..addAll(e.value)),
            ),
        ]),
        const SizedBox(height: 16),
        Text('Or choose individual tags', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in all)
            FilterChip(
              label: Text('${l.name}  ${(l.quality * 100).round()}%'),
              tooltip: '${counts[l.id]} files to review · ${l.examples} examples',
              selected: _selected.contains(l.id),
              onSelected: (v) => setState(() => v ? _selected.add(l.id) : _selected.remove(l.id)),
            ),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: Text('Start review (${_selected.length} tags)'),
          ),
        ]),
      ],
    );
  }

  Widget _buildSession(BuildContext context) {
    final theme = Theme.of(context);
    final app = context.read<AppState>();
    final item = _item;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(children: [
        IconButton(
          tooltip: 'Back to batch selection',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _queue = null),
        ),
        Text('Answered $_answered · ${(_queue!.length - _pos).clamp(0, 1 << 30)} left in queue'),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _retraining ? null : _retrain,
          icon: _retraining
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: Text(_retraining ? 'Retraining…' : 'Retrain with my answers'),
        ),
      ]),
    );

    if (item == null) {
      return Column(children: [
        header,
        const Expanded(child: Center(child: Text('Nothing left to review for these tags. Retrain to get a fresh queue.'))),
      ]);
    }

    final sheet = widget.svc.sheetFor(item.id);
    final abs = LibraryFolders.absPath(app.paths!.filesDir, item.storedRelPath);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _save,
        const SingleActivator(LogicalKeyboardKey.keyS): _skipFile,
        const SingleActivator(LogicalKeyboardKey.keyN): _setAllNotApplicable,
      },
      child: Focus(
        autofocus: true,
        child: Column(children: [
          header,
          const Divider(height: 1),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Fill the panel; mouse wheel / drag to zoom into a frame.
                    // Images and GIFs show the original, videos the frames the model saw.
                    Expanded(
                      child: ClipRect(
                        child: InteractiveViewer(
                          key: ValueKey(item.id),
                          maxScale: 6,
                          child: SizedBox.expand(
                            child: item.type == ItemType.image
                                ? Image.file(File(abs), fit: BoxFit.contain, filterQuality: FilterQuality.medium)
                                : sheet.existsSync()
                                    ? Image.file(sheet, fit: BoxFit.contain, filterQuality: FilterQuality.medium)
                                    : const Center(child: Text('No preview yet — run Analyze.')),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: Text(item.originalName,
                            overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.hintColor)),
                      ),
                      TextButton.icon(
                        onPressed: () => OpenFilex.open(abs),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Open file'),
                      ),
                    ]),
                  ]),
                ),
              ),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 420,
                child: Column(children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_noneCapable.length > 1)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: OutlinedButton.icon(
                                onPressed: _setAllNotApplicable,
                                icon: const Icon(Icons.block, size: 16),
                                label: const Text("Doesn't apply to this file (N)"),
                              ),
                            ),
                          ),
                        _buildFolderRow(context),
                        for (final info in _pending)
                          if (info.kind != AutotagLabelKind.folder) _buildEditor(context, info),
                        _buildSure(context),
                        _buildExtraTags(context),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      TextButton(onPressed: _skipFile, child: const Text('Skip file (S)')),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check),
                        label: const Text('Save & next (Enter)'),
                      ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// What Lewdex decided on its own for this file (confident enough to auto-apply) and
  /// therefore didn't ask. Clicking one turns it into a normal question to correct it.
  List<({AutotagLabelInfo info, String text, double p})> _sureList() {
    final item = _item;
    final state = _state;
    final pred = item == null ? null : preds.items[item.id];
    if (item == null || state == null || pred == null) return const [];
    final asked = {for (final i in _pending) i.id};
    final out = <({AutotagLabelInfo info, String text, double p})>[];
    for (final info in preds.labels.values) {
      if (asked.contains(info.id) || pred.notApplicable.contains(info.id)) continue;
      switch (info.kind) {
        case AutotagLabelKind.kv:
          if (state.kv.containsKey(info.name) && !state.applied.contains(kvLabel(info.name, state.kv[info.name]!))) {
            continue;   // set by the user
          }
          final top = pred.topKv(info.name);
          if (top == null || top.value == preds.noneValue || !info.isAuto(top.p)) continue;
          out.add((info: info, text: '${info.name}: ${top.value}', p: top.p));
        case AutotagLabelKind.tag:
          if (info.recheck || state.feedback.containsKey(tagLabel(info.name))) continue;
          if (state.tagNames.contains(info.name) && !state.applied.contains(tagLabel(info.name))) continue;
          final p = pred.tag(info.name);
          if (info.isAuto(p)) out.add((info: info, text: info.name, p: p));
        case AutotagLabelKind.folder:
          break;
      }
    }
    out.sort((a, b) => a.info.kind == b.info.kind ? a.text.compareTo(b.text) : a.info.kind.index.compareTo(b.info.kind.index));
    return out;
  }

  Widget _buildSure(BuildContext context) {
    final theme = Theme.of(context);
    final sure = _sureList();
    if (sure.isEmpty) return const SizedBox.shrink();
    final pred = preds.items[_item!.id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Lewdex is sure', style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Expanded(
            child: Text('applied automatically · click one if it is wrong',
                overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: theme.hintColor)),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in sure)
            ActionChip(
              avatar: const Icon(Icons.verified_outlined, size: 16),
              label: Text('${s.text}  ${(s.p * 100).round()}%'),
              tooltip: 'Wrong? Click to answer it yourself',
              onPressed: () => setState(() {
                _pending = [..._pending, s.info];
                _answers[s.info.id] = _guess(s.info, pred);
              }),
            ),
        ]),
      ]),
    );
  }

  /// Tags this file has besides the ones asked: current ones (read-only) and "+ Add tag…".
  Widget _buildExtraTags(BuildContext context) {
    final theme = Theme.of(context);
    final asked = {for (final i in _pending) if (i.kind == AutotagLabelKind.tag) i.name};
    final has = _state?.tagNames ?? const <String>{};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Other tags', style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final t in has.where((t) => !asked.contains(t)).toList()..sort())
          Chip(label: Text(t), visualDensity: VisualDensity.compact),
        for (final t in _extraTags.toList()..sort())
          InputChip(
            label: Text(t),
            selected: true,
            onDeleted: () => setState(() => _extraTags.remove(t)),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Add tag…'),
          onPressed: () => _pickExtraTags(exclude: {
            ...asked,
            ...has,
            for (final s in _sureList()) if (s.info.kind == AutotagLabelKind.tag) s.info.name,
          }),
        ),
      ]),
    ]);
  }

  Future<void> _pickExtraTags({required Set<String> exclude}) async {
    final app = context.read<AppState>();
    final na = preds.items[_item!.id]?.notApplicable ?? const <String>{};
    final groupNames = {for (final g in app.tagGroupList) g.id: g.name};
    final byGroup = <String, List<String>>{};
    for (final t in app.tagList) {
      if (exclude.contains(t.name) || na.contains(tagLabel(t.name))) continue;
      byGroup.putIfAbsent(groupNames[t.groupId] ?? 'Other', () => []).add(t.name);
    }
    final picked = Set<String>.from(_extraTags);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add tags to this file'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final e in byGroup.entries) ...[
                  Text(e.key, style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final t in e.value)
                      FilterChip(
                        label: Text(t),
                        selected: picked.contains(t),
                        onSelected: (v) => setD(() => v ? picked.add(t) : picked.remove(t)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _extraTags
        ..clear()
        ..addAll(picked));
    }
  }

  static String? _folderOf(AppState app, String subcategoryId) {
    for (final c in app.categoryList) {
      for (final sub in app.subcategoriesFor(c.id)) {
        if (sub.id == subcategoryId) return '${c.name}/${sub.name}';
      }
    }
    return null;
  }

  /// Current folder (or the model's suggestion for inbox files), preselected.
  /// Leave it if it's right; pick another and Save moves the file.
  Widget _buildFolderRow(BuildContext context) {
    final theme = Theme.of(context);
    final app = context.read<AppState>();
    final pred = preds.items[_item!.id];
    final probs = {for (final f in pred?.folders ?? const <({String folder, double p})>[]) f.folder: f.p};
    final options = <String>[
      if (_currentFolder != null && !(app.stashCategoryId != null &&
          app.subcategoriesFor(app.stashCategoryId!).any((sub) => sub.id == _item!.subcategoryId)))
        _currentFolder!,
      for (final f in probs.keys)
        if (f != _currentFolder) f,
      if (_folderChoice != null && _folderChoice != _currentFolder && !probs.containsKey(_folderChoice)) _folderChoice!,
    ];
    final all = [
      for (final c in app.categoryList)
        for (final sub in app.subcategoriesFor(c.id)) '${c.name}/${sub.name}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Folder', style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _folderChoice == _currentFolder ? 'now in $_currentFolder' : 'now in $_currentFolder → will move on Save',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in options)
            ChoiceChip(
              label: Text(probs[f] == null ? f : '$f  ${(probs[f]! * 100).round()}%'),
              selected: _folderChoice == f,
              onSelected: (_) => setState(() => _folderChoice = f),
            ),
          PopupMenuButton<String>(
            tooltip: 'Other folder',
            onSelected: (f) => setState(() => _folderChoice = f),
            itemBuilder: (_) => [for (final f in all) PopupMenuItem(value: f, child: Text(f))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Other folder…', style: TextStyle(color: theme.colorScheme.primary)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _buildEditor(BuildContext context, AutotagLabelInfo info) {
    final theme = Theme.of(context);
    final app = context.read<AppState>();
    final pred = preds.items[_item!.id]!;
    final current = _answers[info.id];

    Widget choice(String label, Object? value, {double? p}) => ChoiceChip(
          label: Text(p == null ? label : '$label  ${(p * 100).round()}%'),
          selected: current == value,
          onSelected: (_) => setState(() => _answers[info.id] = value),
        );

    final List<Widget> chips;
    switch (info.kind) {
      case AutotagLabelKind.tag:
        final p = pred.tag(info.name);
        chips = [choice('Yes', true, p: p), choice('No', false)];
      case AutotagLabelKind.kv:
        final key = app.tagKeyList.where((k) => k.key == info.name).firstOrNull;
        final values = key == null ? <String>[] : app.valuesForKey(key.id).map((v) => v.value).toList();
        final dist = pred.kv[info.name] ?? const {};
        chips = [
          for (final v in values) choice(v, v, p: dist[v]),
          if (info.classes.contains(preds.noneValue)) ...[
            // the model can't tell these two apart; its "empty" % is shown on Not visible
            choice('Not visible', GroupEmpty.notVisible, p: dist[preds.noneValue]),
            choice("Doesn't apply", GroupEmpty.notApplicable),
          ],
        ];
      case AutotagLabelKind.folder:
        chips = [
          for (final f in pred.folders) choice(f.folder, f.folder, p: f.p),
          choice('None of these', _skip),
        ];
    }
    final applied = info.kind == AutotagLabelKind.tag && (_state?.applied.contains(tagLabel(info.name)) ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(info.name, style: theme.textTheme.titleSmall),
          if (applied) ...[
            const SizedBox(width: 8),
            Text('added by Lewdex', style: TextStyle(fontSize: 11, color: theme.hintColor)),
          ],
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Training files tab: drop example files you're sure about onto a tag
// ─────────────────────────────────────────────────────────────────────────────

class _TrainingTab extends StatefulWidget {
  final AutotagService svc;
  const _TrainingTab({required this.svc});

  @override
  State<_TrainingTab> createState() => _TrainingTabState();
}

class _TrainingTabState extends State<_TrainingTab> {
  String _filter = '';

  Future<void> _add({String? key, required String value, required List<String> paths}) async {
    final n = await widget.svc.addTrainingFiles(key: key, value: value, paths: paths);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Added $n files to ${key == null ? value : key == '_Folders' ? 'folder $value' : '$key › $value'}. '
            'They are used on the next "Analyze new files & retrain".')));
  }

  Future<void> _pick({String? key, required String value}) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths = res?.files.map((f) => f.path).whereType<String>().toList() ?? [];
    if (paths.isNotEmpty) await _add(key: key, value: value, paths: paths);
  }

  Future<void> _openFolder({String? key, required String value}) async {
    final dir = widget.svc.trainingDirFor(key: key, value: value);
    await dir.create(recursive: true);
    await OpenFilex.open(dir.path);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    bool match(String s) => _filter.isEmpty || s.toLowerCase().contains(_filter.toLowerCase());

    final groups = app.tagKeyList.where((k) => !_manualKeys.contains(k.key)).toList();
    // folder content types, shared across categories (Girls/Femdom + Anime/Femdom -> Femdom)
    final folderTypes = <String, List<String>>{};   // lower-case name -> categories
    final folderNames = <String, String>{};
    for (final c in app.categoryList) {
      if (_personCategories.contains(c.name)) continue;
      for (final sub in app.subcategoriesFor(c.id)) {
        final k = sub.name.toLowerCase();
        folderNames.putIfAbsent(k, () => sub.name);
        folderTypes.putIfAbsent(k, () => []).add(c.name);
      }
    }
    final groupNames = {for (final g in app.tagGroupList) g.id: g.name};
    final tagsByGroup = <String, List<Tag>>{};
    for (final t in app.tagList) {
      tagsByGroup.putIfAbsent(groupNames[t.groupId] ?? 'Other', () => []).add(t);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Training files', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Drop images or videos that clearly show one tag (e.g. 20–50 per value). They are copied to '
            'Library/training and only used for learning — they never appear in your library.',
            style: TextStyle(color: theme.hintColor)),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter…', isDense: true),
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 16),
        if (folderTypes.keys.any((k) => match('folder ${folderNames[k]}'))) ...[
          Text('Folders (main focus of the file)', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in folderTypes.keys.toList()..sort())
              if (match('folder ${folderNames[k]}'))
                _DropTile(
                  title: folderNames[k]!,
                  subtitle: 'Used for ${folderTypes[k]!.map((c) => '$c/${folderNames[k]}').join(', ')}',
                  count: widget.svc.countTrainingFiles(key: '_Folders', value: folderNames[k]!),
                  onDrop: (paths) => _add(key: '_Folders', value: folderNames[k]!, paths: paths),
                  onPick: () => _pick(key: '_Folders', value: folderNames[k]!),
                  onOpen: () => _openFolder(key: '_Folders', value: folderNames[k]!),
                ),
          ]),
          const SizedBox(height: 16),
        ],
        for (final k in groups)
          if (app.valuesForKey(k.id).any((v) => match('${k.key} ${v.value}'))) ...[
            Text(k.key, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in app.valuesForKey(k.id))
                if (match('${k.key} ${v.value}'))
                  _DropTile(
                    title: v.value,
                    subtitle: v.description,
                    count: widget.svc.countTrainingFiles(key: k.key, value: v.value),
                    onDrop: (paths) => _add(key: k.key, value: v.value, paths: paths),
                    onPick: () => _pick(key: k.key, value: v.value),
                    onOpen: () => _openFolder(key: k.key, value: v.value),
                  ),
            ]),
            const SizedBox(height: 16),
          ],
        for (final e in tagsByGroup.entries)
          if (e.value.any((t) => match(t.name))) ...[
            Text(e.key, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in e.value)
                if (match(t.name))
                  _DropTile(
                    title: t.name,
                    subtitle: t.description,
                    count: widget.svc.countTrainingFiles(value: t.name),
                    onDrop: (paths) => _add(value: t.name, paths: paths),
                    onPick: () => _pick(value: t.name),
                    onOpen: () => _openFolder(value: t.name),
                  ),
            ]),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class _DropTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final int count;
  final void Function(List<String> paths) onDrop;
  final VoidCallback onPick;
  final VoidCallback onOpen;

  const _DropTile({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.onDrop,
    required this.onPick,
    required this.onOpen,
  });

  @override
  State<_DropTile> createState() => _DropTileState();
}

class _DropTileState extends State<_DropTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (d) {
        setState(() => _hover = false);
        widget.onDrop(d.files.map((f) => f.path).toList());
      },
      child: Tooltip(
        message: widget.subtitle.isEmpty ? 'Drop files here' : widget.subtitle,
        child: Container(
          width: 200,
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: _hover ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: Border.all(color: _hover ? theme.colorScheme.primary : theme.dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(widget.count == 0 ? 'drop files' : '${widget.count} files',
                    style: TextStyle(fontSize: 12, color: theme.hintColor)),
              ]),
            ),
            IconButton(tooltip: 'Add files…', icon: const Icon(Icons.add, size: 18), onPressed: widget.onPick),
            IconButton(tooltip: 'Open folder', icon: const Icon(Icons.folder_open, size: 18), onPressed: widget.onOpen),
          ]),
        ),
      ),
    );
  }
}

/// Dot shown on an icon while there is something to review (no count on purpose).
class ReviewMarker extends StatelessWidget {
  final Widget child;
  const ReviewMarker({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AutotagService.needsReview,
        builder: (context, pending, child) => Badge(
          isLabelVisible: pending,
          smallSize: 9,
          backgroundColor: Colors.orangeAccent,
          child: child,
        ),
        child: child,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rules tab: which tags never apply to which folders, and folders kept manual
// ─────────────────────────────────────────────────────────────────────────────

class _RulesTab extends StatefulWidget {
  final AutotagService svc;
  const _RulesTab({required this.svc});

  @override
  State<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<_RulesTab> {
  AutotagRules? _rules;

  @override
  void initState() {
    super.initState();
    widget.svc.loadRules().then((r) { if (mounted) setState(() => _rules = r); });
  }

  Future<void> _save() async {
    await widget.svc.saveRules(_rules!);
    if (mounted) setState(() {});
  }

  /// 'Girls', 'Girls/Ass', ... for every category and subcategory.
  List<String> _folders(AppState app) => [
        for (final c in app.categoryList) ...[
          c.name,
          for (final s in app.subcategoriesFor(c.id)) '${c.name}/${s.name}',
        ],
      ];

  Future<void> _editLabels(NotApplicableRule rule) async {
    final picked = await pickNeverLabels(context, rule.folder, rule.labels);
    if (picked == null) return;
    rule.labels
      ..clear()
      ..addAll(picked);
    await _save();
  }

  String _labelName(String id) => id.startsWith('kv:') ? id.substring(3) : id.startsWith('tag:') ? id.substring(4) : id;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final rules = _rules;
    if (rules == null) return const Center(child: CircularProgressIndicator());
    final folders = _folders(app);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Rules', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Tags and groups that never apply to some folders (e.g. Age for Boys). They are never '
            'auto-applied or asked in review there. A category rule (e.g. "Boys") covers all its '
            'subfolders. For files still in the inbox the predicted folder is used. '
            'Changes take effect after the next retrain.',
            style: TextStyle(color: theme.hintColor)),
        const SizedBox(height: 16),
        Text("Doesn't apply", style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final rule in rules.notApplicable)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Files in  '),
                  DropdownButton<String>(
                    value: folders.contains(rule.folder) ? rule.folder : null,
                    hint: Text(rule.folder),
                    items: [for (final f in folders) DropdownMenuItem(value: f, child: Text(f))],
                    onChanged: (v) { if (v != null) { rule.folder = v; _save(); } },
                  ),
                  const Text('  never get:'),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editLabels(rule),
                  ),
                  IconButton(
                    tooltip: 'Delete rule',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () { rules.notApplicable.remove(rule); _save(); },
                  ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (rule.labels.isEmpty) Text('nothing yet, click edit', style: TextStyle(color: theme.hintColor)),
                  for (final id in rule.labels.toList()..sort())
                    InputChip(
                      label: Text(_labelName(id)),
                      onDeleted: () { rule.labels.remove(id); _save(); },
                    ),
                ]),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: folders.isEmpty
                ? null
                : () async {
                    final rule = NotApplicableRule(folders.first, {});
                    rules.notApplicable.add(rule);
                    await _save();
                    await _editLabels(rule);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add rule'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Manual folders', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('The tagger never suggests these folders or moves files into them.',
            style: TextStyle(color: theme.hintColor)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in rules.manualFolders)
            InputChip(label: Text(f), onDeleted: () { rules.manualFolders.remove(f); _save(); }),
          DropdownButton<String>(
            hint: const Text('Add folder…'),
            value: null,
            items: [
              for (final f in folders)
                if (f.contains('/') && !rules.manualFolders.contains(f)) DropdownMenuItem(value: f, child: Text(f)),
            ],
            onChanged: (v) { if (v != null) { rules.manualFolders.add(v); _save(); } },
          ),
        ]),
      ],
    );
  }
}

/// Dialog to pick the groups/tags that never apply to [folder]. Returns null on cancel.
Future<Set<String>?> pickNeverLabels(BuildContext context, String folder, Set<String> initial,
    {Set<String> inherited = const {}}) {
  final app = context.read<AppState>();
  final labels = [
    for (final k in app.tagKeyList)
      if (!_manualKeys.contains(k.key)) (id: 'kv:${k.key}', name: k.key, group: true),
    for (final t in app.tagList) (id: tagLabel(t.name), name: t.name, group: false),
  ];
  final picked = Set<String>.from(initial);
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text('Never apply to $folder'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Selected groups and tags are never auto-tagged or asked in review for files here.',
                  style: TextStyle(color: Theme.of(ctx).hintColor)),
              if (inherited.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Already excluded by the category: ${inherited.map((l) => l.substring(l.indexOf(':') + 1)).join(', ')}',
                    style: TextStyle(color: Theme.of(ctx).hintColor, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Text('Groups', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final l in labels.where((l) => l.group))
                  FilterChip(
                    label: Text(l.name),
                    selected: picked.contains(l.id) || inherited.contains(l.id),
                    onSelected: inherited.contains(l.id) ? null : (v) => setD(() => v ? picked.add(l.id) : picked.remove(l.id)),
                  ),
              ]),
              const SizedBox(height: 12),
              Text('Tags', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final l in labels.where((l) => !l.group))
                  FilterChip(
                    label: Text(l.name),
                    selected: picked.contains(l.id) || inherited.contains(l.id),
                    onSelected: inherited.contains(l.id) ? null : (v) => setD(() => v ? picked.add(l.id) : picked.remove(l.id)),
                  ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, picked), child: const Text('Save')),
        ],
      ),
    ),
  );
}

/// Edit the "never applies" rule of one category or subfolder (used from Categories).
Future<void> showNeverTagsDialog(BuildContext context, String folder) async {
  final svc = AutotagService(context.read<AppState>());
  final rules = await svc.loadRules();
  final rule = rules.notApplicable.where((r) => r.folder == folder).firstOrNull;
  final category = folder.contains('/') ? folder.substring(0, folder.indexOf('/')) : null;
  final inherited = category == null
      ? <String>{}
      : rules.notApplicable.where((r) => r.folder == category).expand((r) => r.labels).toSet();
  if (!context.mounted) return;
  final picked = await pickNeverLabels(context, folder, rule?.labels ?? {}, inherited: inherited);
  if (picked == null) return;
  if (rule != null) {
    rule.labels
      ..clear()
      ..addAll(picked);
  } else if (picked.isNotEmpty) {
    rules.notApplicable.add(NotApplicableRule(folder, picked));
  }
  rules.notApplicable.removeWhere((r) => r.labels.isEmpty);
  await svc.saveRules(rules);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. Takes effect after the next retrain (Lewdex → Run).')));
  }
}
