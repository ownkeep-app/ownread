/// One row in the novel's modification history.
class EditHistoryEntry {
  const EditHistoryEntry({
    required this.id,
    required this.createdAt,
    required this.summary,
    required this.changedChars,
    required this.kind,
    this.chapterIndex,
  });

  final String id;
  final DateTime createdAt;

  /// Human-readable summary, e.g.
  /// `全文替换：'18岁' -> '14岁'；共计修改文本400字`
  final String summary;

  /// Absolute number of characters affected (inserted + deleted magnitude).
  final int changedChars;

  /// `replace_all` | `chapter_edit`
  final String kind;

  final int? chapterIndex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'summary': summary,
        'changedChars': changedChars,
        'kind': kind,
        if (chapterIndex != null) 'chapterIndex': chapterIndex,
      };

  factory EditHistoryEntry.fromJson(Map<String, dynamic> json) {
    return EditHistoryEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      summary: json['summary'] as String,
      changedChars: json['changedChars'] as int,
      kind: json['kind'] as String,
      chapterIndex: json['chapterIndex'] as int?,
    );
  }

  /// Build a Chinese summary for a full-text find/replace.
  static String summaryReplaceAll({
    required String find,
    required String replace,
    required int changedChars,
  }) {
    return "全文替换：'$find' -> '$replace'；共计修改文本$changedChars字";
  }

  /// Build a Chinese summary for an in-place chapter edit.
  static String summaryChapterEdit({
    required int chapterNumber1Based,
    required String? sampleFrom,
    required String? sampleTo,
    required int changedChars,
  }) {
    final sample = (sampleFrom != null && sampleTo != null)
        ? "：'$sampleFrom' -> '$sampleTo'"
        : '';
    return '第$chapterNumber1Based章修改文本$sample；共计修改文本$changedChars字';
  }
}
