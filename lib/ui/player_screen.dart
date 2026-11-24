import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../data/models.dart';
import '../data/progress_store.dart';
import 'home_screen.dart' show VideoContext;
import 'theme.dart';

/// 播放页：竖屏（16:9 预览 + 剧集列表）/ 全屏（横屏沉浸）
/// 播放内核 media_kit（mpv）：EMUI 设备解码兼容性好，iOS/Android 同一套代码
class PlayerScreen extends StatefulWidget {
  final VideoContext vc;
  final VoidCallback onBack;
  final void Function(VideoContext next) onPlayVideo;
  const PlayerScreen({
    super.key,
    required this.vc,
    required this.onBack,
    required this.onPlayVideo,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player =
      Player(configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
  late final VideoController _videoController = VideoController(
    _player,
    configuration:
        const VideoControllerConfiguration(enableHardwareAcceleration: true),
  );
  final List<StreamSubscription> _subs = [];
  bool _controls = true;
  bool _fullscreen = false;
  bool _locked = false;
  bool _showUnlock = false;
  Timer? _unlockTimer;
  bool _ended = false;
  bool _buffering = true;
  int _qualityIndex = 0;
  int _speedIndex = 0;
  bool _loopOne = false;
  String? _error;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _seeking = false;
  double _seekValue = 0;

  static const _speeds = [1.0, 1.25, 1.5, 0.8];

  VideoItem get _video => widget.vc.video;

  VideoItem? get _next {
    final visible = widget.vc.unit.videos.where((v) => !v.hidden).toList();
    final i = visible.indexWhere((v) => v.id == _video.id);
    if (i >= 0 && i + 1 < visible.length) return visible[i + 1];
    return null;
  }

  @override
  void initState() {
    super.initState();
    _qualityIndex = _video.defaultQualityIndex;
    _listenPlayer();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initPlayer();
  }

  void _listenPlayer() {
    _subs.add(_player.stream.position.listen((d) {
      if (!mounted) return;
      final ms = d.inMilliseconds;
      setState(() => _positionMs = ms);
      if (_player.state.playing &&
          ms ~/ 5000 != (ms - 200).clamp(0, 1 << 30) ~/ 5000) {
        progressStore.save(_video.id, ms, _player.state.duration.inMilliseconds);
      }
    }));
    _subs.add(_player.stream.duration.listen((d) {
      if (mounted) setState(() => _durationMs = d.inMilliseconds);
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (!mounted) return;
      setState(() => _ended = done);
      if (done) progressStore.markCompleted(_video.id);
    }));
    _subs.add(_player.stream.buffering.listen((b) {
      if (mounted) setState(() => _buffering = b);
    }));
    _subs.add(_player.stream.error.listen((e) {
      debugPrint('[Player] stream error: $e');
    }));
  }

  Future<void> _initPlayer({int startMs = 0}) async {
    final url = _video.qualities.isNotEmpty
        ? _video.qualities[_qualityIndex.clamp(0, _video.qualities.length - 1)].url
        : '';
    debugPrint('[Player] open $url');
    if (url.isEmpty) {
      setState(() => _error = '这个视频还没有上传完成');
      return;
    }
    setState(() {
      _error = null;
      _ended = false;
    });
    try {
      await _player.open(Media(url), play: false);
      if (startMs > 0) {
        await _player.seek(Duration(milliseconds: startMs));
      } else {
        final saved = progressStore.get(_video.id);
        if (saved != null && !saved.completed && saved.positionMs > 0) {
          await _player.seek(Duration(milliseconds: saved.positionMs));
        }
      }
      await _player.setRate(_speeds[_speedIndex]);
      await _player.setPlaylistMode(
          _loopOne ? PlaylistMode.single : PlaylistMode.none);
      await _player.play();
      debugPrint('[Player] opened & playing');
    } catch (e) {
      debugPrint('[Player] open failed: $e');
      if (mounted) setState(() => _error = '视频加载失败，点屏幕重试');
    }
  }

  Future<void> _switchQuality(int idx) async {
    final posMs = _player.state.position.inMilliseconds;
    setState(() {
      _qualityIndex = idx;
      _controls = true;
    });
    await _initPlayer(startMs: posMs);
  }

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    if (on) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _togglePlay() async {
    if (_ended) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    setState(() {});
  }

  void _saveNow() {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (dur > Duration.zero) {
      progressStore.save(_video.id, pos.inMilliseconds, dur.inMilliseconds);
    }
  }

  @override
  void dispose() {
    _saveNow();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fullscreen ? Colors.black : AppTheme.windowBackground,
      body: SafeArea(
        top: !_fullscreen,
        bottom: !_fullscreen,
        child: _fullscreen
            ? _videoArea(const BoxConstraints.expand())
            : Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: _videoArea(const BoxConstraints.expand()),
                    ),
                  ),
                  Expanded(child: _episodePanel()),
                ],
              ),
      ),
    );
  }

  Widget _videoArea(BoxConstraints constraints) {
    return GestureDetector(
      onTap: () {
        if (_locked) {
          // 锁定时：点一下显示解锁按钮，3 秒后自动消失
          setState(() => _showUnlock = true);
          _unlockTimer?.cancel();
          _unlockTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _showUnlock = false);
          });
          return;
        }
        setState(() => _controls = !_controls);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: _videoController,
            controls: NoVideoControls,
          ),
          if (_buffering && !_ended && _error == null)
            const Center(
                child: CircularProgressIndicator(color: AppTheme.brandGreen)),
          if (_error != null)
            Center(
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
          if (!_locked)
            _controlsOverlay()
          else ...[
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Icon(Icons.lock, color: Colors.white54, size: 20),
              ),
            ),
            // 解锁浮层：3 秒内点击即可解锁
            if (_showUnlock)
              Center(
                child: GestureDetector(
                  onTap: () {
                    _unlockTimer?.cancel();
                    setState(() {
                      _locked = false;
                      _showUnlock = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0x88000000),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.lock_open, color: Colors.white, size: 30),
                        SizedBox(height: 6),
                        Text('点击解锁',
                            style: TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _controlsOverlay() {
    if (!_controls && !_ended) return const SizedBox.shrink();
    return Stack(
      children: [
        // 顶部栏
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            color: Colors.black54,
            padding: EdgeInsets.only(
                top: _fullscreen ? 8 : 2, left: 4, right: 4, bottom: 2),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (_fullscreen) {
                      _setFullscreen(false);
                    } else {
                      widget.onBack();
                    }
                  },
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    _video.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('投屏功能即将上线，敬请期待～')),
                    );
                  },
                  icon: const Icon(Icons.cast, color: Colors.white),
                ),
                IconButton(
                  onPressed: () => setState(() => _locked = true),
                  icon: const Icon(Icons.lock_outline, color: Colors.white),
                ),
                IconButton(
                  onPressed: () => _setFullscreen(!_fullscreen),
                  icon: Icon(
                    _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        // 底部栏
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            color: Colors.black54,
            padding: EdgeInsets.only(
                bottom: _fullscreen ? 10 : 2, left: 12, right: 12, top: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: const Color(0xFF4CD07A),
                    inactiveTrackColor: const Color(0x66FFFFFF),
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _seeking
                        ? _seekValue
                        : (_durationMs > 0
                            ? (_positionMs / _durationMs).clamp(0.0, 1.0)
                            : 0.0),
                    onChanged: (v) {
                      setState(() {
                        _seeking = true;
                        _seekValue = v;
                      });
                    },
                    onChangeEnd: (v) {
                      _seeking = false;
                      final target = (v * _durationMs).round();
                      _player.seek(Duration(milliseconds: target));
                    },
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _togglePlay,
                      icon: Icon(
                        _ended
                            ? Icons.replay
                            : (_player.state.playing
                                ? Icons.pause
                                : Icons.play_arrow),
                        color: Colors.white,
                      ),
                    ),
                    Text('${formatDuration(_positionMs)} / ${formatDuration(_durationMs)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        _speedIndex = (_speedIndex + 1) % _speeds.length;
                        _player.setRate(_speeds[_speedIndex]);
                        setState(() {});
                      },
                      child: Text('${_speeds[_speedIndex]}x',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _speeds[_speedIndex] == 1.0
                                  ? Colors.white
                                  : const Color(0xFF7BE3A2))),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: _showQualitySheet,
                      child: Text(_qualityLabel(),
                          style: const TextStyle(
                              fontSize: 14, color: Colors.white)),
                    ),
                    const SizedBox(width: 14),
                    GestureDetector(
                      onTap: () {
                        _loopOne = !_loopOne;
                        _player.setPlaylistMode(
                            _loopOne ? PlaylistMode.single : PlaylistMode.none);
                        setState(() {});
                      },
                      child: Icon(
                        _loopOne ? Icons.repeat_one : Icons.repeat,
                        color: _loopOne
                            ? const Color(0xFF7BE3A2)
                            : Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    IconButton(
                      onPressed: _next == null
                          ? null
                          : () => widget.onPlayVideo(VideoContext(
                              widget.vc.subject, widget.vc.unit, _next!)),
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _qualityLabel() =>
      _video.qualities.isNotEmpty
          ? _video.qualities[_qualityIndex.clamp(0, _video.qualities.length - 1)].label
          : '1080p';

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('清晰度',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (var i = 0; i < _video.qualities.length; i++)
              ListTile(
                leading: Icon(
                  i == _qualityIndex ? Icons.check_circle : Icons.circle_outlined,
                  color: i == _qualityIndex ? AppTheme.brandGreen : Colors.grey,
                ),
                title: Text(_video.qualities[i].label),
                onTap: () {
                  Navigator.pop(context);
                  _switchQuality(i);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _episodePanel() {
    final unit = widget.vc.unit;
    final visible = unit.videos.where((v) => !v.hidden).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(_video.title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('${widget.vc.subject.name} · ${unit.title}',
              style: const TextStyle(fontSize: 12, color: AppTheme.warmGray)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFFFFF3E9),
          child: Text('剧集（${visible.length} 集）',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final item = visible[i];
              final isCurrent = item.id == _video.id;
              final p = progressStore.get(item.id);
              return GestureDetector(
                onTap: isCurrent
                    ? null
                    : () => widget.onPlayVideo(
                        VideoContext(widget.vc.subject, unit, item)),
                child: Container(
                  color: isCurrent
                      ? const Color(0xFFDCF3E4)
                      : Colors.transparent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isCurrent
                                ? AppTheme.brandGreen
                                : Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                )),
                            if (isCurrent)
                              const Text('正在播放',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.brandGreen))
                            else if (p?.completed ?? false)
                              const Text('✓ 看完啦',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.greenDeep)),
                          ],
                        ),
                      ),
                      if (item.durationSec > 0)
                        Text(formatSeconds(item.durationSec),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
