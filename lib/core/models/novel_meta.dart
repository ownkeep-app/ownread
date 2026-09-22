/// Lightweight novel metadata shown on the library list and stored in meta.json.
class NovelMeta {
  const NovelMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.chapterCount,
    required this.totalChars,
    required this.editedChars,
    required this.progressChapterIndex,
    required this.progressFractionInChapter,
    this.sourceFileName,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int chapterCount;
  final int totalChars;

  /// Cumulative absolute characters changed across edit history.
  final int editedChars;

  /// Last reading chapter index (0-based).
  final int progressChapterIndex;

  /// 0.0–1.0 scroll fraction within the current chapter viewport aggregate.
  final double progressFractionInChapter;

  final String? sourceFileName;

  /// Overall reading progress 0.0–1.0 across the whole book.
  double get readingProgress {
    if (chapterCount <= 0) return 0;
    final base = progressChapterIndex / chapterCount;
    final within = (progressFractionInChapter.clamp(0.0, 1.0)) / chapterCount;
    return (base + within).clamp(0.0, 1.0);
  }

  NovelMeta copyWith({
    String? title,
    DateTime? updatedAt,
    int? chapterCount,
    int? totalChars,
    int? editedChars,
    int? progressChapterIndex,
    double? progressFractionInChapter,
    String? sourceFileName,
  }) {
    return NovelMeta(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      chapterCount: chapterCount ?? this.chapterCount,
      totalChars: totalChars ?? this.totalChars,
      editedChars: editedChars ?? this.editedChars,
      progressChapterIndex: progressChapterIndex ?? this.progressChapterIndex,
      progressFractionInChapter:
          progressFractionInChapter ?? this.progressFractionInChapter,
      sourceFileName: sourceFileName ?? this.sourceFileName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'chapterCount': chapterCount,
        'totalChars': totalChars,
        'editedChars': editedChars,
        'progressChapterIndex': progressChapterIndex,
        'progressFractionInChapter': progressFractionInChapter,
        if (sourceFileName != null) 'sourceFileName': sourceFileName,
      };

  factory NovelMeta.fromJson(Map<String, dynamic> json) {
    return NovelMeta(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      chapterCount: json['chapterCount'] as int? ?? 0,
      totalChars: json['totalChars'] as int? ?? 0,
      editedChars: json['editedChars'] as int? ?? 0,
      progressChapterIndex: json['progressChapterIndex'] as int? ?? 0,
      progressFractionInChapter:
          (json['progressFractionInChapter'] as num?)?.toDouble() ?? 0,
      sourceFileName: json['sourceFileName'] as String?,
    );
  }
}

enum NovelSortBy { updatedAt, title, progress, totalChars }

extension NovelSortByLabel on NovelSortBy {
  String get label => switch (this) {
        NovelSortBy.updatedAt => '最近阅读',
        NovelSortBy.title => '书名',
        NovelSortBy.progress => '阅读进度',
        NovelSortBy.totalChars => '字数',
      };
}
