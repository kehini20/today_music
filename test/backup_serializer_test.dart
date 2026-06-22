import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/backup/backup_models.dart';
import 'package:today_music/backup/backup_serializer.dart';
import 'package:today_music/backup/backup_validation.dart';
import 'package:today_music/song.dart';

void main() {
  const serializer = BackupSerializer();

  BackupSourceSnapshot source({
    List<Song>? songs,
    List<BackupSourceSet>? sets,
    Set<String>? disabledArtists,
    List<String>? selectedSetIds,
    String defaultShareMessage = '오늘은 이 곡을 들어보세요 🎧',
    String randomMode = 'artistRandom',
    List<String>? artistOrder,
  }) {
    return BackupSourceSnapshot(
      songs: songs ?? const [],
      sets: sets ?? const [],
      disabledRandomArtists: disabledArtists ?? const {},
      selectedSetIds: selectedSetIds ?? const [],
      defaultShareMessage: defaultShareMessage,
      randomMode: randomMode,
      artistOrder: artistOrder ?? const [],
    );
  }

  BackupDocument documentFrom(Map<String, Object?> json) {
    return BackupDocument.fromJson(json);
  }

  Map<String, Object?> validJson() {
    return {
      'backupFormatVersion': 1,
      'appVersion': '0.7.0',
      'createdAt': '2026-06-20T12:00:00+09:00',
      'platform': 'android',
      'summary': {'songCount': 1, 'setCount': 1, 'favoriteCount': 1},
      'data': {
        'songs': [
          {
            'id': 'song-1',
            'artist': 'KEY',
            'title': 'Good & Great',
            'tags': ['#콘서트'],
            'memo': '메모',
            'link': 'https://example.com',
            'isFavorite': true,
            'order': 0,
          },
        ],
        'sets': [
          {
            'id': 'set-1',
            'name': 'KEYLAND',
            'songIds': ['song-1'],
            'order': 0,
          },
        ],
        'artistRandomSettings': {
          'disabledArtists': ['KEY'],
        },
        'selectedSetIds': ['set-1'],
        'shareSettings': {'defaultMessage': '공유 문구'},
        'appSettings': {'randomMode': 'songSets'},
      },
    };
  }

  group('backup creation and restoration', () {
    test('preserves Korean, CJK, emoji, punctuation, and all song fields', () {
      const song = Song(
        artist: '키(KEY) 漢字',
        title: 'G.O.A.T (Greatest Of All Time) 🎵',
        tags: ['#한글', '#日本語', '#🔥'],
        memo: '메모 줄바꿈\n보존 & 특수문자 <>"',
        link: 'https://example.com/노래?q=한글',
        isFavorite: true,
      );
      final document = serializer.createDocument(
        source: source(
          songs: const [song],
          sets: const [
            BackupSourceSet(id: 'set-keyland', name: '키랜드 💎', songs: [song]),
          ],
          disabledArtists: const {'키(KEY) 漢字'},
          selectedSetIds: const ['set-keyland'],
          randomMode: 'songSets',
          artistOrder: const ['키(KEY) 漢字'],
        ),
        appVersion: '0.7.0',
        createdAt: DateTime.parse('2026-06-20T12:00:00+09:00'),
      );

      final decoded = serializer.decode(serializer.encode(document));
      final restored = serializer.restore(decoded);

      expect(restored.songs, [song]);
      expect(restored.songs.single.tags, song.tags);
      expect(restored.songs.single.memo, song.memo);
      expect(restored.sets.single.name, '키랜드 💎');
      expect(restored.sets.single.songs, [song]);
      expect(restored.disabledRandomArtists, {'키(KEY) 漢字'});
      expect(restored.selectedSetIds, ['set-keyland']);
      expect(restored.defaultShareMessage, '오늘은 이 곡을 들어보세요 🎧');
      expect(restored.randomMode, 'songSets');
      expect(restored.artistOrder, ['키(KEY) 漢字']);
      expect(decoded.summary.favoriteCount, 1);
    });

    test('creates and restores an empty backup', () {
      final document = serializer.createDocument(
        source: source(),
        appVersion: '0.7.0',
        createdAt: DateTime.parse('2026-06-20T12:00:00+09:00'),
      );

      expect(document.summary.songCount, 0);
      expect(document.summary.setCount, 0);
      expect(document.summary.favoriteCount, 0);
      expect(serializer.restore(document).songs, isEmpty);
    });

    test('preserves duplicate artist and title entries by song id', () {
      const first = Song(
        id: 'star-first',
        artist: 'N.Flying',
        title: 'Star',
        tags: [],
        memo: 'first memo',
      );
      const second = Song(
        id: 'star-second',
        artist: 'N.Flying',
        title: 'Star',
        tags: [],
        memo: 'second memo',
      );
      final document = serializer.createDocument(
        source: source(
          songs: const [first, second],
          sets: const [
            BackupSourceSet(
              id: 'set-duplicates',
              name: 'Duplicates',
              songs: [second],
            ),
          ],
        ),
        appVersion: '0.7.6',
        createdAt: DateTime.parse('2026-06-22T18:00:00+09:00'),
      );

      final restored = serializer.restore(
        serializer.decode(serializer.encode(document)),
      );

      expect(restored.songs.map((song) => song.id), [
        'star-first',
        'star-second',
      ]);
      expect(restored.songs.map((song) => song.memo), [
        'first memo',
        'second memo',
      ]);
      expect(restored.sets.single.songs.single.id, 'star-second');
    });

    test('keeps the same v1 schema for a web file backup', () {
      final document = serializer.createDocument(
        source: source(),
        appVersion: '0.7.2',
        createdAt: DateTime.parse('2026-06-21T17:00:00+09:00'),
        platform: 'web',
      );

      final decoded = serializer.decode(serializer.encode(document));

      expect(decoded.backupFormatVersion, 1);
      expect(decoded.platform, 'web');
    });

    test('handles a large backup and computes summary counts', () {
      final songs = List<Song>.generate(
        2000,
        (index) => Song(
          artist: '가수 ${index % 50}',
          title: '곡 $index',
          tags: const ['#대량'],
          isFavorite: index.isEven,
        ),
      );
      final document = serializer.createDocument(
        source: source(songs: songs),
        appVersion: '0.7.0',
        createdAt: DateTime.parse('2026-06-20T12:00:00+09:00'),
      );

      expect(document.summary.songCount, 2000);
      expect(document.summary.favoriteCount, 1000);
      expect(serializer.restore(document).songs.length, 2000);
    });

    test('rejects a set song that is absent from the song storage', () {
      const missingSong = Song(artist: 'N.Flying', title: 'Rooftop', tags: []);

      expect(
        () => serializer.createDocument(
          source: source(
            sets: const [
              BackupSourceSet(id: 'set-1', name: '공연', songs: [missingSong]),
            ],
          ),
          appVersion: '0.7.0',
          createdAt: DateTime.now(),
        ),
        throwsFormatException,
      );
    });
  });

  group('backup parsing and validation', () {
    test('ignores unknown fields', () {
      final json = validJson()..['futureRootField'] = {'anything': true};
      final data = Map<String, Object?>.from(json['data']! as Map)
        ..['futureDataField'] = ['ignored'];
      json['data'] = data;

      final document = serializer.decode(jsonEncode(json));

      expect(document.summary.songCount, 1);
    });

    test('applies defaults for optional fields from an earlier backup', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map);
      final songs = List<Object?>.from(data['songs']! as List);
      songs[0] = {'id': 'song-1', 'artist': 'KEY', 'title': 'Good & Great'};
      data
        ..['songs'] = songs
        ..remove('artistRandomSettings')
        ..remove('selectedSetIds')
        ..remove('shareSettings')
        ..remove('appSettings');
      json
        ..['data'] = data
        ..['summary'] = {'songCount': 1, 'setCount': 1, 'favoriteCount': 0};

      final document = serializer.decode(jsonEncode(json));

      expect(document.data.songs.single.tags, isEmpty);
      expect(document.data.songs.single.isFavorite, isFalse);
      expect(document.data.songs.single.order, 0);
      expect(document.data.appSettings.randomMode, 'artistRandom');
      expect(document.data.shareSettings.defaultMessage, isEmpty);
      expect(document.data.appSettings.artistOrder, isEmpty);
    });

    test('rejects duplicate artists in optional custom order', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map);
      data['appSettings'] = {
        'randomMode': 'artistRandom',
        'artistOrder': ['KEY', 'key'],
      };
      json['data'] = data;

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects an unsupported format version', () {
      final json = validJson()..['backupFormatVersion'] = 99;

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects missing required root data', () {
      final json = validJson()..remove('data');

      expect(() => serializer.decode(jsonEncode(json)), throwsFormatException);
    });

    test('rejects missing songs or sets arrays', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map)
        ..remove('songs');
      json['data'] = data;

      expect(() => serializer.decode(jsonEncode(json)), throwsFormatException);
    });

    test('rejects fields with incorrect types', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map);
      final songs = List<Object?>.from(data['songs']! as List);
      songs[0] = {
        ...Map<String, Object?>.from(songs[0]! as Map),
        'isFavorite': 'yes',
      };
      data['songs'] = songs;
      json['data'] = data;

      expect(() => serializer.decode(jsonEncode(json)), throwsFormatException);
    });

    test('rejects duplicate song ids', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map);
      final songs = List<Object?>.from(data['songs']! as List)
        ..add({'id': 'song-1', 'artist': 'KEY', 'title': 'Killer', 'order': 1});
      data['songs'] = songs;
      json
        ..['data'] = data
        ..['summary'] = {'songCount': 2, 'setCount': 1, 'favoriteCount': 1};

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects duplicate set ids', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map);
      final sets = List<Object?>.from(data['sets']! as List)
        ..add({
          'id': 'set-1',
          'name': '중복',
          'songIds': ['song-1'],
          'order': 1,
        });
      data['sets'] = sets;
      json
        ..['data'] = data
        ..['summary'] = {'songCount': 1, 'setCount': 2, 'favoriteCount': 1};

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects a missing song reference and duplicate set song id', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map);
      data['sets'] = [
        {
          'id': 'set-1',
          'name': 'KEYLAND',
          'songIds': ['song-1', 'song-1', 'missing-song'],
          'order': 0,
        },
      ];
      json['data'] = data;

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(
          isA<BackupValidationException>().having(
            (error) => error.errors.join(' '),
            'errors',
            allOf(contains('duplicate song id'), contains('missing song id')),
          ),
        ),
      );
    });

    test('rejects an unknown selected set id', () {
      final json = validJson();
      final data = Map<String, Object?>.from(json['data']! as Map)
        ..['selectedSetIds'] = ['missing-set'];
      json['data'] = data;

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('rejects inconsistent summary counts', () {
      final json = validJson()
        ..['summary'] = {'songCount': 9, 'setCount': 1, 'favoriteCount': 0};

      expect(
        () => serializer.decode(jsonEncode(json)),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('document parser rejects a non-ISO createdAt value', () {
      final json = validJson()..['createdAt'] = 'today';

      expect(() => documentFrom(json), throwsFormatException);
    });
  });
}
