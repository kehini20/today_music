import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String adConfigUrl =
    'https://tangerine-nougat-072e10.netlify.app/ads/ad_config.json';

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
  debugPrint('SponsorAd config load start: $configUrl');

  try {
    final response = await http.get(Uri.parse(configUrl));

    if (response.statusCode != 200) {
      debugPrint(
        'SponsorAd config load failed: $configUrl / status ${response.statusCode}',
      );
      return fallbackBottomAd;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      debugPrint('SponsorAd JSON decode failed: $configUrl / $error');
      return fallbackBottomAd;
    }

    if (decoded is! Map) {
      debugPrint('SponsorAd config is not Map: $configUrl');
      return fallbackBottomAd;
    }

    final bottomAdJson = decoded['bottomAd'];
    if (bottomAdJson is! Map) {
      debugPrint('SponsorAd bottomAd missing or not Map: $configUrl');
      return fallbackBottomAd;
    }

    final ad = SponsorAd.fromJson(Map<String, Object?>.from(bottomAdJson));
    debugPrint(
      'SponsorAd loaded: enabled=${ad.enabled}, imageUrl=${ad.imageUrl}',
    );
    return ad;
  } catch (error) {
    debugPrint('SponsorAd config load error: $configUrl / $error');
    return fallbackBottomAd;
  }
}
