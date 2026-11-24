import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/paojiao_auth.dart';
import '../data/staff_directory.dart';
import '../data/trial_store.dart';
import 'theme.dart';

/// 激活页：卡密 + 员工码（选填，显示对应老师微信）+ 新设备免费试用 3 天
class ActivateScreen extends StatefulWidget {
  final VoidCallback onActivated;
  const ActivateScreen({super.key, required this.onActivated});

  @override
  State<ActivateScreen> createState() => _ActivateScreenState();
}

class _ActivateScreenState extends State<ActivateScreen> {
  final _cardCtrl = TextEditingController();
  final _staffCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _copied = false;
  StaffConfig _staff = StaffConfig.fallback();
  bool _usedTrial = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    await staffDirectory.refresh();
    final used = await trialStore.hasUsedTrial();
    if (!mounted) return;
    setState(() {
      _staff = staffDirectory.config;
      _usedTrial = used;
    });
  }

  Future<void> _doLogin() async {
    final card = _cardCtrl.text.trim();
    if (card.isEmpty) {
      setState(() => _error = '请输入卡密哦～');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final (state, msg) = await paojiaoAuth.login(card);
    if (!mounted) return;
    if (state != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('staff_code', _staffCtrl.text.trim().toUpperCase());
      widget.onActivated();
    } else {
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  Future<void> _doTrial() async {
    final code = _staffCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '试用需要先填写员工码哦～（向老师索取）');
      return;
    }
    if (!_staff.isValidCode(code)) {
      setState(() => _error = '员工码无效，请核对后重新输入');
      return;
    }
    if (await trialStore.hasUsedTrial()) {
      setState(() => _error = '此设备已试用过啦，请购买卡密激活～');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('staff_code', code.toUpperCase());
    await trialStore.start();
    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    final wechat = _staff.wechatFor(_staffCtrl.text);
    final teacherName = _staff.nameFor(_staffCtrl.text);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCF3E4),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('🐰', style: TextStyle(fontSize: 52)),
              ),
              const SizedBox(height: 16),
              const Text('早教动画课堂',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 26)),
              const SizedBox(height: 6),
              const Text('输入卡密，开启快乐学习之旅～',
                  style: TextStyle(fontSize: 14, color: AppTheme.warmGray)),
              const SizedBox(height: 32),
              TextField(
                controller: _cardCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _deco('请输入卡密'),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _staffCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _deco('员工码（选填，向售卡老师索取）'),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: Text('🐰 $_error',
                      style: const TextStyle(
                          color: Color(0xFFC62828), fontSize: 13)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _loading ? null : _doLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandGreen,
                    shape: const StadiumBorder(),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('激 活',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _doTrial,
                child: Text(
                  '🎁 新用户填员工码，免费试用 ${Config.trialDays} 天',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _usedTrial ? AppTheme.warmGray : AppTheme.greenDeep),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: wechat));
                  setState(() => _copied = true);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '没有卡密？联系${teacherName.isEmpty ? '老师' : teacherName}购买～\n'
                    '微信号：$wechat（点击复制）',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.warmGray,
                        height: 1.5),
                  ),
                ),
              ),
              if (_copied)
                const Text('✓ 已复制，去微信添加吧',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.greenDeep)),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.warmGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.brandGreen, width: 2),
        ),
      );
}
