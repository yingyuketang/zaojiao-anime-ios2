import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// 播放进度（本机存储，距结尾 3 秒内记为学完）
class ProgressStore {
  static const _key = 'progress_map';
  Map<String, VideoProgress> _map = {};
  final List<void Function()> _listeners = [];

  Map<String, VideoProgress> get map => _map;

  void addListener(void Function() fn) => _listeners.add(fn);

  void removeListener(void Function() fn) => _listeners.remove(fn);

  void _notify() {
    for (final fn in _listeners) {
      fn();
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _map = j.map((k, v) => MapEntry(
            k, VideoProgress.fromJson(Map<String, dynamic>.from(v))));
      } catch (_) {}
    }
    _notify();
  }

  VideoProgress? get(String videoId) => _map[videoId];

  Future<void> save(
      String videoId, int positionMs, int durationMs) async {
    final completed = durationMs > 0 && positionMs >= durationMs - 3000;
    _map[videoId] = VideoProgress(
      positionMs: positionMs,
      durationMs: durationMs,
      completed: completed || (_map[videoId]?.completed ?? false),
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _persist();
    _notify();
  }

  Future<void> markCompleted(String videoId) async {
    final old = _map[videoId];
    _map[videoId] = VideoProgress(
      positionMs: old?.positionMs ?? 0,
      durationMs: old?.durationMs ?? 0,
      completed: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _persist();
    _notify();
  }

  Future<void> clearAll() async {
    _map = {};
    await _persist();
    _notify();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_map.map((k, v) => MapEntry(k, v.toJson()))));
  }
}

final progressStore = ProgressStore();
