import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/paste_parser.dart';
import 'package:today_music/song.dart';

void main() {
  group('parsePastedSongText', () {
    test('preserves numeric song titles and strips explicit list numbers', () {
      final analysis = parsePastedSongText(
        text: '''
1. \uD658\uC808\uAE30
2) Endless Summer
3 - 1\uBD84
4: 24\uC2DC\uAC04
4242
10\uBD84 \uC804
1000 Years
1\uBD84
2\uC6D4
7 Days
''',
        existingSongs: const [],
        knownSongs: const [
          Song(artist: 'N.Flying', title: 'Rooftop', tags: []),
        ],
      );

      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        '\uD658\uC808\uAE30',
        'Endless Summer',
        '1\uBD84',
        '24\uC2DC\uAC04',
        '4242',
        '10\uBD84 \uC804',
        '1000 Years',
        '1\uBD84',
        '2\uC6D4',
        '7 Days',
      ]);
    });

    test('excludes date, setlist header, and separator lines', () {
      final analysis = parsePastedSongText(
        text: '''
2026/06/06 \uC14B\uB9AC\uC2A4\uD2B8
====================
N.Flying - Blue Moon
''',
        existingSongs: const [],
        knownSongs: const [
          Song(artist: 'N.Flying', title: 'Rooftop', tags: []),
        ],
      );

      expect(analysis.drafts, hasLength(1));
      expect(analysis.drafts.single.artist, 'N.Flying');
      expect(analysis.drafts.single.title, 'Blue Moon');
    });

    test(
      'infers artist from event header and applies it to title-only lines',
      () {
        final analysis = parsePastedSongText(
          text: '''
2026 Awesome Stage in Busan: N.Flying
Blue Moon
Autumn Dream
''',
          existingSongs: const [],
          knownSongs: const [
            Song(artist: 'N.Flying', title: 'Rooftop', tags: []),
          ],
        );

        expect(analysis.inferredArtist, 'N.Flying');
        expect(
          analysis.candidates
              .map((candidate) => candidate.song?.artist)
              .toList(),
          ['N.Flying', 'N.Flying'],
        );
        expect(
          analysis.candidates
              .map((candidate) => candidate.song?.title)
              .toList(),
          ['Blue Moon', 'Autumn Dream'],
        );
      },
    );

    test('marks existing songs as duplicates', () {
      final analysis = parsePastedSongText(
        text: 'N.Flying - Blue Moon',
        existingSongs: const [
          Song(artist: 'N.Flying', title: 'Blue Moon', tags: []),
        ],
        knownSongs: const [
          Song(artist: 'N.Flying', title: 'Rooftop', tags: []),
        ],
      );

      expect(analysis.candidates, hasLength(1));
      expect(
        analysis.candidates.single.status,
        PasteSongCandidateStatus.existing,
      );
    });

    test('handles empty input', () {
      final analysis = parsePastedSongText(text: '', existingSongs: const []);

      expect(analysis.inferredArtist, isEmpty);
      expect(analysis.drafts, isEmpty);
      expect(analysis.candidates, isEmpty);
    });
  });
}
