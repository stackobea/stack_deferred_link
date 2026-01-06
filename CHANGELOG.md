## 1.0.1
- Upgrade the versions

## 1.0.0

### Added

- Wildcard support for iOS deep link pattern matching in `HelperReferrer.matchesDeepLinkPattern`.
- New matching rules:
    - `*.example.com` → matches any subdomain + the base domain.
    - `example.com/*` → matches any path under `example.com`.
    - `example.com/profile/*` → matches `/profile` and any nested path.
    - `*` → matches any URL that can be parsed as a valid URI (use carefully).

### Improved

- Kept existing behavior for:
    - http / https / no scheme
    - `www.` vs non-`www`
    - subdomain handling
- Ensured wildcard support is fully backward compatible with existing patterns.

### Notes

- No breaking changes. Existing `deepLinks` patterns continue to work as before.
- Only the internal matching logic in `HelperReferrer` was extended to support wildcards.

- Extracting a Single Query Parameter for Android

## 0.0.4

- Readme file updated

## 0.0.3

- Updated the version

## 0.0.2

- Stable release

## 0.0.1

- First stable release
- Android Install Referrer support
- iOS Clipboard deep link support
- Subdomain + www matching
- Added helper: getParam()
