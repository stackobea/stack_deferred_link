import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:stack_deferred_link/src/helpers.dart';
import 'package:stack_deferred_link/src/ios_clipboard_deep_link_result.dart';

/// Structured view of the Google Play Install Referrer payload.
///
/// NOTE: All timestamps are in **seconds** (as provided by the Android API).
class ReferrerInfo {
  ReferrerInfo({
    required String? installReferrer,
    required int referrerClickTimestampSeconds,
    required int installBeginTimestampSeconds,
    required int referrerClickTimestampServerSeconds,
    required int installBeginTimestampServerSeconds,
    required String? installVersion,
    required bool googlePlayInstantParam,
  })  : _installReferrer = installReferrer,
        _referrerClickTimestampSeconds = referrerClickTimestampSeconds,
        _installBeginTimestampSeconds = installBeginTimestampSeconds,
        _referrerClickTimestampServerSeconds =
            referrerClickTimestampServerSeconds,
        _installBeginTimestampServerSeconds =
            installBeginTimestampServerSeconds,
        _installVersion = installVersion,
        _googlePlayInstantParam = googlePlayInstantParam;

  final String? _installReferrer;
  final int _referrerClickTimestampSeconds;
  final int _installBeginTimestampSeconds;
  final int _referrerClickTimestampServerSeconds;
  final int _installBeginTimestampServerSeconds;
  final String? _installVersion;
  final bool _googlePlayInstantParam;

  /// The raw referrer string reported by Google Play.
  ///
  /// Example:
  ///   "utm_source=foo&utm_medium=bar&custom_param=baz"
  String? get installReferrer => _installReferrer;

  /// Client-side timestamp (seconds) when the referrer click happened.
  int get referrerClickTimestampSeconds => _referrerClickTimestampSeconds;

  /// Client-side timestamp (seconds) when the installation began.
  int get installBeginTimestampSeconds => _installBeginTimestampSeconds;

  /// Server-side timestamp (seconds) when the referrer click happened.
  int get referrerClickTimestampServerSeconds =>
      _referrerClickTimestampServerSeconds;

  /// Server-side timestamp (seconds) when the installation began.
  int get installBeginTimestampServerSeconds =>
      _installBeginTimestampServerSeconds;

  /// App version at the time of first install (if reported).
  String? get installVersion => _installVersion;

  /// Whether the app's instant experience was launched in the last 7 days.
  bool get googlePlayInstantParam => _googlePlayInstantParam;

  /// Build [ReferrerInfo] from a platform Map.
  ///
  /// This is tolerant to missing / null fields and will fallback to sane
  /// defaults (e.g. `0` for timestamps, `false` for boolean).
  factory ReferrerInfo.fromMap(Map<dynamic, dynamic> map) {
    return ReferrerInfo(
      installReferrer: map['installReferrer'] as String?,
      referrerClickTimestampSeconds:
          (map['referrerClickTimestampSeconds'] as num?)?.toInt() ?? 0,
      installBeginTimestampSeconds:
          (map['installBeginTimestampSeconds'] as num?)?.toInt() ?? 0,
      referrerClickTimestampServerSeconds:
          (map['referrerClickTimestampServerSeconds'] as num?)?.toInt() ?? 0,
      installBeginTimestampServerSeconds:
          (map['installBeginTimestampServerSeconds'] as num?)?.toInt() ?? 0,
      installVersion: map['installVersion'] as String?,
      googlePlayInstantParam: (map['googlePlayInstantParam'] as bool?) ?? false,
    );
  }

  /// Convenience method to parse the [installReferrer] as query parameters.
  ///
  /// Example:
  ///   installReferrer = "utm_source=foo&utm_medium=bar"
  ///   => returns { "utm_source": "foo", "utm_medium": "bar" }
  ///
  /// If [installReferrer] is null or empty, an empty map is returned.
  Map<String, String> get asQueryParameters {
    final ref = installReferrer;
    if (ref == null || ref.isEmpty) {
      return const {};
    }

    // Treat the referrer string like a query segment: key1=val1&key2=val2...
    final uri = Uri.parse('https://dummy?$ref');
    return uri.queryParameters;
  }

  @override
  String toString() {
    return 'ReferrerInfo('
        'installReferrer: $_installReferrer, '
        'referrerClickTimestampSeconds: $_referrerClickTimestampSeconds, '
        'installBeginTimestampSeconds: $_installBeginTimestampSeconds, '
        'referrerClickTimestampServerSeconds: $_referrerClickTimestampServerSeconds, '
        'installBeginTimestampServerSeconds: $_installBeginTimestampServerSeconds, '
        'installVersion: $_installVersion, '
        'googlePlayInstantParam: $_googlePlayInstantParam'
        ')';
  }
}

/// Main entrypoint for the `stack_deferred_link` plugin.
///
/// Usage:
/// ```dart
/// try {
///   final info = await StackDeferredLink.getInstallReferrerAndroid();
///   final params = info.asQueryParameters;
///   final campaign = params['utm_campaign'];
/// } on UnsupportedError {
///   // Not Android (iOS / web / desktop)
/// } on PlatformException catch (e) {
///   // Android-side errors (SERVICE_UNAVAILABLE, FEATURE_NOT_SUPPORTED, etc.)
/// }
/// ```
class StackDeferredLink {
  static const MethodChannel _channel = MethodChannel(
    'com.stackobea.stack_deferred_link',
  );

  /// Reads the Google Play Install Referrer information once.
  /// Error behavior:
  /// - Android plugin failures are surfaced as [PlatformException] with
  ///   codes like `SERVICE_UNAVAILABLE`, `FEATURE_NOT_SUPPORTED`, etc.
  static Future<ReferrerInfo> getInstallReferrerAndroid() async {
    // Explicitly restrict to Android only.
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'stack_deferred_link: Install Referrer is only available on Android.',
      );
    }

    try {
      final dynamic raw = await _channel.invokeMethod<dynamic>(
        'getInstallReferrer',
      );

      if (raw is! Map) {
        // Be explicit if the platform returns an unexpected shape
        throw StateError(
          'stack_deferred_link: Unexpected response type from platform: ${raw.runtimeType}',
        );
      }

      return ReferrerInfo.fromMap(raw);
    } on PlatformException {
      // Re-throw PlatformException so caller can inspect e.code / e.message
      rethrow;
    } catch (e) {
      // Any other unexpected dart-side error
      throw StateError(
        'stack_deferred_link: Unexpected error while reading install referrer: $e',
      );
    }
  }

  /// Reads the iOS clipboard and tries to detect a deep link
  /// that matches any of the provided [deepLinks].
  ///
  /// [deepLinks] should be a list of **allowed patterns**, for example:
  ///
  ///   [
  ///     "https://example.com",
  ///     "http://example.com/",
  ///     "http://example.com/profile",
  ///     "http://example.com/profile",
  ///     "example.com/profile",
  ///     "sub.example.com", // Sub domains
  ///     "example.com", // base domain only
  ///   ]
  ///
  /// Matching rules:
  ///  - Clipboard text must be non-empty.
  ///  - We normalize both clipboard text and patterns by:
  ///      * trimming
  ///      * stripping "http://" or "https://"
  ///  - We support:
  ///      * same domain
  ///      * `www.` variants
  ///      * any subdomain of the pattern base domain (e.g. sub.example.com)
  ///  - If pattern defines a path (e.g. `/profile`), clipboard's path must
  ///    start with that path.
  ///
  /// If a match is found, returns [IosClipboardDeepLinkResult].
  /// If no match or clipboard is empty, returns null.
  ///

  static Future<IosClipboardDeepLinkResult?> getInstallReferrerIos({
    required List<String> deepLinks,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError(
        'stack_deferred_link: getInstallReferrerIos() is only intended for iOS.',
      );
    }

    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();

      if (text == null || text.isEmpty) {
        // Nothing on clipboard / not text.
        return null;
      }

      // Check if clipboard text matches any deep link pattern (with subdomain + www rules)
      final hasMatch = deepLinks.any(
        (pattern) => HelperReferrerIos.matchesDeepLinkPattern(
          clipboard: text,
          pattern: pattern,
        ),
      );

      if (!hasMatch) {
        // Clipboard text is not one of our expected deep links.
        return null;
      }

      // Try to parse the clipboard text as a URI.
      final uri = HelperReferrerIos.parseToUri(text);
      if (uri == null) {
        // We matched the pattern but couldn't parse it as URI.
        return null;
      }

      return IosClipboardDeepLinkResult(fullDeepLink: text, uri: uri);
    } on PlatformException catch (e) {
      // Provide a clearer message but keep the original error code/details.
      throw PlatformException(
        code: e.code,
        message:
            'stack_deferred_link: Failed to read clipboard text on iOS: ${e.message}',
        details: e.details,
      );
    } catch (e) {
      throw StateError(
        'stack_deferred_link: Unexpected error while reading clipboard text: $e',
      );
    }
  }
}
