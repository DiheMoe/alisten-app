final class SiteCapabilities {
  const SiteCapabilities({
    required this.registrationOpen,
    required this.githubLogin,
  });

  /// 读不到站点能力时使用：注册入口照常显示，由服务端决定能不能注册。
  static const unknown = SiteCapabilities(
    registrationOpen: true,
    githubLogin: false,
  );

  final bool registrationOpen;
  final bool githubLogin;
}
