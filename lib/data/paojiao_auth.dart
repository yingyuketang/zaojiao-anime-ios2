import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// 激活状态
class ActivationState {
  final String card;
  final String token;
  final int expiresTs; // 秒
  final String cardType;
  final String deviceId;
  ActivationState({
    required this.card,
    required this.token,
    required this.expiresTs,
    this.cardType = '',
    this.deviceId = '',
  });

  bool get isValid =>
      card.isNotEmpty && token.isNotEmpty && expiresTs > _nowSec();

  Map<String, dynamic> toJson() => {
        'card': card,
        'token': token,
        'expiresTs': expiresTs,
        'cardType': cardType,
        'deviceId': deviceId,
      };

  factory ActivationState.fromJson(Map<String, dynamic> j) => ActivationState(
        card: (j['card'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        expiresTs: (j['expiresTs'] as num?)?.toInt() ?? 0,
        cardType: (j['cardType'] ?? '').toString(),
        deviceId: (j['deviceId'] ?? '').toString(),
      );
}

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// 泸椒云卡密验证客户端（签名规则：md5(METHOD+HOST+path+升序参数串+secret)）
class PaojiaoAuth {
  static const _prefsKey = 'activation_state';
  static const _deviceIdKey = 'device_id';

  final http.Client _client = http.Client();

  ActivationState? _state;
  ActivationState? get state => _state;
  final List<void Function(ActivationState?)> _listeners = [];

  void addListener(void Function(ActivationState?) fn) => _listeners.add(fn);

  void _notify() {
    for (final fn in _listeners) {
      fn(_state);
    }
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final s = ActivationState.fromJson(jsonDecode(raw));
        _state = s.isValid ? s : null;
      } catch (_) {}
    }
    _notify();
  }

  /// 设备号：安装后随机生成并持久化（双端通用）
  Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final rnd = Random.secure();
      id = List.generate(16, (_) => chars[rnd.nextInt(chars.length)]).join();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// 获取服务器时间（秒）：读响应 Date 头（客户端时钟偏差会导致 10013）
  Future<int> _serverTs() async {
    try {
      final resp =
          await _client.head(Uri.parse(Config.pjBaseUrl)).timeout(const Duration(seconds: 8));
      final date = resp.headers['date'];
      if (date != null) {
        return DateTime.parse(date).toUtc().millisecondsSinceEpoch ~/ 1000;
      }
    } catch (_) {}
    return _nowSec();
  }

  Future<(ActivationState?, String)> login(String card) async {
    try {
      final ts = await _serverTs();
      final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(32).padRight(16, '0').substring(0, 16);
      final params = <String, String>{
        'app_key': Config.pjAppKey,
        'card': card.trim(),
        'device_id': await deviceId(),
        'nonce': nonce,
        'timestamp': '$ts',
      };
      final resp = await _post('/v1/card/login', params);
      if (resp['code'] != 0) {
        final msg = (resp['message'] ?? '').toString();
        return (null, msg.isEmpty ? '验证失败（code=${resp['code']}）' : msg);
      }
      final result = resp['result'] as Map<String, dynamic>?;
      if (result == null) return (null, '服务器响应异常');
      final state = ActivationState(
        card: card.trim(),
        token: (result['token'] ?? '').toString(),
        expiresTs: (result['expires_ts'] as num?)?.toInt() ?? 0,
        cardType: (result['card_type'] ?? '').toString(),
        deviceId: await deviceId(),
      );
      await _save(state);
      return (state, '');
    } catch (e) {
      return (null, '网络异常，请检查网络后重试');
    }
  }

  /// 心跳：刷新 token、校验顶号/过期。失败返回原因（已自动清状态）
  Future<(bool, String)> heartbeat() async {
    final state = _state;
    if (state == null) return (false, '未激活');
    try {
      final ts = await _serverTs();
      final params = <String, String>{
        'app_key': Config.pjAppKey,
        'card': state.card,
        'nonce': DateTime.now().microsecondsSinceEpoch.toRadixString(32)
            .padRight(16, '0')
            .substring(0, 16),
        'timestamp': '$ts',
        'token': state.token,
      };
      final resp = await _post('/v1/card/heartbeat', params);
      if (resp['code'] != 0) {
        await logout(notifyServer: false);
        final msg = (resp['message'] ?? '').toString();
        return (false, msg.isEmpty ? '登录状态已失效' : msg);
      }
      final result = resp['result'] as Map<String, dynamic>?;
      final newExp = (result?['expires_ts'] as num?)?.toInt() ?? 0;
      if (newExp > 0) {
        final updated = ActivationState(
          card: state.card,
          token: state.token,
          expiresTs: newExp,
          cardType: state.cardType,
          deviceId: state.deviceId,
        );
        await _save(updated);
      }
      return (true, '');
    } catch (_) {
      return (false, '网络异常');
    }
  }

  Future<void> logout({bool notifyServer = true}) async {
    final state = _state;
    if (notifyServer && state != null) {
      try {
        final ts = await _serverTs();
        await _post('/v1/card/logout', {
          'app_key': Config.pjAppKey,
          'card': state.card,
          'nonce': DateTime.now().microsecondsSinceEpoch.toRadixString(32)
              .padRight(16, '0')
              .substring(0, 16),
          'timestamp': '$ts',
          'token': state.token,
        });
      } catch (_) {}
    }
    _state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _notify();
  }

  Future<void> _save(ActivationState s) async {
    _state = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
    _notify();
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, String> params) async {
    final sorted = params.keys.toList()..sort();
    final query = sorted.map((k) => '$k=${params[k]}').join('&');
    final sign =
        md5.convert(utf8.encode('POST${Config.pjHost}$path$query${Config.pjAppSecret}')).toString();
    final resp = await _client
        .post(
          Uri.parse('${Config.pjBaseUrl}$path'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: [...params.entries.map((e) => '${e.key}=${e.value}'), 'sign=$sign'].join('&'),
        )
        .timeout(const Duration(seconds: 15));
    final body = utf8.decode(resp.bodyBytes);
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return {'code': -1, 'message': '服务器响应异常'};
    }
  }
}

final paojiaoAuth = PaojiaoAuth();
