import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:today_music/offers/offer_repository.dart';
import 'package:today_music/song_import.dart';

void main() {
  const catalogJson = '''
{
  "offers": [
    {
      "id": "limited_test_n_flying_202606",
      "enabled": true,
      "notify": true,
      "title": "기간 한정 테스트 데이터",
      "artistLabel": "N.Flying",
      "description": "테스트 설명",
      "note": "수정 또는 삭제할 수 있습니다.",
      "dataPath": "/data/offers/test.txt",
      "startAt": "2026-06-01T00:00:00+09:00",
      "endAt": "2026-10-31T23:59:59+09:00",
      "primaryButton": "테스트 데이터 불러오기",
      "secondaryButton": "직접 시작"
    }
  ]
}
''';

  test('offer catalog loads reusable metadata and TXT content', () async {
    final repository = HttpOfferRepository(
      catalogUrl: 'https://example.com/data/offers/offers.json',
      fetch: (uri) async {
        if (uri.path.endsWith('offers.json')) {
          return http.Response.bytes(utf8.encode(catalogJson), 200);
        }
        return http.Response.bytes(
          utf8.encode('[곡]\n가수명: N.Flying\n제목: Blue Moon\n'),
          200,
        );
      },
    );

    final offers = await repository.loadCatalog();
    expect(offers, hasLength(1));
    expect(offers.single.id, 'limited_test_n_flying_202606');
    expect(offers.single.dataPath, '/data/offers/test.txt');
    expect(await repository.loadData(offers.single), contains('Blue Moon'));
  });

  test(
    'offer selection excludes disabled, expired, seen, and imported data',
    () {
      final offer = OfferedDataPackage.fromJson(
        Map<String, Object?>.from(
          jsonDecode(catalogJson)['offers'].single as Map,
        ),
      );
      final now = DateTime.parse('2026-06-23T12:00:00+09:00');

      expect(
        activeUnseenOffers(
          offers: [offer],
          now: now,
          seenOfferIds: {},
          importedOfferIds: {},
        ),
        [offer],
      );
      expect(
        activeUnseenOffers(
          offers: [offer],
          now: now,
          seenOfferIds: {offer.id},
          importedOfferIds: {},
        ),
        isEmpty,
      );
      expect(
        activeUnseenOffers(
          offers: [offer],
          now: now,
          seenOfferIds: {},
          importedOfferIds: {offer.id},
        ),
        isEmpty,
      );
    },
  );

  test('network failure returns an empty catalog without throwing', () async {
    final repository = HttpOfferRepository(
      fetch: (_) async => http.Response('Unavailable', 503),
    );

    expect(await repository.loadCatalog(), isEmpty);
  });

  test('bundled offer TXT follows the existing TDM format', () {
    final text = File(
      'web/data/offers/limited_test_n_flying_202606.txt',
    ).readAsStringSync();
    final songs = parseTdmSongText(text);

    expect(songs, hasLength(119));
    expect(songs.every((song) => song.artist == 'N.Flying'), isTrue);
    expect(songs.map((song) => song.title), contains('Blue Moon'));
  });
}
