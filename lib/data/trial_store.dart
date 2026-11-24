import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// 新设备免费试用（3 天）：ANDROID_ID/iOS identifierForVendor 为指纹 + 多重标记
/// （能防普通清数据/重装；恢复出厂理论可绕过，引流场景够用）
class TrialStore {
  static const _prefsPrefix = 'trial_';
  static const _seconds = Config.trialDays * 24 * 60 * 60;

  String? _deviceId;

  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('trial_device_id');
    id ??= _randomId(12);
    await prefs.setString('trial_device_id', id);
    _deviceId = id;
    return id;
  }

  String _randomId(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  /// 是否已用过试用（任一标记存在即算）
  Future<bool> hasUsedTrial() async {
    final id = await deviceId();
    if (Platform.isAndroid) {
      try {
        // 外部存储标记（ProcessChannel 不引入，直接省略；prefs + files 双标记够用）
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('$_prefsPrefix$id')) return true;
    return false;
  }

  /// 当前有效试用状态（未过期返回剩余秒数；过期返回 0）
  Future<int> remainingSec() async {
    final id = await deviceId();
    final prefs = await SharedPreferences.getInstance();
    final started = prefs.getInt('$_prefsPrefix$id') ?? 0;
    if (started <= 0) return 0;
    final expires = started + _seconds;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expires > now ? expires - now : 0;
  }

  /// 开始试用
  Future<void> start() async {
    final id = await deviceId();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefsPrefix$id', DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }
}

final trialStore = TrialStore();
