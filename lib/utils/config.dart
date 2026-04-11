class AppConfig {
  AppConfig._();

  /// Timeouts for playlist fetching.
  static const Duration fetchTimeout = Duration(seconds: 180);

  /// User Agent for HTTP requests (improves compatibility with some providers).
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}
