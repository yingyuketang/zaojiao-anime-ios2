/// 课程目录数据模型（与 OSS catalog.json 结构对应）
class Quality {
  final String label;
  final String url;
  final int height;
  Quality({required this.label, required this.url, required this.height});

  factory Quality.fromJson(Map<String, dynamic> j) => Quality(
        label: (j['label'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        height: (j['height'] as num?)?.toInt() ?? 0,
      );
}

class VideoItem {
  final String id;
  final String title;
  final String description;
  final int durationSec;
  final String cover;
  final bool hidden;
  final List<Quality> qualities;

  VideoItem({
    required this.id,
    required this.title,
    this.description = '',
    this.durationSec = 0,
    this.cover = '',
    this.hidden = false,
    this.qualities = const [],
  });

  /// 默认清晰度（分辨率最高的一档；height 缺失时从 label 解析，如 "1080p"）
  int get defaultQualityIndex {
    var best = 0;
    var bestH = -1;
    for (var i = 0; i < qualities.length; i++) {
      final m = RegExp(r'(\d{3,4})').firstMatch(qualities[i].label);
      final h = int.tryParse(m?.group(1) ?? '') ?? qualities[i].height;
      if (h > bestH) {
        bestH = h;
        best = i;
      }
    }
    return best;
  }

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        cover: (j['cover'] ?? '').toString(),
        hidden: j['hidden'] == true,
        qualities: (j['qualities'] as List<dynamic>? ?? [])
            .map((e) => Quality.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Unit {
  final String id;
  final String title;
  final List<VideoItem> videos;
  Unit({required this.id, required this.title, required this.videos});

  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        videos: (j['videos'] as List<dynamic>? ?? [])
            .map((e) => VideoItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Grade {
  final String id;
  final List<Unit> units;
  Grade({required this.id, required this.units});

  factory Grade.fromJson(Map<String, dynamic> j) => Grade(
        id: (j['id'] ?? '').toString(),
        units: (j['units'] as List<dynamic>? ?? [])
            .map((e) => Unit.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Subject {
  final String id;
  final String name;
  final List<Grade> grades;
  Subject({required this.id, required this.name, required this.grades});

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        grades: (j['grades'] as List<dynamic>? ?? [])
            .map((e) => Grade.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class Catalog {
  final int version;
  final List<Subject> subjects;
  Catalog({required this.version, required this.subjects});

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        version: (j['version'] as num?)?.toInt() ?? 0,
        subjects: (j['subjects'] as List<dynamic>? ?? [])
            .map((e) => Subject.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// 播放进度
class VideoProgress {
  final int positionMs;
  final int durationMs;
  final bool completed;
  final int updatedAt;
  VideoProgress({
    required this.positionMs,
    required this.durationMs,
    required this.completed,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'completed': completed,
        'updatedAt': updatedAt,
      };

  factory VideoProgress.fromJson(Map<String, dynamic> j) => VideoProgress(
        positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        completed: j['completed'] == true,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}
