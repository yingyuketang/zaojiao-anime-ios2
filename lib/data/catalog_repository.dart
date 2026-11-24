import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'models.dart';

/// 课程目录仓库：OSS 线上为唯一真相，本地仅断网缓存
class CatalogRepository {
  static const _cacheKey = 'cached_catalog_v2';

  Catalog? _cache;
  Catalog? get cache => _cache;

  Future<Catalog?> load() async {
    // 先给本地缓存（秒开），再拉线上覆盖
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached != null) {
      try {
        _cache = Catalog.fromJson(jsonDecode(cached));
      } catch (_) {}
    }
    try {
      final resp = await http
          .get(Uri.parse('${Config.catalogUrl}?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final body = utf8.decode(resp.bodyBytes);
        final catalog = Catalog.fromJson(jsonDecode(body));
        _cache = catalog;
        await prefs.setString(_cacheKey, body);
      }
    } catch (_) {
      // 断网用缓存
    }
    return _cache;
  }
}

/// 全局单例
final catalogRepository = CatalogRepository();
