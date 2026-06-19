import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:today_music/main.dart';
import 'package:today_music/sponsor_ad.dart';

void main() {
  final now = DateTime.parse('2026-06-19T00:00:00Z');
  const configUrl = 'https://example.com/ads/ad_config.json';

  Map<String, Object?> adJson({
    required String id,
    bool enabled = true,
    String startAt = '2026-06-01T00:00:00Z',
    String endAt = '2026-06-30T23:59:59Z',
    String imageUrl = 'ads/banner.png',
  }) {
    return {
      'id': id,
      'enabled': enabled,
      'startAt': startAt,
      'endAt': endAt,
      'imageUrl': imageUrl,
      'title': id,
      'message': '',
      'linkUrl': '',
    };
  }

  test('bundled and web ad configs match the December schedule', () {
    final bundled =
        jsonDecode(File('assets/ads/ad_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final web =
        jsonDecode(File('web/ads/ad_config.json').readAsStringSync())
            as Map<String, dynamic>;

    expect(bundled, web);
    final activeAds = [
      ...(web['mainAds'] as List).cast<Map>(),
      ...(web['bottomAds'] as List).cast<Map>(),
    ].where((ad) => ad['enabled'] == true);
    for (final ad in activeAds) {
      final startAt = ad['startAt'] as String;
      final endAt = ad['endAt'] as String;
      final start = DateTime.parse(startAt);
      final end = DateTime.parse(endAt);
      expect(startAt, endsWith('+09:00'));
      expect(endAt, endsWith('+09:00'));
      expect(end.month, 12);
      expect(end.isAfter(start), isTrue);
    }
  });

  test('selects active ads and resolves relative image URLs', () {
    final config = selectSponsorAdConfigFromJson(
      {
        'bottomAds': [adJson(id: 'bottom-active')],
        'mainAds': [adJson(id: 'main-active')],
      },
      now: now,
      configUrl: configUrl,
    );

    expect(config.bottomAd.id, 'bottom-active');
    expect(config.bottomAd.imageUrl, 'https://example.com/ads/banner.png');
    expect(config.mainAd?.id, 'main-active');
    expect(config.mainAd?.imageUrl, 'https://example.com/ads/banner.png');
  });

  test('uses fallbacks when every scheduled ad is expired', () {
    final config = selectSponsorAdConfigFromJson(
      {
        'bottomAds': [
          adJson(
            id: 'bottom-expired',
            startAt: '2026-05-01T00:00:00Z',
            endAt: '2026-05-31T23:59:59Z',
          ),
        ],
        'mainAds': [
          adJson(
            id: 'main-expired',
            startAt: '2026-05-01T00:00:00Z',
            endAt: '2026-05-31T23:59:59Z',
          ),
        ],
      },
      now: now,
      configUrl: configUrl,
    );

    expect(config.bottomAd.imageUrl, isEmpty);
    expect(config.bottomAd.title, fallbackBottomAd.title);
    expect(config.mainAd, isNull);
  });

  test('uses fallbacks when ads are disabled', () {
    final config = selectSponsorAdConfigFromJson(
      {
        'bottomAds': [adJson(id: 'bottom-disabled', enabled: false)],
        'mainAds': [adJson(id: 'main-disabled', enabled: false)],
      },
      now: now,
      configUrl: configUrl,
    );

    expect(config.bottomAd.imageUrl, isEmpty);
    expect(config.bottomAd.title, fallbackBottomAd.title);
    expect(config.mainAd, isNull);
  });

  test('keeps active slots while empty image URLs render fallback assets', () {
    final config = selectSponsorAdConfigFromJson(
      {
        'bottomAds': [adJson(id: 'bottom-empty', imageUrl: '')],
        'mainAds': [adJson(id: 'main-empty', imageUrl: '')],
      },
      now: now,
      configUrl: configUrl,
    );

    expect(config.bottomAd.enabled, isTrue);
    expect(config.bottomAd.imageUrl, isEmpty);
    expect(config.mainAd?.enabled, isTrue);
    expect(config.mainAd?.imageUrl, isEmpty);
  });

  test('uses fallback config when remote loading fails', () async {
    final config = await loadSponsorAdConfig(
      configUrl: configUrl,
      fetch: (_) async => http.Response('unavailable', 503),
    );

    expect(config.bottomAd, same(fallbackBottomAd));
    expect(config.mainAd, isNull);
  });

  testWidgets('fallback main and bottom ad layouts remain visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainSponsorPanel(
            ad: fallbackMainAd,
            onOpenLink: () {},
            onPickSponsorSong: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MainSponsorPanel), findsOneWidget);
    expect(find.byType(AspectRatio), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SponsorBottomBanner(ad: fallbackBottomAd, onTap: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(SponsorBottomBanner), findsOneWidget);
    expect(find.byType(AspectRatio), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
