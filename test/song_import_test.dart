import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/song.dart';
import 'package:today_music/song_import.dart';

void main() {
  group('song import classification', () {
    const existing = Song(
      artist: 'N.Flying',
      title: 'Flowerwork',
      tags: ['#엔플라잉'],
      memo: '기존 메모',
      link: '',
      isFavorite: true,
    );

    test('classifies new, updateable, and identical songs', () {
      final candidates = classifyImportedSongs(
        existingSongs: const [existing],
        incomingSongs: const [
          Song(artist: 'N.Flying', title: 'Blue Moon', tags: []),
          Song(
            artist: ' n.flying ',
            title: 'Flowerwork',
            tags: ['#엔플라잉', '#승협'],
            link: 'https://example.com/new',
          ),
          Song(artist: 'N.Flying', title: 'Flowerwork', tags: []),
        ],
      );

      expect(candidates[0].status, SongImportCandidateStatus.newSong);
      expect(candidates[1].status, SongImportCandidateStatus.updateAvailable);
      expect(candidates[2].status, SongImportCandidateStatus.identical);
      expect(candidates[1].changes.map((change) => change.field), ['링크', '태그']);
    });

    test('keeps existing values for blank incoming fields and merges tags', () {
      final merged = mergeImportedSong(
        existing,
        const Song(
          artist: 'N.Flying',
          title: 'Flowerwork',
          tags: ['#엔플라잉', '#승협'],
          memo: '',
          link: '',
        ),
      );

      expect(merged.memo, '기존 메모');
      expect(merged.link, '');
      expect(merged.tags, ['#엔플라잉', '#승협']);
      expect(merged.isFavorite, isTrue);
    });

    test('replaces non-empty changed link and memo only after selection', () {
      final candidate = classifyImportedSong(
        existingSongs: const [existing],
        incoming: const Song(
          artist: 'N.Flying',
          title: 'Flowerwork',
          tags: [],
          memo: '새 메모',
          link: 'https://example.com/new',
        ),
      );

      expect(candidate.status, SongImportCandidateStatus.updateAvailable);
      expect(candidate.existingSong, same(existing));
      expect(candidate.mergedSong?.memo, '새 메모');
      expect(candidate.mergedSong?.link, 'https://example.com/new');
      expect(candidate.mergedSong?.tags, ['#엔플라잉']);
    });
  });

  group('TDM TXT parsing', () {
    const text = '''
# 오늘의 한 곡 내보내기

[곡]
가수명: N.Flying
제목: Flowerwork
메모: 새 메모
태그: #엔플라잉 #승협
링크: https://example.com/flowerwork

[곡]
가수명: N.Flying
제목: Blue Moon
메모:
태그:
링크:
''';

    test('preserves metadata for duplicate comparison', () {
      final songs = parseTdmSongText(text);

      expect(songs, hasLength(2));
      expect(songs.first.artist, 'N.Flying');
      expect(songs.first.memo, '새 메모');
      expect(songs.first.tags, ['#엔플라잉', '#승협']);
      expect(songs.first.link, 'https://example.com/flowerwork');
    });

    test('rejects unrelated plain text', () {
      expect(parseTdmSongText('N.Flying - Blue Moon'), isEmpty);
    });
  });
}
