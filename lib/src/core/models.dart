class Category {
  final String id;
  final String name;
  final String description;
  final int sortOrder;
  Category({required this.id, required this.name, this.description = '', this.sortOrder = 0});
}

class Subcategory {
  final String id;
  final String categoryId;
  final String name;
  final String description;
  final int sortOrder;
  Subcategory({required this.id, required this.categoryId, required this.name, this.description = '', this.sortOrder = 0});
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
  final bool isFavourite;

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
    this.isFavourite = false,
  });

  MediaItem copyWith({bool? isFavourite}) {
    return MediaItem(
      id: id,
      subcategoryId: subcategoryId,
      type: type,
      originalName: originalName,
      storedRelPath: storedRelPath,
      sizeBytes: sizeBytes,
      sha256: sha256,
      createdAt: createdAt,
      isDuplicate: isDuplicate,
      duplicateOfId: duplicateOfId,
      isFavourite: isFavourite ?? this.isFavourite,
    );
  }
}

class Tag {
  final String id;
  final String name;
  final String description;
  final int sortOrder;
  Tag({required this.id, required this.name, this.description = '', this.sortOrder = 0});
}

class TagKey {
  final String id;
  final String key;
  final DateTime createdAt;
  final String description;
  final int sortOrder;
  TagKey({
    required this.id,
    required this.key,
    required this.createdAt,
    this.description = '',
    this.sortOrder = 0,
  });
}

class TagKeyValue {
  final String id;
  final String keyId;
  final String key;
  final String value;
  final String description;
  final DateTime createdAt;
  TagKeyValue({
    required this.id,
    required this.keyId,
    required this.key,
    required this.value,
    this.description = '',
    required this.createdAt,
  });
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
