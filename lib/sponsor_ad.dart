import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'song.dart';

const String adConfigUrl = String.fromEnvironment(
  'SPONSOR_AD_CONFIG_URL',
  defaultValue: 'ads/ad_config.json',
);

const String appAdConfigBaseUrl = 'https://today-music.pages.dev/';

const String fallbackBottomAdAssetPath =
    'assets/ads/ad_tdm_bottom_fallback.png';

const String fallbackMainAdAssetPath = 'assets/ads/ad_tdm_main_fallback.png';

class SponsorAd {
  final String id;
  final String slot;
  final String startAt;
  final String endAt;
  final bool enabled;
  final String title;
  final String message;
  final String imageUrl;
  final String linkUrl;

  const SponsorAd({
    this.id = '',
    this.slot = '',
    this.startAt = '',
    this.endAt = '',
    required this.enabled,
    required this.title,
    required this.message,
    required this.imageUrl,
    required this.linkUrl,
  });

  factory SponsorAd.fromJson(Map<String, Object?> json) {
    return SponsorAd(
      id: json['id']?.toString().trim() ?? '',
      slot: json['slot']?.toString().trim() ?? '',
      startAt: json['startAt']?.toString().trim() ?? '',
      endAt: json['endAt']?.toString().trim() ?? '',
      enabled: json['enabled'] == true,
      title: json['title']?.toString().trim() ?? '',
      message: json['message']?.toString().trim() ?? '',
      imageUrl: json['imageUrl']?.toString().trim() ?? '',
      linkUrl: json['linkUrl']?.toString().trim() ?? '',
    );
  }

  SponsorAd copyWith({String? imageUrl}) {
    return SponsorAd(
      id: id,
      slot: slot,
      startAt: startAt,
      endAt: endAt,
      enabled: enabled,
      title: title,
      message: message,
      imageUrl: imageUrl ?? this.imageUrl,
      linkUrl: linkUrl,
    );
  }
}

class MainSponsorAd {
  final String id;
  final String slot;
  final String startAt;
  final String endAt;
  final bool enabled;
  final String imageUrl;
  final String fallbackAsset;
  final String message;
  final String linkUrl;
  final Song? song;

  const MainSponsorAd({
    this.id = '',
    this.slot = '',
    this.startAt = '',
    this.endAt = '',
    required this.enabled,
    required this.imageUrl,
    required this.fallbackAsset,
    required this.message,
    required this.linkUrl,
    required this.song,
  });

  factory MainSponsorAd.fromJson(Map<String, Object?> json) {
    return MainSponsorAd(
      id: json['id']?.toString().trim() ?? '',
      slot: json['slot']?.toString().trim() ?? '',
      startAt: json['startAt']?.toString().trim() ?? '',
      endAt: json['endAt']?.toString().trim() ?? '',
      enabled: json['enabled'] == true,
      imageUrl: json['imageUrl']?.toString().trim() ?? '',
      fallbackAsset:
          json['fallbackAsset']?.toString().trim() ?? fallbackMainAdAssetPath,
      message: json['message']?.toString().trim() ?? '',
      linkUrl: json['linkUrl']?.toString().trim() ?? '',
      song: _songFromJson(json['song']),
    );
  }

  MainSponsorAd copyWith({String? imageUrl}) {
    return MainSponsorAd(
      id: id,
      slot: slot,
      startAt: startAt,
      endAt: endAt,
      enabled: enabled,
      imageUrl: imageUrl ?? this.imageUrl,
      fallbackAsset: fallbackAsset,
      message: message,
      linkUrl: linkUrl,
      song: song,
    );
  }
}

class SponsorAdConfig {
  final SponsorAd bottomAd;
  final MainSponsorAd? mainAd;

  const SponsorAdConfig({required this.bottomAd, required this.mainAd});
}

const SponsorAd fallbackBottomAd = SponsorAd(
  enabled: true,
  title: '오늘의 한 곡',
  message: '오늘도 한 곡 뽑아볼까요?',
  imageUrl: '',
  linkUrl: '',
);

const MainSponsorAd fallbackMainAd = MainSponsorAd(
  enabled: true,
  imageUrl: '',
  fallbackAsset: fallbackMainAdAssetPath,
  message: '오늘의 추천곡을 준비 중이에요. 지금은 랜덤 뽑기로 먼저 만나보세요.',
  linkUrl: '',
  song: null,
);

Future<SponsorAdConfig> loadSponsorAdConfig({
  String configUrl = adConfigUrl,
}) async {
  final resolvedConfigUrl = _resolveAdConfigUrl(configUrl);
  debugPrint('SponsorAd config load start: $resolvedConfigUrl');

  try {
    final response = await http.get(Uri.parse(resolvedConfigUrl));

    if (response.statusCode != 200) {
      debugPrint(
        'SponsorAd config load failed: $resolvedConfigUrl / status ${response.statusCode}',
      );
      return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      debugPrint('SponsorAd JSON decode failed: $resolvedConfigUrl / $error');
      return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
    }

    if (decoded is! Map) {
      debugPrint('SponsorAd config is not Map: $resolvedConfigUrl');
      return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
    }

    final now = DateTime.now();
    final bottomAd = _resolveSponsorAdImageUrl(
      _selectBottomAd(decoded, now, resolvedConfigUrl),
      resolvedConfigUrl,
    );
    final selectedMainAd = _selectMainAd(decoded, now);
    final mainAd = selectedMainAd == null
        ? null
        : _resolveMainSponsorAdImageUrl(selectedMainAd, resolvedConfigUrl);

    debugPrint(
      'SponsorAd loaded: enabled=${bottomAd.enabled}, imageUrl=${bottomAd.imageUrl}',
    );
    if (mainAd != null) {
      debugPrint(
        'MainSponsorAd loaded: enabled=${mainAd.enabled}, imageUrl=${mainAd.imageUrl}',
      );
      if (!mainAd.enabled) {
        debugPrint('MainSponsorAd disabled: fallback main panel will be used.');
      }
    }

    return SponsorAdConfig(bottomAd: bottomAd, mainAd: mainAd);
  } catch (error) {
    debugPrint('SponsorAd config load error: $resolvedConfigUrl / $error');
    return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
  }
}

Future<SponsorAd> loadBottomSponsorAd({String configUrl = adConfigUrl}) async {
  final config = await loadSponsorAdConfig(configUrl: configUrl);
  return config.bottomAd;
}

String _resolveAdConfigUrl(String configUrl) {
  final trimmed = configUrl.trim();
  if (trimmed.isEmpty) {
    return kIsWeb
        ? adConfigUrl
        : Uri.parse(appAdConfigBaseUrl).resolve(adConfigUrl).toString();
  }

  final configUri = Uri.tryParse(trimmed);
  if (configUri != null && configUri.hasScheme) {
    return trimmed;
  }

  if (kIsWeb) {
    return trimmed;
  }

  final normalizedPath = trimmed.startsWith('/')
      ? trimmed.substring(1)
      : trimmed;
  return Uri.parse(appAdConfigBaseUrl).resolve(normalizedPath).toString();
}

SponsorAd _resolveSponsorAdImageUrl(SponsorAd ad, String configUrl) {
  return ad.copyWith(
    imageUrl: _resolveAdImageUrl(ad.imageUrl, configUrl, ad.id),
  );
}

MainSponsorAd _resolveMainSponsorAdImageUrl(
  MainSponsorAd ad,
  String configUrl,
) {
  return ad.copyWith(
    imageUrl: _resolveAdImageUrl(ad.imageUrl, configUrl, ad.id),
  );
}

String _resolveAdImageUrl(String imageUrl, String configUrl, String adId) {
  final trimmed = imageUrl.trim();
  if (trimmed.isEmpty) {
    return '';
  }

  final imageUri = Uri.tryParse(trimmed);
  if (imageUri != null && imageUri.hasScheme) {
    return trimmed;
  }

  final configUri = Uri.tryParse(configUrl);
  if (configUri == null || !configUri.hasScheme) {
    debugPrint(
      'SponsorAd imageUrl left unresolved: id=$adId, imageUrl=$trimmed, configUrl=$configUrl',
    );
    return trimmed;
  }

  final normalizedPath = trimmed.replaceAll('\\', '/');
  final resolved = normalizedPath.startsWith('ads/')
      ? configUri.replace(
          path: _joinUriPath(
            _siteBasePathFromConfig(configUri.path),
            normalizedPath,
          ),
          query: null,
          fragment: null,
        )
      : configUri.resolve(normalizedPath);
  final resolvedText = resolved.toString();

  debugPrint(
    'SponsorAd imageUrl resolved: id=$adId, imageUrl=$trimmed, resolved=$resolvedText',
  );
  return resolvedText;
}

String _siteBasePathFromConfig(String configPath) {
  final adsIndex = configPath.indexOf('/ads/');
  if (adsIndex >= 0) {
    return configPath.substring(0, adsIndex + 1);
  }

  final lastSlashIndex = configPath.lastIndexOf('/');
  if (lastSlashIndex < 0) {
    return '/';
  }

  return configPath.substring(0, lastSlashIndex + 1);
}

String _joinUriPath(String basePath, String relativePath) {
  final normalizedBase = basePath.endsWith('/') ? basePath : '$basePath/';
  final normalizedRelative = relativePath.startsWith('/')
      ? relativePath.substring(1)
      : relativePath;

  return '$normalizedBase$normalizedRelative';
}

SponsorAd _selectBottomAd(
  Map<dynamic, dynamic> decoded,
  DateTime now,
  String configUrl,
) {
  final bottomAdsJson = decoded['bottomAds'];
  if (bottomAdsJson is List) {
    final candidates = _parseBottomAds(bottomAdsJson);
    final activeAds = candidates
        .where(
          (ad) => _isAdActive(
            enabled: ad.enabled,
            id: ad.id,
            slot: ad.slot,
            startAt: ad.startAt,
            endAt: ad.endAt,
            now: now,
            logPrefix: 'bottomAd',
          ),
        )
        .take(3)
        .toList();

    if (activeAds.isEmpty) {
      debugPrint(
        'bottomAds active candidate missing: fallback bottomAd selected.',
      );
      return fallbackBottomAd;
    }

    final selected = activeAds[_selectionIndex(activeAds.length, now)];
    _logSelectedAd(
      logPrefix: 'bottomAd',
      id: selected.id,
      slot: selected.slot,
      startAt: selected.startAt,
      endAt: selected.endAt,
    );
    return selected;
  }

  final bottomAdJson = decoded['bottomAd'];
  final bottomAd = bottomAdJson is Map
      ? SponsorAd.fromJson(Map<String, Object?>.from(bottomAdJson))
      : fallbackBottomAd;

  if (bottomAdJson is! Map) {
    debugPrint('SponsorAd bottomAd missing or not Map: $configUrl');
  }

  _logSingleAdState(
    logPrefix: 'bottomAd',
    id: bottomAd.id,
    slot: bottomAd.slot,
    startAt: bottomAd.startAt,
    endAt: bottomAd.endAt,
    enabled: bottomAd.enabled,
  );
  if (_hasSchedule(bottomAd.startAt, bottomAd.endAt) &&
      !_isAdActive(
        enabled: bottomAd.enabled,
        id: bottomAd.id,
        slot: bottomAd.slot,
        startAt: bottomAd.startAt,
        endAt: bottomAd.endAt,
        now: now,
        logPrefix: 'bottomAd',
      )) {
    debugPrint(
      'bottomAd single inactive by schedule: fallback bottomAd selected.',
    );
    return fallbackBottomAd;
  }

  return bottomAd;
}

MainSponsorAd? _selectMainAd(Map<dynamic, dynamic> decoded, DateTime now) {
  final mainAdsJson = decoded['mainAds'];
  if (mainAdsJson is List) {
    final candidates = _parseMainAds(mainAdsJson);
    final activeAds = candidates
        .where(
          (ad) => _isAdActive(
            enabled: ad.enabled,
            id: ad.id,
            slot: ad.slot,
            startAt: ad.startAt,
            endAt: ad.endAt,
            now: now,
            logPrefix: 'mainAd',
          ),
        )
        .take(3)
        .toList();

    if (activeAds.isEmpty) {
      debugPrint(
        'mainAds active candidate missing: fallback main panel will be used.',
      );
      return null;
    }

    final selected = activeAds[_selectionIndex(activeAds.length, now)];
    _logSelectedAd(
      logPrefix: 'mainAd',
      id: selected.id,
      slot: selected.slot,
      startAt: selected.startAt,
      endAt: selected.endAt,
    );
    return selected;
  }

  final mainAdJson = decoded['mainAd'];
  if (mainAdJson is! Map) {
    debugPrint('MainSponsorAd missing: fallback main panel will be used.');
    return null;
  }

  final mainAd = MainSponsorAd.fromJson(Map<String, Object?>.from(mainAdJson));

  _logSingleAdState(
    logPrefix: 'mainAd',
    id: mainAd.id,
    slot: mainAd.slot,
    startAt: mainAd.startAt,
    endAt: mainAd.endAt,
    enabled: mainAd.enabled,
  );
  if (_hasSchedule(mainAd.startAt, mainAd.endAt) &&
      !_isAdActive(
        enabled: mainAd.enabled,
        id: mainAd.id,
        slot: mainAd.slot,
        startAt: mainAd.startAt,
        endAt: mainAd.endAt,
        now: now,
        logPrefix: 'mainAd',
      )) {
    debugPrint(
      'mainAd single inactive by schedule: fallback main panel will be used.',
    );
    return null;
  }

  return mainAd;
}

List<SponsorAd> _parseBottomAds(List<dynamic> rawAds) {
  final ads = <SponsorAd>[];
  for (final rawAd in rawAds) {
    if (rawAd is! Map) {
      debugPrint('bottomAds item skipped: not Map');
      continue;
    }

    try {
      ads.add(SponsorAd.fromJson(Map<String, Object?>.from(rawAd)));
    } catch (error) {
      debugPrint('bottomAds item parse failed: $error');
    }
  }
  return ads;
}

List<MainSponsorAd> _parseMainAds(List<dynamic> rawAds) {
  final ads = <MainSponsorAd>[];
  for (final rawAd in rawAds) {
    if (rawAd is! Map) {
      debugPrint('mainAds item skipped: not Map');
      continue;
    }

    try {
      ads.add(MainSponsorAd.fromJson(Map<String, Object?>.from(rawAd)));
    } catch (error) {
      debugPrint('mainAds item parse failed: $error');
    }
  }
  return ads;
}

bool _isAdActive({
  required bool enabled,
  required String id,
  required String slot,
  required String startAt,
  required String endAt,
  required DateTime now,
  required String logPrefix,
}) {
  var active = enabled;

  final start = _parseAdDate(startAt, '$logPrefix startAt', id);
  final end = _parseAdDate(endAt, '$logPrefix endAt', id);

  if (enabled && start == null && startAt.trim().isNotEmpty) {
    active = false;
  }
  if (enabled && end == null && endAt.trim().isNotEmpty) {
    active = false;
  }
  if (active && start != null && now.isBefore(start)) {
    active = false;
  }
  if (active && end != null && now.isAfter(end)) {
    active = false;
  }

  debugPrint(
    '$logPrefix candidate: id=$id, slot=$slot, startAt=$startAt, endAt=$endAt, active=$active',
  );
  return active;
}

DateTime? _parseAdDate(String value, String fieldName, String id) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  try {
    return DateTime.parse(trimmed);
  } catch (error) {
    debugPrint(
      'SponsorAd date parse failed: id=$id, field=$fieldName, value=$trimmed, error=$error',
    );
    return null;
  }
}

int _selectionIndex(int candidateCount, DateTime now) {
  if (candidateCount <= 1) {
    return 0;
  }

  return now.millisecondsSinceEpoch % candidateCount;
}

bool _hasSchedule(String startAt, String endAt) {
  return startAt.trim().isNotEmpty || endAt.trim().isNotEmpty;
}

void _logSelectedAd({
  required String logPrefix,
  required String id,
  required String slot,
  required String startAt,
  required String endAt,
}) {
  debugPrint(
    '$logPrefix selected: id=$id, slot=$slot, startAt=$startAt, endAt=$endAt, active=true',
  );
}

void _logSingleAdState({
  required String logPrefix,
  required String id,
  required String slot,
  required String startAt,
  required String endAt,
  required bool enabled,
}) {
  debugPrint(
    '$logPrefix single: id=$id, slot=$slot, startAt=$startAt, endAt=$endAt, active=$enabled',
  );
}

Song? _songFromJson(Object? rawJson) {
  if (rawJson is! Map) {
    return null;
  }

  final json = Map<String, Object?>.from(rawJson);
  final artist = json['artist']?.toString().trim() ?? '';
  final title = json['title']?.toString().trim() ?? '';

  if (artist.isEmpty || title.isEmpty) {
    return null;
  }

  return Song(
    artist: artist,
    title: title,
    memo: json['memo']?.toString().trim() ?? '',
    tags: _parseSponsorTags(json['tags']),
    link: json['link']?.toString().trim() ?? '',
  );
}

List<String> _parseSponsorTags(Object? rawTags) {
  if (rawTags is List) {
    return rawTags
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .map((tag) => tag.startsWith('#') ? tag : '#$tag')
        .toList();
  }

  if (rawTags is! String) {
    return const [];
  }

  return rawTags
      .split(RegExp(r'[,\s]+'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .map((tag) => tag.startsWith('#') ? tag : '#$tag')
      .toList();
}
