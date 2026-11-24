import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'data/catalog_repository.dart';
import 'data/paojiao_auth.dart';
import 'data/progress_store.dart';
import 'data/staff_directory.dart';
import 'data/trial_store.dart';
import 'ui/activate_screen.dart';
import 'ui/home_screen.dart';
import 'ui/mine_screen.dart';
import 'ui/player_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ZaojiaoApp());
}

class ZaojiaoApp extends StatelessWidget {
  const ZaojiaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '早教动画课堂',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: const RootGate(),
    );
  }
}

/// 门禁：未激活（无卡密且无试用）→ 激活页；已激活 → 主页
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _ready = false;
  bool _activated = false;
  bool _trialValid = false;
  String? _heartbeatFail;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await paojiaoAuth.init();
    await progressStore.init();
    await catalogRepository.load();
    await staffDirectory.refresh();

    // 试用期校验
    final remaining = await trialStore.remainingSec();
    final trialValid = remaining > 0;

    // 已有卡密：心跳校验（过期/被顶号 → 回激活页）
    if (paojiaoAuth.state != null) {
      final (ok, msg) = await paojiaoAuth.heartbeat();
      if (!ok) {
        setState(() {
          _heartbeatFail = msg;
          _activated = false;
          _trialValid = trialValid;
          _ready = true;
        });
        return;
      }
    }

    setState(() {
      _trialValid = trialValid;
      _activated = paojiaoAuth.state != null;
      _ready = true;
    });
  }

  void _onActivated() {
    setState(() => _activated = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.brandGreen)),
      );
    }
    if (!_activated && !_trialValid) {
      return ActivateScreen(onActivated: _onActivated);
    }
    return _MainTabs(heartbeatFail: _heartbeatFail);
  }
}

/// 主页：底部导航（课程 / 我的）+ 播放页全屏路由
class _MainTabs extends StatefulWidget {
  final String? heartbeatFail;
  const _MainTabs({this.heartbeatFail});

  @override
  State<_MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<_MainTabs> {
  int _tab = 0;
  bool _tipShown = false;

  void _play(VideoContext vc) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          vc: vc,
          onBack: () => Navigator.of(context).pop(),
          onPlayVideo: _playReplace,
        ),
      ),
    );
  }

  /// 换集：替换当前页，避免返回栈越叠越长
  void _playReplace(VideoContext next) {
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          vc: next,
          onBack: () => Navigator.of(context).pop(),
          onPlayVideo: _playReplace,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.heartbeatFail != null && !_tipShown) {
        _tipShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('登录状态已失效：${widget.heartbeatFail}，请重新激活'),
              backgroundColor: const Color(0xFFC62828)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Offstage(
            offstage: _tab != 0,
            child: HomeScreen(onPlayVideo: _play),
          ),
          Offstage(
            offstage: _tab != 1,
            child: MineScreen(onPlayVideo: _play),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.pinkContainer,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: '课程'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
        ],
      ),
    );
  }
}
