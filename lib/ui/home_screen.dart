import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../data/catalog_repository.dart';
import '../data/models.dart';
import '../data/progress_store.dart';
import 'theme.dart';

class VideoContext {
  final Subject subject;
  final Unit unit;
  final VideoItem video;
  VideoContext(this.subject, this.unit, this.video);
}

/// 找"继续学习"的一集：当前类目下最近观看的
VideoContext? findContinueVideo(
    Catalog catalog, Map<String, VideoProgress> progress, String subjectId) {
  final subject = catalog.subjects.firstWhere(
    (s) => s.id == subjectId,
    orElse: () => catalog.subjects.first,
  );
  final entries = progress.entries
      .where((e) => e.value.updatedAt > 0)
      .toList()
    ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
  for (final e in entries) {
    for (final g in subject.grades) {
      for (final u in g.units) {
        for (final v in u.videos) {
          if (v.id == e.key && !v.hidden) {
            return VideoContext(subject, u, v);
          }
        }
      }
    }
  }
  return null;
}

/// 首页：类目药丸 + 合集胶囊 + 继续学习 + 课程列表
class HomeScreen extends StatefulWidget {
  final void Function(VideoContext vc) onPlayVideo;
  const HomeScreen({super.key, required this.onPlayVideo});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Catalog? _catalog;
  bool _loading = true;
  String? _error;
  String _subjectId = '';
  String _selectedUnitId = '';
  Map<String, VideoProgress> _progress = {};
  int _reloadTick = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    progressStore.addListener(_onProgressChanged);
  }

  @override
  void dispose() {
    progressStore.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onProgressChanged() {
    if (mounted) setState(() => _progress = progressStore.map);
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final catalog = await catalogRepository.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _catalog = catalog;
      _progress = progressStore.map;
      _reloadTick++;
      if (catalog != null && catalog.subjects.isNotEmpty) {
        _subjectId = catalog.subjects.first.id;
        _selectedUnitId = '';
      }
      if (catalog == null) {
        _error = '课程目录加载失败，请检查网络';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (_loading)
              const Expanded(
                  child: Center(
                      child: CircularProgressIndicator(color: AppTheme.brandGreen)))
            else if (_error != null)
              Expanded(child: _errorPane())
            else
              Expanded(child: _readyPane()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
                color: Color(0xFFDCF3E4), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('🐰', style: TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('早教动画课堂',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                Text('今天也一起快乐学习吧～',
                    style: TextStyle(fontSize: 12, color: AppTheme.warmGray)),
              ],
            ),
          ),
          IconButton(
            onPressed: _reload,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, color: AppTheme.warmGray),
          ),
        ],
      ),
    );
  }

  Widget _errorPane() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('哎呀，加载失败了',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(_error ?? '', style: const TextStyle(color: AppTheme.warmGray)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _reload,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.brandGreen),
            child: const Text('再试一次'),
          ),
        ],
      ),
    );
  }

  Widget _readyPane() {
    final catalog = _catalog!;
    final subjects = catalog.subjects;
    if (subjects.isEmpty) {
      return const Center(child: Text('🌱 课程目录是空的'));
    }
    final subject = subjects.firstWhere(
      (s) => s.id == _subjectId,
      orElse: () => subjects.first,
    );
    final grade = subject.grades.isNotEmpty ? subject.grades.first : null;
    final units = grade?.units ?? <Unit>[];
    final activeUnit = units
        .where((u) => u.id == _selectedUnitId)
        .toList()
        .firstOrNull;
    final continueVc = findContinueVideo(catalog, _progress, subject.id);

    final items = <Widget>[];
    if (continueVc != null) {
      items.add(_continueCard(continueVc));
    }

    final shownUnits = activeUnit != null ? [activeUnit] : units;

    if (shownUnits.isEmpty) {
      items.add(const Padding(
        padding: EdgeInsets.all(32),
        child: Text('🌱 这个类目还没有课程，录好视频传上来就能看到啦～',
            style: TextStyle(color: AppTheme.warmGray)),
      ));
    }
    for (final unit in shownUnits) {
      final visible = unit.videos.where((v) => !v.hidden).toList();
      if (visible.isEmpty) continue;
      if (activeUnit == null) items.add(_unitHeader(unit.title));
      var idx = 0;
      for (final video in visible) {
        items.add(_videoRow(video, idx));
        idx++;
      }
    }

    return RefreshIndicator(
      onRefresh: _reload,
      color: AppTheme.brandGreen,
      child: ListView(
        key: ValueKey('home-$_reloadTick'),
        children: [
          _subjectPills(subjects, subject),
          if (units.length > 1) _unitPills(units, activeUnit),
          ...items,
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _subjectPills(List<Subject> subjects, Subject current) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: subjects.map((s) {
          final selected = s.id == current.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _subjectId = s.id;
                _selectedUnitId = '';
              }),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppTheme.brandGreen : AppTheme.sand,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  '${subjectEmoji(s.id)} ${s.name}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.white : AppTheme.warmInk,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _unitPills(List<Unit> units, Unit? activeUnit) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _pill('✨ 全部', activeUnit == null, () => setState(() => _selectedUnitId = '')),
          for (final u in units)
            _pill('📚 ${u.title}', u.id == activeUnit?.id,
                () => setState(() => _selectedUnitId = u.id)),
        ],
      ),
    );
  }

  Widget _pill(String text, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppTheme.brandGreen : AppTheme.sand,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? Colors.white : AppTheme.warmInk,
            ),
          ),
        ),
      ),
    );
  }

  Widget _continueCard(VideoContext vc) {
    final p = _progress[vc.video.id];
    final fraction = (p != null && p.durationMs > 0)
        ? (p.positionMs / p.durationMs).clamp(0.0, 1.0)
        : 0.0;
    return GestureDetector(
      onTap: () => widget.onPlayVideo(vc),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
            Color(0xFFDCF3E4),
            AppTheme.pinkContainer,
          ]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            _cover(vc.video.cover, const Size(128, 74)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('继续学习 🎬',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.greenDeep)),
                  Text(vc.video.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${vc.subject.name} · ${vc.unit.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.warmGray)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    backgroundColor: const Color(0x33FFFFFF),
                    color: AppTheme.brandGreen,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (p?.completed ?? false)
                        ? '已经看完啦，可以再看一遍～'
                        : '上次看到 ${formatDuration(p?.positionMs ?? 0)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.warmGray),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unitHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.sand,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('📚 $title',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppTheme.warmInk)),
        ),
      ),
    );
  }

  Widget _videoRow(VideoItem video, int index) {
    final p = _progress[video.id];
    return GestureDetector(
      onTap: () {
        final subject = _catalog!.subjects.firstWhere((s) => s.id == _subjectId);
        final unit = subject.grades
            .expand((g) => g.units)
            .firstWhere((u) => u.videos.any((v) => v.id == video.id));
        widget.onPlayVideo(VideoContext(subject, unit, video));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (p?.completed ?? false)
              ? AppTheme.yellowContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                _cover(video.cover, const Size(132, 76)),
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.brandGreen,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text('${index + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, color: AppTheme.warmInk)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (video.durationSec > 0) formatSeconds(video.durationSec),
                      if (video.description.isNotEmpty) video.description,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.warmGray),
                  ),
                  if (p != null && !p.completed && p.positionMs > 0 && p.durationMs > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(
                        value: (p.positionMs / p.durationMs).clamp(0.0, 1.0),
                        minHeight: 4,
                        color: AppTheme.brandGreen,
                      ),
                    ),
                ],
              ),
            ),
            if (p?.completed ?? false)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCF3E4),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Text('✓ 看完啦',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.greenDeep)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cover(String url, Size size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size.width,
        height: size.height,
        color: const Color(0xFFDCF3E4),
        child: url.isEmpty
            ? const Icon(Icons.play_circle_fill, color: Color(0xFF9CC7AA), size: 30)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.play_circle_fill, color: Color(0xFF9CC7AA)),
              ),
      ),
    );
  }
}

