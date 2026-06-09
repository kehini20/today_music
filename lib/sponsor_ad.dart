import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'song.dart';

const String adConfigUrl =
    'https://tangerine-nougat-072e10.netlify.app/ads/ad_config.json';

const String fallbackBottomAdAssetPath =
    'assets/ads/ad_tdm_bottom_fallback.png';

const String fallbackMainAdAssetPath = 'assets/ads/ad_tdm_main.png';

class SponsorAd {
  final bool enabled;
  final String title;
  final String message;
  final String imageUrl;
  final String linkUrl;

  const SponsorAd({
    required this.enabled,
    required this.title,
    required this.message,
    required this.imageUrl,
    required this.linkUrl,
  });

  factory SponsorAd.fromJson(Map<String, Object?> json) {
    return SponsorAd(
      enabled: json['enabled'] == true,
      title: json['title']?.toString().trim() ?? '',
      message: json['message']?.toString().trim() ?? '',
      imageUrl: json['imageUrl']?.toString().trim() ?? '',
      linkUrl: json['linkUrl']?.toString().trim() ?? '',
    );
  }
}

class MainSponsorAd {
  final bool enabled;
  final String imageUrl;
  final String fallbackAsset;
  final String message;
  final String linkUrl;
  final Song? song;

  const MainSponsorAd({
    required this.enabled,
    required this.imageUrl,
    required this.fallbackAsset,
    required this.message,
    required this.linkUrl,
    required this.song,
  });

  factory MainSponsorAd.fromJson(Map<String, Object?> json) {
    return MainSponsorAd(
      enabled: json['enabled'] == true,
      imageUrl: json['imageUrl']?.toString().trim() ?? '',
      fallbackAsset:
          json['fallbackAsset']?.toString().trim() ?? fallbackMainAdAssetPath,
      message: json['message']?.toString().trim() ?? '',
      linkUrl: json['linkUrl']?.toString().trim() ?? '',
      song: _songFromJson(json['song']),
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
  debugPrint('SponsorAd config load start: $configUrl');

  try {
    final response = await http.get(Uri.parse(configUrl));

    if (response.statusCode != 200) {
      debugPrint(
        'SponsorAd config load failed: $configUrl / status ${response.statusCode}',
      );
      return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      debugPrint('SponsorAd JSON decode failed: $configUrl / $error');
      return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
    }

    if (decoded is! Map) {
      debugPrint('SponsorAd config is not Map: $configUrl');
      return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
    }

    final bottomAdJson = decoded['bottomAd'];
    final bottomAd = bottomAdJson is Map
        ? SponsorAd.fromJson(Map<String, Object?>.from(bottomAdJson))
        : fallbackBottomAd;

    if (bottomAdJson is! Map) {
      debugPrint('SponsorAd bottomAd missing or not Map: $configUrl');
    }

    final mainAdJson = decoded['mainAd'];
    final mainAd = mainAdJson is Map
        ? MainSponsorAd.fromJson(Map<String, Object?>.from(mainAdJson))
        : null;

    if (mainAdJson is! Map) {
      debugPrint('MainSponsorAd missing: fallback main panel will be used.');
    }

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
    debugPrint('SponsorAd config load error: $configUrl / $error');
    return const SponsorAdConfig(bottomAd: fallbackBottomAd, mainAd: null);
  }
}

Future<SponsorAd> loadBottomSponsorAd({String configUrl = adConfigUrl}) async {
  final config = await loadSponsorAdConfig(configUrl: configUrl);
  return config.bottomAd;
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
