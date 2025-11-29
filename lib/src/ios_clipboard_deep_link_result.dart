/*
/// Represents a deep link detected from the iOS clipboard.
///
/// Example clipboard value:
///   "https://example.com/?referrer=home&uid=1000000"
///   "https://m.example.com/?referrer=home&uid=1000000"
///
/// Usage:
///   result.fullDeepLink           -> full string from clipboard
///   result.fullReferralDeepLinkPath (alias)
///   result.queryParameters        -> { "referrer": "home", "uid": "1000000" }
///   result.getParam("referrer")   -> "home"
*/

class IosClipboardDeepLinkResult {
  IosClipboardDeepLinkResult({required this.fullDeepLink, required this.uri});

  /// The full deep link string exactly as taken from the clipboard.
  final String fullDeepLink;

  /// Parsed URI form of [fullDeepLink].
  final Uri uri;

  /// Alias: full referral deep link path.
  String get fullReferralDeepLinkPath => fullDeepLink;

  /// Parsed query parameters after the `?`.
  ///
  /// Example:
  ///   fullDeepLink = "https://example.com?referrer=home&uid=10"
  ///   => { "referrer": "home", "uid": "10" }
  Map<String, String> get queryParameters => uri.queryParameters;

  /// Convenience helper to access a specific query parameter.
  ///
  /// Example:
  ///   getParam("referrer") -> "home"
  ///   getParam("uid")     -> "10"
  String? getParam(String key) => queryParameters[key];

  @override
  String toString() =>
      'IosClipboardDeepLinkResult(fullDeepLink: $fullDeepLink, queryParameters: $queryParameters)';
}
