/// One chapter in the on-disk index. Body lives in `chapters/{file}`.
class ChapterIndexEntry {
  const ChapterIndexEntry({
    required this.index,
    required this.title,
    required this.file,
    required this.charCount,
  });

  final int index;
  final String title;

  /// Relative filename under `chapters/`, e.g. `0000.txt`.
  final String file;

  /// Character count (Dart [String.length]) of the chapter file.
  final int charCount;

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'file': file,
        'charCount': charCount,
      };

  factory ChapterIndexEntry.fromJson(Map<String, dynamic> json) {
    final index = json['index'] as int;
    return ChapterIndexEntry(
      index: index,
      title: json['title'] as String,
      file: json['file'] as String? ??
          '${index.toString().padLeft(4, '0')}.txt',
      charCount: json['charCount'] as int? ?? 0,
    );
  }

  ChapterIndexEntry copyWith({
    String? title,
    String? file,
    int? charCount,
  }) {
    return ChapterIndexEntry(
      index: index,
      title: title ?? this.title,
      file: file ?? this.file,
      charCount: charCount ?? this.charCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterIndexEntry &&
          index == other.index &&
          title == other.title &&
          file == other.file &&
          charCount == other.charCount;

  @override
  int get hashCode => Object.hash(index, title, file, charCount);
}

/// Full chapter index for a novel.
class ChapterIndex {
  const ChapterIndex(this.chapters);

  final List<ChapterIndexEntry> chapters;

  int get length => chapters.length;

  int get totalChars => chapters.fold(0, (s, c) => s + c.charCount);

  ChapterIndexEntry? operator [](int i) =>
      (i >= 0 && i < chapters.length) ? chapters[i] : null;

  Map<String, dynamic> toJson() => {
        'version': 2,
        'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  factory ChapterIndex.fromJson(Map<String, dynamic> json) {
    final raw = json['chapters'] as List<dynamic>? ?? const [];
    return ChapterIndex(
      raw
          .map((e) => ChapterIndexEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One chapter body produced by [ChapterSplitter].
class SplitChapter {
  const SplitChapter({required this.title, required this.content});

  final String title;
  final String content;
}
