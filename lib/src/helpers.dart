class HelperReferrerIos {
  /// Returns true if [clipboard] deep link matches [pattern],
  /// supporting:
  ///   - http / https / no scheme
  ///   - www.
  ///   - any subdomain of the pattern's base domain
  ///
  /// Examples:
  ///   clipboard: "https://sub.example.com/profile?x=1"
  ///   pattern:   "https://example.com/profile"
  ///   => true (same base domain, path prefix)
  ///
  ///   clipboard: "https://m.example.com/offer?id=1"
  ///   pattern:   "example.com"
  ///   => true (same base domain, any path)
  static bool matchesDeepLinkPattern({
    required String clipboard,
    required String pattern,
  }) {
    // Quick normalization for raw string compare
    final normalizedClipboard = normalizeUrlLikeString(clipboard);
    final normalizedPattern = normalizeUrlLikeString(pattern);

    // Simple direct/prefix check.
    if (normalizedClipboard == normalizedPattern ||
        normalizedClipboard.startsWith(normalizedPattern)) {
      return true;
    }

    // Try URI-based matching for domain and path
    final clipboardUri = parseToUri(clipboard);
    final patternUri = parseToUri(pattern);

    if (clipboardUri == null || patternUri == null) {
      return false;
    }

    String stripWww(String host) =>
        host.toLowerCase().startsWith('www.') ? host.substring(4) : host;

    final cbHostBase = stripWww(clipboardUri.host);
    final ptHostBase = stripWww(patternUri.host);

    if (cbHostBase.isEmpty || ptHostBase.isEmpty) {
      return false;
    }

    // Host match rules:
    //  - same base host
    //  - OR clipboard host is a subdomain of pattern base host
    final hostMatches =
        cbHostBase == ptHostBase || cbHostBase.endsWith('.$ptHostBase');

    if (!hostMatches) {
      return false;
    }

    // Path rule:
    //  - if pattern has no specific path ("/" or ""), accept any clipboard path
    //  - else clipboard path must start with pattern path
    final patternPath = patternUri.path.isEmpty || patternUri.path == '/'
        ? null
        : patternUri.path;

    if (patternPath == null) {
      return true; // any path is OK as long as host matched
    }

    return clipboardUri.path.startsWith(patternPath);
  }

  /// Normalize URL-like strings so that:
  ///   "https://example.com/profile?ref=abc"
  ///   "http://example.com/profile?ref=abc"
  ///   "example.com/profile?ref=abc"
  ///
  /// all become:
  ///   "example.com/profile?ref=abc"
  static String normalizeUrlLikeString(String value) {
    var v = value.trim();

    if (v.toLowerCase().startsWith('https://')) {
      v = v.substring('https://'.length);
    } else if (v.toLowerCase().startsWith('http://')) {
      v = v.substring('http://'.length);
    }

    return v;
  }

  /// Try to parse a URL-like string as a [Uri].
  ///
  /// If no scheme is present, assume "https://".
  static Uri? parseToUri(String value) {
    final trimmed = value.trim();

    Uri? tryParse(String candidate) {
      try {
        final uri = Uri.tryParse(candidate);
        if (uri == null || (uri.host.isEmpty && !uri.hasAuthority)) {
          return null;
        }
        return uri;
      } catch (_) {
        return null;
      }
    }

    // If it already has http/https scheme, try directly.
    if (trimmed.toLowerCase().startsWith('http://') ||
        trimmed.toLowerCase().startsWith('https://')) {
      return tryParse(trimmed);
    }

    // Otherwise, assume https://
    return tryParse('https://$trimmed');
  }
}
