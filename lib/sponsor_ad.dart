import 'dart:convert';

import 'package:flutter/services.dart';

const String adConfigUrl =
    'https://TDM_NETLIFY_URL.netlify.app/ads/ad_config.json';

const String fallbackBottomAdAssetPath =
    'assets/ads/ad_tdm_bottom_fallback.png';

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

const SponsorAd fallbackBottomAd = SponsorAd(
  enabled: true,
  title: '오늘의 한 곡',
  message: '오늘도 한 곡 뽑아볼까요?',
  imageUrl: '',
  linkUrl: '',
);

Future<SponsorAd> loadBottomSponsorAd({String configUrl = adConfigUrl}) async {
  try {
    final rawJson = await NetworkAssetBundle(
      Uri.parse(configUrl),
    ).loadString('');
    final decoded = jsonDecode(rawJson);

    if (decoded is! Map) {
      return fallbackBottomAd;
    }

    final bottomAdJson = decoded['bottomAd'];
    if (bottomAdJson is! Map) {
      return fallbackBottomAd;
    }

    return SponsorAd.fromJson(Map<String, Object?>.from(bottomAdJson));
  } catch (_) {
    return fallbackBottomAd;
  }
}
