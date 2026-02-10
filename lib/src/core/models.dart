class Category {
  final String id;
  final String name;
  Category({required this.id, required this.name});
}

class Subcategory {
  final String id;
  final String categoryId;
  final String name;
  Subcategory({required this.id, required this.categoryId, required this.name});
}

enum ItemType { video, image, other }

class MediaItem {
  final String id;
  final String subcategoryId;
  final ItemType type;
  final String originalName;
  final String storedRelPath; // relative to /Library/files
  final int sizeBytes;
  final String sha256;
  final DateTime createdAt;
  final bool isDuplicate;
  final String? duplicateOfId;

  MediaItem({
    required this.id,
    required this.subcategoryId,
    required this.type,
    required this.originalName,
    required this.storedRelPath,
    required this.sizeBytes,
    required this.sha256,
    required this.createdAt,
    required this.isDuplicate,
    required this.duplicateOfId,
  });
}

class Tag {
  final String id;
  final String name;
  Tag({required this.id, required this.name});
}

class Note {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });
}

class NoteAttachment {
  final String id;
  final String noteId;
  final String storedRelPath; // relative to /Library/attachments
  final String originalName;
  final String mime;
  final int sizeBytes;

  NoteAttachment({
    required this.id,
    required this.noteId,
    required this.storedRelPath,
    required this.originalName,
    required this.mime,
    required this.sizeBytes,
  });
}
