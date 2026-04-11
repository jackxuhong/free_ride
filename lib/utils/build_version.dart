/// Provides the app build version string.
///
/// When built via the release workflow, `APP_VERSION` is passed via
/// `--dart-define` and contains the git tag (e.g. "v1.0.2").
/// For local builds, a timestamp is generated instead
/// (e.g. "Build 20260411_110405").
class BuildVersion {
  BuildVersion._();

  static const _appVersion = String.fromEnvironment('APP_VERSION');

  static String get version {
    if (_appVersion.isNotEmpty) {
      return _appVersion;
    }
    return _localBuildTimestamp();
  }

  static String _localBuildTimestamp() {
    final now = DateTime.now();
    final stamp = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'Build $stamp';
  }
}
