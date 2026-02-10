import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Note? selected;
  List<Note> notes = [];
  List<NoteAttachment> attachments = [];
  bool loading = false;

  final titleCtrl = TextEditingController();
  final contentCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    if (!app.isReady) return;
    setState(() => loading = true);
    notes = await app.notes!.listNotes();
    if (selected != null) {
      selected = notes.where((n) => n.id == selected!.id).cast<Note?>().firstOrNull;
      if (selected != null) {
        attachments = await app.notes!.listAttachments(selected!.id);
        titleCtrl.text = selected!.title;
        contentCtrl.text = selected!.content;
      }
    }
    setState(() => loading = false);
  }

  Future<void> _create() async {
    final name = await _prompt('Tytuł notatki');
    if (name == null || name.trim().isEmpty) return;
    final app = context.read<AppState>();
    selected = await app.notes!.createNote(name.trim());
    titleCtrl.text = selected!.title;
    contentCtrl.text = selected!.content;
    attachments = await app.notes!.listAttachments(selected!.id);
    setState(() {});
    await _reload();
  }

  Future<void> _save() async {
    if (selected == null) return;
    final app = context.read<AppState>();
    final now = DateTime.now();
    final updated = Note(
      id: selected!.id,
      title: titleCtrl.text.trim().isEmpty ? '(bez tytułu)' : titleCtrl.text.trim(),
      content: contentCtrl.text,
      createdAt: selected!.createdAt,
      updatedAt: now,
    );
    await app.notes!.updateNote(updated);
    selected = updated;
    await _reload();
  }

  Future<void> _delete() async {
    if (selected == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Usunąć notatkę?'),
        content: const Text('Notatka i jej obrazki zostaną usunięte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AppState>().notes!.deleteNote(selected!.id);
      selected = null;
      attachments = [];
      titleCtrl.clear();
      contentCtrl.clear();
      await _reload();
    }
  }

  Future<void> _addImage() async {
    if (selected == null) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty || res.files.first.path == null) return;
    final file = File(res.files.first.path!);
    final app = context.read<AppState>();
    await app.notes!.addAttachmentFromFile(selected!.id, file);
    attachments = await app.notes!.listAttachments(selected!.id);
    setState(() {});
  }

  Future<void> _removeAttachment(NoteAttachment a) async {
    final app = context.read<AppState>();
    await app.notes!.deleteAttachment(a.id);
    attachments = await app.notes!.listAttachments(selected!.id);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isReady) return const SizedBox.shrink();

    return Row(
      children: [
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(child: Text('Notatki', style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(onPressed: _create, icon: const Icon(Icons.add)),
                    IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: notes.length,
                        itemBuilder: (ctx, i) {
                          final n = notes[i];
                          return ListTile(
                            title: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(n.content.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis),
                            selected: selected?.id == n.id,
                            onTap: () async {
                              selected = n;
                              titleCtrl.text = n.title;
                              contentCtrl.text = n.content;
                              attachments = await app.notes!.listAttachments(n.id);
                              setState(() {});
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const Center(child: Text('Wybierz notatkę lub utwórz nową'))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: titleCtrl,
                              decoration: const InputDecoration(labelText: 'Tytuł'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text('Zapisz')),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(onPressed: _delete, icon: const Icon(Icons.delete), label: const Text('Usuń')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: TextField(
                          controller: contentCtrl,
                          maxLines: null,
                          expands: true,
                          decoration: const InputDecoration(
                            labelText: 'Treść',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text('Obrazki', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          OutlinedButton.icon(onPressed: _addImage, icon: const Icon(Icons.image), label: const Text('Dodaj')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 140,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: attachments.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (ctx, i) {
                            final a = attachments[i];
                            final path = p.join(app.paths!.attachmentsDir.path, a.storedRelPath);
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(File(path), width: 180, height: 140, fit: BoxFit.cover),
                                ),
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: IconButton(
                                    style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.5)),
                                    icon: const Icon(Icons.close, color: Colors.white),
                                    onPressed: () => _removeAttachment(a),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<String?> _prompt(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
