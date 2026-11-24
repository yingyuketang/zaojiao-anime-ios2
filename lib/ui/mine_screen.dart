import 'package:flutter/material.dart';

import '../data/catalog_repository.dart';
import '../data/models.dart';
import '../data/paojiao_auth.dart';
import '../data/progress_store.dart';
import 'home_screen.dart';
import 'theme.dart';

/// 我的页：学习统计 + 最近观看 + 激活信息
class MineScreen extends StatefulWidget {
  final void Function(VideoContext vc) onPlayVideo;
  const MineScreen({super.key, required this.onPlayVideo});

  @override
  State<MineScreen> createState() => _MineScreenState();
}

class _MineScreenState extends State<MineScreen> {
  Map<String, VideoProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    progressStore.addListener(_reload);
    _progress = progressStore.map;
  }

  @override
  void dispose() {
    progressStore.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _progress = progressStore.map);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _progress.entries
        .where((e) => e.value.updatedAt > 0)
        .toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
    final completed = entries.where((e) => e.value.completed).length;
    final watching =
        entries.where((e) => !e.value.completed && e.value.positionMs > 0).length;
    final minutes =
        entries.fold<int>(0, (sum, e) => sum + e.value.positionMs ~/ 60000);
    final activation = paojiaoAuth.state;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('我的',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 20)),
                      Text('看看今天进步了多少吧～',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.warmGray)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('清空观看记录'),
                        content: const Text('确定要清空所有观看记录吗？此操作不可恢复。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('确定清空')),
                        ],
                      ),
                    );
                    if (ok == true) await progressStore.clearAll();
                  },
                  icon: const Icon(Icons.cleaning_services_outlined,
                      color: AppTheme.warmGray),
                ),
              ],
            ),
            if (activation != null) _activationCard(activation),
            const SizedBox(height: 12),
            Row(
              children: [
                _statCard('🎉', '$completed', '学完啦（集）', const Color(0xFFDCF3E4)),
                const SizedBox(width: 10),
                _statCard('✏️', '$watching', '学习中（集）', AppTheme.pinkContainer),
                const SizedBox(width: 10),
                _statCard('⏰', '$minutes', '观看（分钟）', AppTheme.yellowContainer),
              ],
            ),
            const SizedBox(height: 16),
            const Text('最近观看 📖',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('🌱 还没有观看记录，去课程页开始学习吧～',
                    style: TextStyle(color: AppTheme.warmGray)),
              )
            else
              ...entries.take(20).map((e) => _recentRow(e.key, e.value)),
          ],
        ),
      ),
    );
  }

  Widget _activationCard(ActivationState state) {
    final exp =
        DateTime.fromMillisecondsSinceEpoch(state.expiresTs * 1000);
    final fmt =
        '${exp.year}-${exp.month.toString().padLeft(2, '0')}-${exp.day.toString().padLeft(2, '0')}';
    final masked =
        '${state.card.substring(0, state.card.length.clamp(0, 6))}****';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDCF3E4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('🎫 ${state.cardType.isEmpty ? '会员卡' : state.cardType}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('有效期至 $fmt',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withOpacity(0.6))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('卡密：$masked',
                  style: TextStyle(
                      fontSize: 12, color: Colors.black.withOpacity(0.6))),
              const Spacer(),
              TextButton(
                onPressed: () => paojiaoAuth.logout(),
                child: const Text('退出登录',
                    style: TextStyle(color: AppTheme.brandGreen)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String emoji, String num, String label, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 6),
            Text(num,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.warmInk)),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.warmGray)),
          ],
        ),
      ),
    );
  }

  Widget _recentRow(String videoId, VideoProgress p) {
    final catalog = catalogRepository.cache;
    VideoContext? vc;
    if (catalog != null) {
      for (final s in catalog.subjects) {
        for (final g in s.grades) {
          for (final u in g.units) {
            for (final v in u.videos) {
              if (v.id == videoId) {
                vc = VideoContext(s, u, v);
              }
            }
          }
        }
      }
    }
    if (vc == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => widget.onPlayVideo(vc!),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 120,
                height: 68,
                color: const Color(0xFFDCF3E4),
                child: vc.video.cover.isEmpty
                    ? const Icon(Icons.play_circle_fill, color: Color(0xFF9CC7AA))
                    : Image.network(vc.video.cover, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.play_circle_fill,
                                color: Color(0xFF9CC7AA))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vc.video.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${vc.subject.name} · ${vc.unit.title}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.warmGray)),
                ],
              ),
            ),
            Text(p.completed ? '已看完' : '看到 ${formatDuration(p.positionMs)}',
                style:
                    const TextStyle(fontSize: 12, color: AppTheme.warmGray)),
          ],
        ),
      ),
    );
  }
}
