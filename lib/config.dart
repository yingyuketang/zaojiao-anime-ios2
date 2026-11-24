/// 全局配置（与安卓版保持一致，卡密/OSS 完全互通）
class Config {
  static const String ossBaseUrl =
      'https://yingyuketang-2026.oss-cn-hangzhou.aliyuncs.com';
  static const String catalogUrl = '$ossBaseUrl/catalog.json';
  static const String staffUrl = '$ossBaseUrl/app/staff.json';

  /// 泡椒云卡密验证（软密互通：安卓 iOS 同一套卡密）
  static const String pjAppKey = 'dbvs2crdqusv6eb02a7g';
  static const String pjAppSecret = 'RFArmhBADT0XXYuqzVtTa2UkLSmuDFxq';
  static const String pjBaseUrl = 'http://api.paojiaoyun.com';
  static const String pjHost = 'api.paojiaoyun.com';

  /// 免费试用
  static const int trialDays = 3;
  static const String defaultWechat = 'QAZ89384';
}
