import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_state.dart';
import 'models.dart';
import 'thumbnail_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Auto-tagger integration.
//
// The Python tagger (separate folder, see settings) reads the library DB and
// writes Library/autotag/predictions.json. The app only reads that file and
// applies changes through its own repositories, so the DB, sidecars and folders
// stay consistent.
//
// Labels are strings shared with the tagger:
//   'tag:<name>'  'kv:<key>=<value>'  'folder:<category>/<subcategory>'
// ─────────────────────────────────────────────────────────────────────────────

String tagLabel(String name) => 'tag:$name';
String kvLabel(String key, String value) => 'kv:$key=$value';
String folderLabel(String folder) => 'folder:$folder';

enum AutotagLabelKind { tag, kv, folder }

class AutotagLabelInfo {
  /// 'tag:<name>', 'kv:<key>' or 'folder'
  final String id;
  final AutotagLabelKind kind;
  final String name;
  /// tags: average precision, groups/folder: accuracy (0..1)
  final double quality;
  final double baseRate;
  final double? autoThreshold;
  final double? suggestThreshold;
  final int examples;
  final List<String> missingValues;
  /// Values the model learned (groups/folder), including the not-visible option.
  final List<String> classes;
  /// Combination tag: never auto-applied, every matching file is asked in review.
  final bool recheck;

  AutotagLabelInfo({
    required this.id,
    required this.kind,
    required this.name,
    required this.quality,
    required this.baseRate,
    required this.autoThreshold,
    required this.suggestThreshold,
    required this.examples,
    required this.missingValues,
    required this.classes,
    this.recheck = false,
  });

  factory AutotagLabelInfo.fromJson(String id, Map<String, dynamic> j) => AutotagLabelInfo(
        id: id,
        kind: AutotagLabelKind.values.byName(j['kind'] as String),
        name: j['name'] as String,
        quality: (j['quality'] as num).toDouble(),
        baseRate: (j['base_rate'] as num).toDouble(),
        autoThreshold: (j['auto'] as num?)?.toDouble(),
        suggestThreshold: (j['suggest'] as num?)?.toDouble(),
        examples: (j['examples'] as num).toInt(),
        missingValues: ((j['missing_values'] as List?) ?? const []).cast<String>(),
        classes: ((j['classes'] as Map?) ?? const {}).keys.cast<String>().toList(),
        recheck: (j['recheck'] as bool?) ?? false,
      );

  bool isAuto(double p) => autoThreshold != null && p >= autoThreshold!;
  bool isSuggested(double p) => suggestThreshold != null && p >= suggestThreshold!;
}

class AutotagItemPrediction {
  final Map<String, double> tags;
  final Map<String, Map<String, double>> kv;
  final List<({String folder, double p})> folders;
  /// Label ids ('kv:Age', 'tag:Mommy') that don't apply to this file (Rules tab).
  final Set<String> notApplicable;

  AutotagItemPrediction(this.tags, this.kv, this.folders, this.notApplicable);

  factory AutotagItemPrediction.fromJson(Map<String, dynamic> j) => AutotagItemPrediction(
        (j['tag'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        (j['kv'] as Map).map((k, v) => MapEntry(
            k as String, (v as Map).map((k2, v2) => MapEntry(k2 as String, (v2 as num).toDouble())))),
        [
          for (final f in (j['folder'] as List? ?? const []))
            (folder: (f as List)[0] as String, p: (f[1] as num).toDouble()),
        ],
        ((j['na'] as List?) ?? const []).cast<String>().toSet(),
      );

  double tag(String name) => tags[name] ?? 0;

  /// Most likely value of a group, or null when the group wasn't predicted.
  ({String value, double p})? topKv(String key) {
    final dist = kv[key];
    if (dist == null || dist.isEmpty) return null;
    final best = dist.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return (value: best.key, p: best.value);
  }
}

class AutotagPredictions {
  final DateTime generatedAt;
  /// The learned "leave empty" value of a group (not visible / doesn't apply).
  final String noneValue;
  /// Group that marks a file as fully hand-tagged (empty body groups there mean "not visible")
  final String reviewedMarkerKey;
  final Map<String, AutotagLabelInfo> labels;
  final Map<String, AutotagItemPrediction> items;
  /// label id -> item ids, most uncertain first
  final Map<String, List<String>> review;
  /// label id -> quality in the previous retrain (for trend arrows)
  final Map<String, double> previousQuality;
  /// item id -> label ids that need the user (new files the model is unsure about,
  /// combination-tag matches). Drives the review marker.
  final Map<String, List<String>> attention;

  AutotagPredictions({
    required this.generatedAt,
    required this.noneValue,
    this.reviewedMarkerKey = 'Scene Type',
    required this.labels,
    required this.items,
    required this.review,
    required this.previousQuality,
    required this.attention,
  });

  factory AutotagPredictions.fromJson(Map<String, dynamic> j) => AutotagPredictions(
        generatedAt: DateTime.fromMillisecondsSinceEpoch((j['generated_at'] as num).toInt()),
        noneValue: (j['none_value'] ?? j['not_visible']) as String,
        reviewedMarkerKey: (j['reviewed_marker_key'] as String?) ?? 'Scene Type',
        labels: (j['labels'] as Map).map(
            (k, v) => MapEntry(k as String, AutotagLabelInfo.fromJson(k, v as Map<String, dynamic>))),
        items: (j['items'] as Map).map(
            (k, v) => MapEntry(k as String, AutotagItemPrediction.fromJson(v as Map<String, dynamic>))),
        review: (j['review'] as Map).map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
        previousQuality: ((j['previous'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        attention: ((j['attention'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
      );

  List<AutotagLabelInfo> get groupLabels =>
      labels.values.where((l) => l.kind == AutotagLabelKind.kv).toList();
  List<AutotagLabelInfo> get tagLabels =>
      labels.values.where((l) => l.kind == AutotagLabelKind.tag).toList();
  AutotagLabelInfo? get folder => labels['folder'];
}

class NotApplicableRule {
  /// 'Category' or 'Category/Subcategory'
  String folder;
  /// label ids, e.g. 'kv:Age', 'tag:Mommy'
  final Set<String> labels;
  NotApplicableRule(this.folder, this.labels);
}

class AutotagRules {
  final List<NotApplicableRule> notApplicable;
  final Map<String, String> genreCategory;   // kept as-is, edited by hand if ever needed
  final List<String> manualFolders;

  AutotagRules({required this.notApplicable, required this.genreCategory, required this.manualFolders});

  factory AutotagRules.fromJson(Map<String, dynamic> j) => AutotagRules(
        notApplicable: [
          for (final r in (j['not_applicable'] as List? ?? const []))
            NotApplicableRule((r as Map)['folder'] as String, ((r['labels'] as List?) ?? const []).cast<String>().toSet()),
        ],
        genreCategory: ((j['genre_category'] as Map?) ?? const {}).cast<String, String>(),
        manualFolders: ((j['manual_folders'] as List?) ?? const []).cast<String>(),
      );

  Map<String, Object?> toJson() => {
        'not_applicable': [
          for (final r in notApplicable) {'folder': r.folder, 'labels': r.labels.toList()..sort()},
        ],
        'genre_category': genreCategory,
        'manual_folders': manualFolders,
      };
}

/// One answer from the review screen.
sealed class ReviewAnswer {}

class TagAnswer extends ReviewAnswer {
  final String tag;
  final bool present;
  TagAnswer(this.tag, this.present);
}

/// Why a group was left empty. Both teach the model "leave it empty"; they are stored
/// separately so "doesn't apply" answers can later become fixed rules.
enum GroupEmpty { notVisible, notApplicable }

/// Feedback value for each kind of empty answer (shared with the tagger).
const groupEmptyValues = {GroupEmpty.notVisible: '(none)', GroupEmpty.notApplicable: '(n/a)'};

class GroupAnswer extends ReviewAnswer {
  final String key;
  /// null when the group is left empty, see [empty]
  final String? value;
  final GroupEmpty? empty;
  GroupAnswer(this.key, this.value) : empty = null;
  GroupAnswer.empty(this.key, GroupEmpty this.empty) : value = null;
}

class FolderAnswer extends ReviewAnswer {
  final String subcategoryId;
  FolderAnswer(this.subcategoryId);
}

/// What the user already decided for an item, so it is not asked again.
class ItemLabelState {
  final Set<String> tagNames;          // current simple tags
  final Map<String, String> kv;        // key -> value
  final Set<String> applied;           // labels added by the model, unconfirmed
  final Map<String, int> feedback;     // label -> verdict

  ItemLabelState(this.tagNames, this.kv, this.applied, this.feedback);

  /// Simple tags typed in the normal tag dialog (so missing ones mean "no").
  bool get handTaggedSimple => tagNames.any(
      (t) => !applied.contains(tagLabel(t)) && feedback[tagLabel(t)] != 1);

  bool knowsTag(String tag) =>
      feedback.containsKey(tagLabel(tag)) ||
      (tagNames.contains(tag) && !applied.contains(tagLabel(tag))) ||
      handTaggedSimple;

  bool knowsGroup(String key) {
    final v = kv[key];
    if (v != null && !applied.contains(kvLabel(key, v))) return true;
    // any confirmed answer for the group, including "none"
    return feedback.entries.any((e) => e.value == 1 && e.key.startsWith('kv:$key='));
  }
}

class AutotagEvent {
  final String? line;
  final String? stage;
  final int done;
  final int total;
  final int? exitCode;
  AutotagEvent.log(this.line) : stage = null, done = 0, total = 0, exitCode = null;
  AutotagEvent.progress(this.stage, this.done, this.total) : line = null, exitCode = null;
  AutotagEvent.exit(this.exitCode) : line = null, stage = null, done = 0, total = 0;
}

class AutotagService {
  final AppState app;
  AutotagService(this.app);

  Database get _db => app.database!;
  Directory get libraryDir => app.paths!.libraryDir;
  Directory get workDir => Directory(p.join(libraryDir.path, 'autotag'));
  Directory get trainingDir => Directory(p.join(libraryDir.path, 'training'));
  File get predictionsFile => File(p.join(workDir.path, 'predictions.json'));
  File sheetFor(String itemId) => File(p.join(workDir.path, 'sheets', '$itemId.jpg'));

  // ── Locating the tagger ────────────────────────────────────────────────────

  static bool _isTaggerDir(String dir) =>
      File(p.join(dir, 'autotag', '__main__.py')).existsSync();

  /// Configured folder, else `Tagger` next to the app or the library.
  String? findTagger() {
    final configured = app.settings.taggerPath.trim();
    if (configured.isNotEmpty) return _isTaggerDir(configured) ? configured : null;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    for (final c in [
      p.join(exeDir, 'Tagger'),
      p.join(exeDir, '..', 'Tagger'),
      p.join(libraryDir.path, '..', 'Tagger'),
    ]) {
      final dir = p.normalize(c);
      if (_isTaggerDir(dir)) return dir;
    }
    return null;
  }

  static String? pythonFor(String taggerDir) {
    for (final rel in [
      ['.venv', 'Scripts', 'python.exe'],
      ['python', 'python.exe'],
      ['.venv', 'bin', 'python'],
      ['python', 'bin', 'python3'],
    ]) {
      final f = File(p.joinAll([taggerDir, ...rel]));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Process? _running;
  bool get isRunning => _running != null;

  /// Runs `python -m autotag <command>`: 'run' (analyze new files + retrain) or
  /// 'predict' (retrain only).
  Stream<AutotagEvent> run(String command) {
    final controller = StreamController<AutotagEvent>();
    () async {
      final tagger = findTagger();
      final python = tagger == null ? null : pythonFor(tagger);
      if (tagger == null || python == null) {
        controller.add(AutotagEvent.log(tagger == null
            ? 'Lewdex folder not found. Choose it on the Run tab (Tagger → Choose…).'
            : 'No Python environment found in $tagger (.venv or python folder).'));
        controller.add(AutotagEvent.exit(-1));
        await controller.close();
        return;
      }
      final ffmpeg = await ThumbnailService.resolvedFfmpegPath();
      final args = ['-u', '-m', 'autotag', command, '--library', libraryDir.path];
      if (ffmpeg != null) args.addAll(['--ffmpeg', ffmpeg]);
      try {
        final proc = await Process.start(python, args,
            workingDirectory: tagger, environment: {'PYTHONIOENCODING': 'utf-8'});
        _running = proc;
        void onLine(String line) {
          final parts = line.trim().split(' ');
          if (parts.length == 4 && parts[0] == '@progress') {
            controller.add(AutotagEvent.progress(
                parts[1], int.tryParse(parts[2]) ?? 0, int.tryParse(parts[3]) ?? 0));
          } else if (line.trim().isNotEmpty && line.trim() != '@done') {
            controller.add(AutotagEvent.log(line));
          }
        }

        final out = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
        final err = proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
        final code = await proc.exitCode;
        await out.asFuture<void>();
        await err.asFuture<void>();
        controller.add(AutotagEvent.exit(code));
      } catch (e) {
        controller.add(AutotagEvent.log('Failed to start tagger: $e'));
        controller.add(AutotagEvent.exit(-1));
      } finally {
        _running = null;
        await controller.close();
      }
    }();
    return controller.stream;
  }

  void cancel() => _running?.kill();

  /// True while some file still needs an answer in review: shown as a dot on the
  /// Auto-tag icon and the Review tab.
  static final needsReview = ValueNotifier<bool>(false);

  bool _inStash(String subcategoryId) =>
      app.stashCategoryId != null &&
      app.subcategoriesFor(app.stashCategoryId!).any((s) => s.id == subcategoryId);

  /// Whether the user already answered [info] for this item (so it isn't asked again).
  bool isKnown(AutotagPredictions preds, AutotagLabelInfo info, ItemLabelState s, MediaItem item) {
    switch (info.kind) {
      case AutotagLabelKind.tag:
        if (preds.items[item.id]?.notApplicable.contains(info.id) ?? false) return true;
        // combination tags re-check even hand-tagged files until answered in review
        return info.recheck ? s.feedback.containsKey(tagLabel(info.name)) : s.knowsTag(info.name);
      case AutotagLabelKind.kv:
        return s.knowsGroup(info.name) ||
            (preds.items[item.id]?.notApplicable.contains(info.id) ?? false);
      case AutotagLabelKind.folder:
        return !_inStash(item.subcategoryId) || s.feedback.keys.any((k) => k.startsWith('folder:'));
    }
  }

  /// Recomputes [needsReview]; stops at the first file with an unanswered label.
  Future<void> refreshNeedsReview([AutotagPredictions? preds]) async {
    preds ??= await loadPredictions();
    if (preds == null || preds.attention.isEmpty || app.items == null) {
      needsReview.value = false;
      return;
    }
    final items = {for (final i in await app.items!.listItemsByIds(preds.attention.keys.toList())) i.id: i};
    for (final e in preds.attention.entries) {
      final item = items[e.key];
      if (item == null) continue;
      final state = await stateFor(item.id);
      for (final lid in e.value) {
        final info = preds.labels[lid];
        if (info != null && !isKnown(preds, info, state, item)) {
          needsReview.value = true;
          return;
        }
      }
    }
    needsReview.value = false;
  }

  // ── Rules (Library/autotag/rules.json, shared with the tagger) ───────────────

  File get rulesFile => File(p.join(workDir.path, 'rules.json'));

  Future<AutotagRules> loadRules() async {
    try {
      if (await rulesFile.exists()) {
        return AutotagRules.fromJson(jsonDecode(await rulesFile.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    return AutotagRules(notApplicable: [], genreCategory: {}, manualFolders: []);
  }

  Future<void> saveRules(AutotagRules rules) async {
    await workDir.create(recursive: true);
    final tmp = File('${rulesFile.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(rules.toJson()));
    await tmp.rename(rulesFile.path);
  }

  Future<AutotagPredictions?> loadPredictions() async {
    final f = predictionsFile;
    if (!await f.exists()) return null;
    try {
      return AutotagPredictions.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ── Item state ─────────────────────────────────────────────────────────────

  Future<ItemLabelState> stateFor(String itemId) async {
    final tags = await _db.rawQuery(
        'SELECT t.name FROM item_tags it JOIN tags t ON t.id = it.tag_id WHERE it.item_id = ?', [itemId]);
    final kv = await _db.rawQuery(
        'SELECT k.key, v.value FROM item_tag_key_values x '
        'JOIN tag_key_values v ON v.id = x.key_value_id JOIN tag_keys k ON k.id = v.key_id '
        'WHERE x.item_id = ?',
        [itemId]);
    final applied = await _db.query('autotag_applied', where: 'item_id=?', whereArgs: [itemId]);
    final fb = await _db.query('autotag_feedback', where: 'item_id=?', whereArgs: [itemId]);
    return ItemLabelState(
      {for (final r in tags) r['name'] as String},
      {for (final r in kv) r['key'] as String: r['value'] as String},
      {for (final r in applied) r['label'] as String},
      {for (final r in fb) r['label'] as String: r['verdict'] as int},
    );
  }

  Future<void> _markApplied(String itemId, String label, double p) => _db.insert(
        'autotag_applied',
        {'item_id': itemId, 'label': label, 'confidence': p, 'created_at': _now()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> _feedback(String itemId, String label, int verdict) => _db.insert(
        'autotag_feedback',
        {'item_id': itemId, 'label': label, 'verdict': verdict, 'created_at': _now()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> _clearApplied(String itemId, String labelPrefix) => _db.delete('autotag_applied',
      where: 'item_id=? AND label LIKE ?', whereArgs: [itemId, '$labelPrefix%']);

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  // ── Lookups by name ────────────────────────────────────────────────────────

  Tag? _tagByName(String name) {
    for (final t in app.tagList) {
      if (t.name == name) return t;
    }
    return null;
  }

  TagKey? _keyByName(String key) {
    for (final k in app.tagKeyList) {
      if (k.key == key) return k;
    }
    return null;
  }

  TagKeyValue? _valueByName(String key, String value) {
    final k = _keyByName(key);
    if (k == null) return null;
    for (final v in app.valuesForKey(k.id)) {
      if (v.value == value) return v;
    }
    return null;
  }

  /// 'Category/Subcategory' -> subcategory id
  String? subcategoryIdForFolder(String folder) {
    final i = folder.indexOf('/');
    if (i < 0) return null;
    final catName = folder.substring(0, i), subName = folder.substring(i + 1);
    for (final c in app.categoryList) {
      if (c.name != catName) continue;
      for (final s in app.subcategoriesFor(c.id)) {
        if (s.name == subName) return s.id;
      }
    }
    return null;
  }

  Future<void> _setGroupValue(String itemId, String key, String? value) async {
    final k = _keyByName(key);
    if (k == null) return;
    final current = await app.items!.listKeyValueIdsForItem(itemId);
    final ofKey = app.valuesForKey(k.id).map((v) => v.id).toSet();
    for (final id in current.intersection(ofKey)) {
      await app.items!.removeKeyValueFromItem(itemId, id);
    }
    if (value != null) {
      final v = _valueByName(key, value);
      if (v != null) await app.items!.addKeyValueToItem(itemId, v.id);
    }
  }

  // ── Apply confident predictions ────────────────────────────────────────────

  /// Applies every prediction above its auto threshold to [items]: unknown simple
  /// tags, empty groups, and (for items in the stash) the destination folder.
  /// Returns counts for the summary.
  Future<({int tags, int groups, int moved, int files})> applyConfident(
    AutotagPredictions preds,
    List<MediaItem> items, {
    bool moveFolders = true,
  }) async {
    var nTags = 0, nGroups = 0, nFiles = 0;
    final moves = <String, List<MediaItem>>{};
    final stashSubs = app.stashCategoryId == null
        ? <String>{}
        : app.subcategoriesFor(app.stashCategoryId!).map((s) => s.id).toSet();

    for (final item in items) {
      final pred = preds.items[item.id];
      if (pred == null) continue;
      final state = await stateFor(item.id);
      var changed = false;

      for (final info in preds.tagLabels) {
        final tag = _tagByName(info.name);
        final prob = pred.tag(info.name);
        if (tag == null || !info.isAuto(prob) || pred.notApplicable.contains(info.id)) continue;
        if (state.knowsTag(info.name) || state.tagNames.contains(info.name)) continue;
        await app.items!.addTagToItem(item.id, tag.id);
        await _markApplied(item.id, tagLabel(info.name), prob);
        nTags++;
        changed = true;
      }

      for (final info in preds.groupLabels) {
        if (state.kv.containsKey(info.name) || state.knowsGroup(info.name)) continue;
        // on hand-tagged files an empty body group means "not visible": leave it empty
        final marker = state.kv[preds.reviewedMarkerKey];
        if (info.classes.contains(preds.noneValue) && marker != null &&
            !state.applied.contains(kvLabel(preds.reviewedMarkerKey, marker))) {
          continue;
        }
        if (pred.notApplicable.contains(info.id)) continue;
        final top = pred.topKv(info.name);
        if (top == null || top.value == preds.noneValue || !info.isAuto(top.p)) continue;
        if (state.feedback[kvLabel(info.name, top.value)] == 0) continue;
        await _setGroupValue(item.id, info.name, top.value);
        await _markApplied(item.id, kvLabel(info.name, top.value), top.p);
        nGroups++;
        changed = true;
      }

      final folderInfo = preds.folder;
      if (moveFolders && folderInfo != null && stashSubs.contains(item.subcategoryId) && pred.folders.isNotEmpty) {
        final best = pred.folders.first;
        final subId = subcategoryIdForFolder(best.folder);
        if (subId != null && folderInfo.isAuto(best.p) && state.feedback[folderLabel(best.folder)] != 0) {
          moves.putIfAbsent(subId, () => []).add(item);
          await _markApplied(item.id, folderLabel(best.folder), best.p);
        }
      }

      if (changed) {
        nFiles++;
        await app.items!.writeSidecarForItemId(item.id);
      }
    }

    var nMoved = 0;
    for (final e in moves.entries) {
      await app.items!.moveItemsToSubcategory(e.value, e.key);
      for (final item in e.value) {
        await app.applyAutoTagsToItem(item.id, e.key);
      }
      nMoved += e.value.length;
    }
    await app.refreshFromDiskAndMigrate();
    await app.refreshAll();
    await refreshNeedsReview(preds);
    return (tags: nTags, groups: nGroups, moved: nMoved, files: nFiles);
  }

  // ── Review answers ─────────────────────────────────────────────────────────

  Future<void> saveReview(MediaItem item, List<ReviewAnswer> answers, String noneValue) async {
    String? moveTo;
    for (final a in answers) {
      switch (a) {
        case TagAnswer(:final tag, :final present):
          final t = _tagByName(tag);
          if (t == null) continue;
          if (present) {
            await app.items!.addTagToItem(item.id, t.id);
          } else {
            await app.items!.removeTagFromItem(item.id, t.id);
          }
          await _clearApplied(item.id, tagLabel(tag));
          await _feedback(item.id, tagLabel(tag), present ? 1 : 0);
        case GroupAnswer(:final key, :final value, :final empty):
          await _setGroupValue(item.id, key, value);
          await _clearApplied(item.id, 'kv:$key=');
          await _feedback(item.id, kvLabel(key, value ?? groupEmptyValues[empty] ?? noneValue), 1);
        case FolderAnswer(:final subcategoryId):
          moveTo = subcategoryId;
      }
    }
    await app.items!.writeSidecarForItemId(item.id);
    if (moveTo != null) {
      await _clearApplied(item.id, 'folder:');
      if (moveTo != item.subcategoryId) {
        await app.items!.moveItemsToSubcategory([item], moveTo);
        await app.applyAutoTagsToItem(item.id, moveTo);
      }
      final sub = await app.categories!.getSubcategory(moveTo);
      final cat = sub == null ? null : await app.categories!.getCategory(sub.categoryId);
      if (sub != null && cat != null) await _feedback(item.id, folderLabel('${cat.name}/${sub.name}'), 1);
    }
  }

  // ── Training files ─────────────────────────────────────────────────────────

  /// Training/<Key>/<Value> for groups, Training/<Tag> for simple tags.
  Directory trainingDirFor({String? key, required String value}) =>
      Directory(key == null ? p.join(trainingDir.path, value) : p.join(trainingDir.path, key, value));

  static const mediaExts = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.mp4', '.mov', '.webm', '.mkv', '.m4v', '.avi'
  };

  int countTrainingFiles({String? key, required String value}) {
    final d = trainingDirFor(key: key, value: value);
    if (!d.existsSync()) return 0;
    return d
        .listSync()
        .whereType<File>()
        .where((f) => mediaExts.contains(p.extension(f.path).toLowerCase()) && !p.basename(f.path).startsWith('._'))
        .length;
  }

  /// Copies files into a training folder; returns how many were added.
  Future<int> addTrainingFiles({String? key, required String value, required List<String> paths}) async {
    final dir = trainingDirFor(key: key, value: value);
    await dir.create(recursive: true);
    var n = 0;
    for (final src in paths) {
      if (!mediaExts.contains(p.extension(src).toLowerCase())) continue;
      var dest = p.join(dir.path, p.basename(src));
      var i = 1;
      while (File(dest).existsSync()) {
        dest = p.join(dir.path, '${p.basenameWithoutExtension(src)} ($i)${p.extension(src)}');
        i++;
      }
      await File(src).copy(dest);
      n++;
    }
    return n;
  }
}
