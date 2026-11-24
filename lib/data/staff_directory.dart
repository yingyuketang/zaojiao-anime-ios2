import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class StaffEntry {
  final String code;
  final String name;
  final String wechat;
  StaffEntry({required this.code, required this.name, required this.wechat});

  factory StaffEntry.fromJson(Map<String, dynamic> j) => StaffEntry(
        code: (j['code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        wechat: (j['wechat'] ?? '').toString(),
      );
}

class StaffConfig {
  final StaffEntry def;
  final List<StaffEntry> staff;
  StaffConfig({required this.def, required this.staff});

  factory StaffConfig.fallback() => StaffConfig(
        def: StaffEntry(code: '', name: '老师', wechat: Config.defaultWechat),
        staff: [],
      );

  /// 按员工码取微信号：未填/未命中一律回退默认
  String wechatFor(String rawCode) {
    final c = rawCode.trim().toUpperCase();
    if (c.isNotEmpty) {
      for (final s in staff) {
        if (s.code.trim().toUpperCase() == c && s.wechat.isNotEmpty) return s.wechat;
      }
    }
    return def.wechat.isEmpty ? Config.defaultWechat : def.wechat;
  }

  String nameFor(String rawCode) {
    final c = rawCode.trim().toUpperCase();
    if (c.isEmpty) return def.name;
    for (final s in staff) {
      if (s.code.trim().toUpperCase() == c) return s.name;
    }
    return '';
  }

  bool isValidCode(String rawCode) {
    final c = rawCode.trim().toUpperCase();
    if (c.isEmpty) return false;
    return staff.any((s) => s.code.trim().toUpperCase() == c);
  }
}

/// 员工表（OSS app/staff.json）：改微信云端即时生效
class StaffDirectory {
  static const _diskKey = 'cached_staff_v1';
  StaffConfig _config = StaffConfig.fallback();
  StaffConfig get config => _config;

  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_diskKey);
    if (cached != null) {
      try {
        _config = _parse(cached);
      } catch (_) {}
    }
    try {
      final resp = await http
          .get(Uri.parse('${Config.staffUrl}?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = utf8.decode(resp.bodyBytes);
        final cfg = _parse(body);
        _config = cfg;
        await prefs.setString(_diskKey, body);
        debugPrint('[Staff] ok: staff=${cfg.staff.length}, default=${cfg.def.wechat}');
      } else {
        debugPrint('[Staff] http ${resp.statusCode}');
      }
    } catch (e) {
      debugPrint('[Staff] fetch failed: $e');
      // 失败用缓存/默认
    }
  }

  StaffConfig _parse(String body) {
    final j = jsonDecode(body) as Map<String, dynamic>;
    return StaffConfig(
      def: StaffEntry.fromJson(Map<String, dynamic>.from(j['default'] ?? {})),
      staff: (j['staff'] as List<dynamic>? ?? [])
          .map((e) => StaffEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

final staffDirectory = StaffDirectory();
