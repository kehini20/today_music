import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/paste_parser.dart';
import 'package:today_music/song.dart';

void main() {
  group('artist name normalization', () {
    test('uses the unique stored spelling for safe comparison matches', () {
      const existingSongs = [
        Song(artist: 'N.Flying', title: 'Blue Moon', tags: []),
      ];

      expect(resolveStoredArtistName('NFlying', existingSongs), 'N.Flying');
      expect(resolveStoredArtistName('N Flying', existingSongs), 'N.Flying');
      expect(resolveStoredArtistName('n.flying', existingSongs), 'N.Flying');
    });

    test('keeps inferred spelling when there is no unique stored match', () {
      const ambiguousSongs = [
        Song(artist: 'N.Flying', title: 'Blue Moon', tags: []),
        Song(artist: 'NFlying', title: 'Rooftop', tags: []),
      ];

      expect(resolveStoredArtistName('ONEWE', ambiguousSongs), 'ONEWE');
      expect(resolveStoredArtistName('N Flying', ambiguousSongs), 'N Flying');
      expect(resolveStoredArtistName('엔플라잉', ambiguousSongs), '엔플라잉');
    });

    test('applies the stored spelling to initially inferred artists', () {
      final analysis = parsePastedSongText(
        text: '''
NFlying SETLIST
Blue Moon
''',
        existingSongs: const [
          Song(artist: 'N.Flying', title: 'Rooftop', tags: []),
        ],
      );

      expect(analysis.inferredArtist, 'N.Flying');
      expect(analysis.candidates.single.song?.artist, 'N.Flying');
    });

    test('keeps a user-edited inferred artist during candidate rebuild', () {
      final candidates = buildPasteSongCandidates(
        drafts: const [
          PasteSongDraft(
            sourceLine: 'Blue Moon',
            title: 'Blue Moon',
            usesInferredArtist: true,
          ),
        ],
        inferredArtist: 'N Flying',
        existingSongs: const [
          Song(artist: 'N.Flying', title: 'Rooftop', tags: []),
        ],
      );

      expect(candidates.single.song?.artist, 'N Flying');
    });
  });

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

    test('classifies pasted TDM metadata as an update candidate', () {
      final analysis = parsePastedSongText(
        text: '''
[곡]
가수명: N.Flying
제목: Flowerwork
메모:
태그: #엔플라잉 #승협
링크: https://example.com/flowerwork
''',
        existingSongs: const [
          Song(artist: 'N.Flying', title: 'Flowerwork', tags: ['#엔플라잉']),
        ],
      );

      expect(analysis.candidates, hasLength(1));
      expect(
        analysis.candidates.single.status,
        PasteSongCandidateStatus.updateAvailable,
      );
      expect(analysis.candidates.single.mergedSong?.tags, ['#엔플라잉', '#승협']);
      expect(analysis.candidates.single.changes.map((change) => change.field), [
        '링크',
        '태그',
      ]);
    });

    test('handles OCR setlist headers, split numbers, and encore suffixes', () {
      final analysis = parsePastedSongText(
        text: '''
2026 Awesome Stage in Busan (Day2)
2026/06/07 \uC5D4\uD50C\uB77C\uC789 \uC14B\uB9AC\uC2A4\uD2B8
01. \uD658\uC808\uAE30 (1%\uD569#8)
02. Endless Summer
19.
(Rooftop)
21.\uD53C\uC5C8\uC2B5\uB2C8\uB2E4. (Into Bloom)
22. Flashback - \uC575\uCF5C
24.4242-\uC575\uCF5C
29. \uD658\uC808\uAE30 (3\uD5043) - \uD55C\uBC88 \uB354
MC
\uC575\uCF5C2
ENCORE
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, '\uC5D4\uD50C\uB77C\uC789');
      expect(
        analysis.candidates.map((candidate) => candidate.song?.title).toList(),
        [
          '\uD658\uC808\uAE30 (1%\uD569#8)',
          'Endless Summer',
          'Rooftop',
          '\uD53C\uC5C8\uC2B5\uB2C8\uB2E4. (Into Bloom)',
          'Flashback',
          '4242',
          '\uD658\uC808\uAE30 (3\uD5043)',
        ],
      );
      expect(
        analysis.candidates.map((candidate) => candidate.song?.artist).toSet(),
        {'\uC5D4\uD50C\uB77C\uC789'},
      );
    });

    test('parses the provided full OCR setlist sample', () {
      final analysis = parsePastedSongText(
        text: '''
2026 Awesome Stage in Busan (Day2)
2026/06/07 \uC5D4\uD50C\uB77C\uC789 \uC14B\uB9AC\uC2A4\uD2B8
01. \uD658\uC808\uAE30 (1%\uD569#8)
02. Endless Summer
03. The World Is Mine
04. Delight
05. Star
06. Run Like This
07. \uBEB0\uBE44\uC6B0\uC2A4 (Moebius)
08. \uC544\uC9C1\uB3C4 \uB09C \uADF8\uB300\uB97C \uC88B\uC544\uD574\uC694 (Still You)
09. Love You Like That
10. Ask
11. \uC0AC\uB791\uC744 \uB9C8\uC8FC\uD558\uACE0 (Rise Again)
12. \uC815\uB9AC\uAC00 \uC548\uB3FC (Don't Mess With Me)
13. \uD3ED\uB9DD (I Like You)
14. \uB124\uAC00 \uB0B4 \uB9C8\uC74C\uC5D0 \uC790\uB9AC \uC7A1\uC558\uB2E4 (Into You)
15. \uD589\uBCF5\uD574\uBC84\uB9AC\uAE30 (HAPPY ME!)
16. Autumn Dream
17. Blue Moon
18. Sunset
19.
(Rooftop)
20. Songbird (Korean Ver.)
21.\uD53C\uC5C8\uC2B5\uB2C8\uB2E4. (Into Bloom)
22. Flashback - \uC575\uCF5C
23. \uC544 \uC9C4\uC9DC\uC694. (Oh really.) - \uC575\uCF5C
24.4242-\uC575\uCF5C
25. \uB728\uAC70\uC6B4 \uAC10\uC790 (Hot Potato) -\uC575\uCF5C
26. \uC9C4\uC9DC\uAE30\uAC00 \uB098\uD0C0\uB0AC\uB2E4 (The Real )- \uC575\uCF5C
27. \uB194 (Leave lt) - \uC575\uCF5C
28. \uD658\uC808\uAE30 (FE)- \uC575\uCF5C
29. \uD658\uC808\uAE30 (3\uD5043) - \uD55C\uBC88 \uB354
30. \uAD7F\uBC24 (GOOD BAM) - \uC575\uCF5C
''',
        existingSongs: const [],
      );

      final titles = analysis.candidates
          .map((candidate) => candidate.song?.title)
          .toList();

      expect(analysis.inferredArtist, '\uC5D4\uD50C\uB77C\uC789');
      expect(analysis.candidates, hasLength(30));
      expect(titles, contains('Rooftop'));
      expect(titles, contains('4242'));
      expect(titles, contains('Flashback'));
      expect(titles, contains('\uD53C\uC5C8\uC2B5\uB2C8\uB2E4. (Into Bloom)'));
      expect(titles, isNot(contains('\uC575\uCF5C')));
      expect(titles.where((title) => title == null), isEmpty);
    });
    test('does not infer noisy OCR fragments as artist names', () {
      final analysis = parsePastedSongText(
        text: '''
8)
1%\uD569#8
01. Blue Moon
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, isEmpty);
      expect(analysis.candidates.single.song, isNull);
      expect(
        analysis.candidates.single.status,
        PasteSongCandidateStatus.needsReview,
      );
    });

    test('marks repeated songs inside the same pasted text as duplicates', () {
      final analysis = parsePastedSongText(
        text: '''
N.Flying setlist
03. Cotton Candy
30. Cotton Candy
''',
        existingSongs: const [],
      );

      expect(
        analysis.candidates.map((candidate) => candidate.status).toList(),
        [PasteSongCandidateStatus.newSong, PasteSongCandidateStatus.existing],
      );
    });
    test('recalculates edited draft titles against existing songs', () {
      final candidates = buildPasteSongCandidates(
        drafts: const [
          PasteSongDraft(
            sourceLine: 'Autumn Dream',
            title: 'Blue Moon',
            usesInferredArtist: true,
          ),
        ],
        inferredArtist: 'N.Flying',
        existingSongs: const [
          Song(artist: 'N.Flying', title: 'Blue Moon', tags: []),
        ],
      );

      expect(candidates.single.status, PasteSongCandidateStatus.existing);
    });

    test(
      'keeps loose internal title variants as new songs in an empty library',
      () {
        final candidates = buildPasteSongCandidates(
          drafts: const [
            PasteSongDraft(
              sourceLine: 'Stand By Me',
              artist: 'N.Flying',
              title: 'Stand By Me',
            ),
            PasteSongDraft(
              sourceLine: 'Stand By Me (Korean Ver.)',
              artist: 'N.Flying',
              title: 'Stand By Me (Korean Ver.)',
              link: 'https://example.com/stand-by-me-korean',
            ),
          ],
          inferredArtist: '',
          existingSongs: const [],
        );

        expect(candidates.map((candidate) => candidate.status).toList(), [
          PasteSongCandidateStatus.newSong,
          PasteSongCandidateStatus.newSong,
        ]);
      },
    );

    test('bundled offered TXT is all new songs for an empty library', () {
      final text = File(
        'web/data/offers/limited_test_n_flying_202606.txt',
      ).readAsStringSync();
      final analysis = parsePastedSongText(text: text, existingSongs: const []);

      expect(analysis.candidates, hasLength(119));
      expect(
        analysis.candidates.where(
          (candidate) =>
              candidate.status == PasteSongCandidateStatus.updateAvailable,
        ),
        isEmpty,
      );
      expect(analysis.candidates.map((candidate) => candidate.status).toSet(), {
        PasteSongCandidateStatus.newSong,
      });
    });
    test('recalculates edited draft titles for internal duplicates', () {
      final candidates = buildPasteSongCandidates(
        drafts: const [
          PasteSongDraft(
            sourceLine: 'Cotton Candy',
            title: 'Cotton Candy',
            usesInferredArtist: true,
          ),
          PasteSongDraft(
            sourceLine: 'Autumn Dream',
            title: 'Cotton Candy',
            usesInferredArtist: true,
          ),
        ],
        inferredArtist: 'N.Flying',
        existingSongs: const [],
      );

      expect(candidates.map((candidate) => candidate.status).toList(), [
        PasteSongCandidateStatus.newSong,
        PasteSongCandidateStatus.existing,
      ]);
    });

    test('edited draft titles can resolve internal duplicates', () {
      final candidates = buildPasteSongCandidates(
        drafts: const [
          PasteSongDraft(
            sourceLine: 'Cotton Candy',
            title: 'Cotton Candy',
            usesInferredArtist: true,
          ),
          PasteSongDraft(
            sourceLine: 'Cotton Candy',
            title: 'Blue Moon',
            usesInferredArtist: true,
          ),
        ],
        inferredArtist: 'N.Flying',
        existingSongs: const [],
      );

      expect(candidates.map((candidate) => candidate.status).toList(), [
        PasteSongCandidateStatus.newSong,
        PasteSongCandidateStatus.newSong,
      ]);
    });

    test('connects alternate OCR titles with matching list numbers', () {
      final alternatives = buildOcrTitleAlternatives(
        primaryText: '07. ¿bh(\n08.\n君と僕の未来\n09. Love You Like That',
        alternateText: '07. きらめく季節\n08. 君と僕の未来\n09. Love You Like That',
      );

      expect(alternatives, ['きらめく季節', '君と僕の未来', 'Love You Like That']);
    });

    test('does not connect alternate OCR titles with different numbers', () {
      final alternatives = buildOcrTitleAlternatives(
        primaryText: '07. 환절기\n08. Endless Summer',
        alternateText: '17. きらめく季節\n18. 君と僕の未来',
      );

      expect(alternatives, [null, null]);
    });

    test('connects unnumbered OCR titles by safe reading order', () {
      final alternatives = buildOcrTitleAlternatives(
        primaryText: '환절기\nEndless Summer',
        alternateText: 'きらめく季節\nMarionette Wire',
      );

      expect(alternatives, ['きらめく季節', 'Marionette Wire']);
    });

    test('excludes meta and empty OCR lines from alternate candidates', () {
      final alternatives = buildOcrTitleAlternatives(
        primaryText: 'N.Flying 셋리스트\n01. 환절기\nMC\n02. Endless Summer',
        alternateText: 'N.Flying setlist\n01. きらめく季節\n앵콜\n02. Endless Summer',
      );

      expect(alternatives, ['きらめく季節', 'Endless Summer']);
    });

    test('infers artist from decorated performance headers safely', () {
      final yoasobi = parsePastedSongText(
        text: '''
2026 YOASOBI OCR TEST LIVE
1. \u591C\u306B\u99C6\u3051\u308B
''',
        existingSongs: const [],
      );
      final arena = parsePastedSongText(
        text: '''
YOASOBI ARENA TOUR 2026
1. \u30A2\u30A4\u30C9\u30EB
''',
        existingSongs: const [],
      );
      final nflying = parsePastedSongText(
        text: '''
2026 N.Flying LIVE IN SEOUL
1. Blue Moon
''',
        existingSongs: const [],
      );
      final awesomeStage = parsePastedSongText(
        text: '''
2026 Awesome Stage in Busan
1. \uD658\uC808\uAE30
''',
        existingSongs: const [],
      );
      final tdmFestival = parsePastedSongText(
        text: '''
2026 TDM MUSIC FESTIVAL in Tokyo
1. \uD658\uC808\uAE30
''',
        existingSongs: const [],
      );

      expect(yoasobi.inferredArtist, 'YOASOBI');
      expect(
        yoasobi.candidates.single.song?.title,
        '\u591C\u306B\u99C6\u3051\u308B',
      );
      expect(arena.inferredArtist, 'YOASOBI');
      expect(nflying.inferredArtist, 'N.Flying');
      expect(awesomeStage.inferredArtist, isEmpty);
      expect(tdmFestival.inferredArtist, isEmpty);
    });

    test('excludes plain text and standalone performance meta lines', () {
      final analysis = parsePastedSongText(
        text: '''
Plain text
PLAIN TEXT
plain text
MC
ENCORE
1. \u591C\u306B\u99C6\u3051\u308B
''',
        existingSongs: const [],
      );

      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        '\u591C\u306B\u99C6\u3051\u308B',
      ]);
    });

    test('strips OCR list numbers without damaging numeric song titles', () {
      final analysis = parsePastedSongText(
        text: '''
09. Love You Like That
09.Love You Like That
9. Love You Like That
9.Love You Like That
09) Love You Like That
09: Love You Like That
4242
1\uBD84
10\uBD84 \uC804
24\uC2DC\uAC04
1000 Years
1\u5206
''',
        existingSongs: const [],
      );

      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        'Love You Like That',
        'Love You Like That',
        'Love You Like That',
        'Love You Like That',
        'Love You Like That',
        'Love You Like That',
        '4242',
        '1\uBD84',
        '10\uBD84 \uC804',
        '24\uC2DC\uAC04',
        '1000 Years',
        '1\u5206',
      ]);
    });

    test(
      'keeps numbered Japanese song Encore but excludes standalone ENCORE',
      () {
        final analysis = parsePastedSongText(
          text: '''
2026 YOASOBI OCR TEST LIVE
1. \u591C\u306B\u99C6\u3051\u308B
2. \u3042\u306E\u5922\u3092\u306A\u305E\u3063\u3066
3. \u30CF\u30EB\u30B8\u30AA\u30F3
4. \u305F\u3076\u3093
5. \u7FA4\u9752
6. \u30CF\u30EB\u30AB
7. \u602A\u7269
8. \u512A\u3057\u3044\u66F8\u661F
9. \u4E09\u539F\u8272
10. \u30A2\u30F3\u30B3\u30FC\u30EB
MC
11. \u30E9\u30D6\u30EC\u30BF\u30FC
12. \u5927\u6B63\u6D6A\u6F2B
13. \u30C4\u30D0\u30E1
14. \u30DF\u30B9\u30BF\u30FC
15. \u597D\u304D\u3060
16. \u6D77\u306E\u307E\u306B\u307E\u306B
17. \u795D\u9AD8
18. \u30BB\u30D6\u30F3\u30C6\u30A3\u30FC\u30F3
19. \u30A2\u30A4\u30C9\u30EB
20. \u52C7\u8005
ENCORE
21. \u3082\u3057\u3082\u547D\u304C\u63CF\u3051\u305F\u3089
22. \u30A2\u30C9\u30D9\u30F3\u30C1\u30E3\u30FC
23. Biri-Biri
24. UNDEAD
25. Watch me!
''',
          existingSongs: const [],
        );

        final titles = analysis.drafts.map((draft) => draft.title).toList();
        expect(analysis.inferredArtist, 'YOASOBI');
        expect(titles, hasLength(25));
        expect(titles, contains('\u30A2\u30F3\u30B3\u30FC\u30EB'));
        expect(titles, contains('\u512A\u3057\u3044\u66F8\u661F'));
        expect(titles, contains('\u795D\u9AD8'));
        expect(titles, isNot(contains('MC')));
        expect(titles, isNot(contains('ENCORE')));
        expect(titles.first, '\u591C\u306B\u99C6\u3051\u308B');
        expect(titles.last, 'Watch me!');
      },
    );

    test('prioritizes explicit artist setlist header over event metadata', () {
      final analysis = parsePastedSongText(
        text: '''
\uAC15\uB0A8\uAD6C
GANGNAM GU
2026
AI\uB85C \uC0DD\uC131\uD55C \uCF58\uD150\uCE20
\uAC15\uB0A8\uD53C\uD06C\uB2C9 \uCF58\uC11C\uD2B8
N.Flying SETLIST
\uD658\uC808\uAE30
Blue Moon
Sunset
Songbird
\uC625\uD0D1\uBC29
ONFlyingNote
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, 'N.Flying');
      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        '\uD658\uC808\uAE30',
        'Blue Moon',
        'Sunset',
        'Songbird',
        '\uC625\uD0D1\uBC29',
      ]);
    });

    test('excludes all lines above explicit setlist header', () {
      final analysis = parsePastedSongText(
        text: '''
Beautiful
Mint Life 2026
5.30.Sat-5.31.Sun \uC11C\uC6B8 \uBB38\uD654\uBE44\uCD95\uAE30\uC9C0
N.Flying SETLIST
\uC625\uD0D1\uBC29
Blue Moon
The World is mine
\uB108 \uC5C6\uB294 \uB09C
Run Like This
Firefly
Autumn Dream
\uD53C\uC5C8\uC2B5\uB2C8\uB2E4.
\uD658\uC808\uAE30
\uD658\uC808\uAE30
Flashback
@NFlyingNote
''',
        existingSongs: const [],
      );

      final titles = analysis.drafts.map((draft) => draft.title).toList();
      expect(analysis.inferredArtist, 'N.Flying');
      expect(titles, hasLength(11));
      expect(titles.first, '\uC625\uD0D1\uBC29');
      expect(titles.last, 'Flashback');
      expect(
        titles.where((title) => title == '\uD658\uC808\uAE30'),
        hasLength(2),
      );
      expect(titles, isNot(contains('Beautiful')));
      expect(titles, isNot(contains('@NFlyingNote')));
    });

    test(
      'keeps standalone setlist artist empty and excludes event metadata',
      () {
        final analysis = parsePastedSongText(
          text: '''
2026 \uC644\uB3C4 \uAD6D\uC81C \uD574\uC870\uB958 \uBC15\uB78C\uD68C
SETLIST
Star
Blue Moon
Sunset
4242
\uAD7F\uBC24
\uC625\uD0D1\uBC29
''',
          existingSongs: const [],
        );

        expect(analysis.inferredArtist, isEmpty);
        expect(analysis.drafts.map((draft) => draft.title).toList(), [
          'Star',
          'Blue Moon',
          'Sunset',
          '4242',
          '\uAD7F\uBC24',
          '\uC625\uD0D1\uBC29',
        ]);
        expect(
          analysis.candidates.every(
            (candidate) =>
                candidate.status == PasteSongCandidateStatus.needsReview,
          ),
          isTrue,
        );
      },
    );

    test(
      'excludes standalone stage, generated-content, and account metadata',
      () {
        final analysis = parsePastedSongText(
          text: '''
N.Flying SETLIST
STAGE
Plain text
AI\uB85C \uC0DD\uC131\uD55C \uCF58\uD150\uCE20
A\uB85C \uC0DD\uC131\uD55C \uCF58\uD150\uCE20
4242
1\uBD84
10\uBD84 \uC804
24\uC2DC\uAC04
1000 Years
1\u5206
@NFlyingNote
''',
          existingSongs: const [],
        );

        expect(analysis.inferredArtist, 'N.Flying');
        expect(analysis.drafts.map((draft) => draft.title).toList(), [
          '4242',
          '1\uBD84',
          '10\uBD84 \uC804',
          '24\uC2DC\uAC04',
          '1000 Years',
          '1\u5206',
        ]);
      },
    );

    test('extracts artist from a sentence-style festival setlist header', () {
      final analysis = parsePastedSongText(
        text: '''
<2025 \uCCAD\uAC15 \uB300\uCD95\uC81C '\uD53C\uC5B4\uB0A0' \uC5D4\uD50C\uB77C\uC789 \uC14B\uB9AC\uC2A4\uD2B8>
01. \uB124\uAC00 \uB0B4 \uB9C8\uC74C\uC5D0 \uC790\uB9AC \uC7A1\uC558\uB2E4 (Into You)
(Rooftop)
02.
03. Firefly
04. Blue Moon
2025.05.22
05. Star
06. \uC9C4\uC9DC\uAC00 \uB098\uD0C0\uB0AC\uB2E4 (The Real)
''',
        existingSongs: const [],
      );

      final titles = analysis.drafts.map((draft) => draft.title).toList();
      expect(analysis.inferredArtist, '\uC5D4\uD50C\uB77C\uC789');
      expect(titles, contains('Rooftop'));
      expect(titles, contains('Firefly'));
      expect(titles, isNot(contains('02.')));
      expect(titles, isNot(contains('2025.05.22')));
    });

    test('uses concert header instead of weekday setlist metadata', () {
      final analysis = parsePastedSongText(
        text: '''
N.Flying \uC18C\uADF9\uC7A5 \uCF58\uC11C\uD2B8
\uC6B0\uB9CC\uD569
: \uC6B0\uB9AC \uB9CC\uB098\uC11C \uC598\uAE30 \uC880 \uD569\uC2DC\uB2E4
\uD1A0\uC694\uC77C \uC14B\uB9AC\uC2A4\uD2B8
Sunset
\uD30C\uB780\uBC30\uACBD
Video Therapy
\uBD04\uC774 \uBD80\uC2DC\uAC8C
\uD53C\uC5C8\uC2B5\uB2C8\uB2E4
ANYWAY
Waiting for...
Starlight
\uD314\uBD88\uCD9C
\uC625\uD0D1\uBC29
Autumn Dream
Stand By Me
ONFlyingNote
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, 'N.Flying');
      expect(analysis.drafts, hasLength(12));
      expect(analysis.drafts.first.title, 'Sunset');
      expect(analysis.drafts.last.title, 'Stand By Me');
    });

    test('infers a trailing logo artist while excluding school metadata', () {
      final analysis = parsePastedSongText(
        text: '''
Today's Set List
2025.05.21 \uACBD\uC778\uC5EC\uC790\uB300\uD559\uAD50
2025 \uCCAD\uCD98 \uD398\uC2A4\uD2F0\uBC8C
O Star
\uD53C\uC5C8\uC2B5\uB2C8\uB2E4. (Into Bloom)
3 Blue Moon
6 Sunset
@ \uC544\uC9C4\uC9DC\uC694. (Oh really.)
[\uC624\uB298\uC758 \uC14B\uB9AC\uC2A4\uD2B8 \uB2E4\uC2DC \uB4E3\uAE30.\u314B
NF
NFlying
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, 'NFlying');
      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        'Star',
        '\uD53C\uC5C8\uC2B5\uB2C8\uB2E4. (Into Bloom)',
        'Blue Moon',
        'Sunset',
        '\uC544\uC9C4\uC9DC\uC694. (Oh really.)',
      ]);
    });

    test(
      'does not infer a standalone short logo without supporting evidence',
      () {
        final nf = parsePastedSongText(text: 'NF', existingSongs: const []);
        final key = parsePastedSongText(text: 'KEY', existingSongs: const []);

        expect(nf.inferredArtist, isEmpty);
        expect(key.inferredArtist, isEmpty);
      },
    );

    test('infers a short logo when a related event brand supports it', () {
      final analysis = parsePastedSongText(
        text: '''
2024 KEYLAND
ON:AND ON
SET LIST
NUM
DATE: 2024. 1. 27. - 2024. 1. 28.
ADDRESS: OLYMPIC HANDBALL GYMNASIUM
01
02
NAME
Opening VCR
Good & Great
Saturday Night
G.O.A.T
(Greatest Of All Time)
ALBUM
Good & Great
BAD LOVE
NUM
KEY
15
16
NAME
DANCER TIME
Helium (\uD5EC\uB968)
Bound
MENT
Forever Yours
Total
END
ALBUM
BAD LOVE
Gasoline
2:35:46
''',
        existingSongs: const [],
      );

      final titles = analysis.drafts.map((draft) => draft.title).toList();
      expect(analysis.inferredArtist, 'KEY');
      expect(titles, [
        'Good & Great',
        'Saturday Night',
        'G.O.A.T (Greatest Of All Time)',
        'Helium (\uD5EC\uB968)',
        'Bound',
        'Forever Yours',
      ]);
      expect(titles, isNot(contains('BAD LOVE')));
      expect(titles, isNot(contains('Opening VCR')));
      expect(titles, isNot(contains('DANCER TIME')));
    });

    test(
      'keeps Live Without You in a KEYLAND NAME section without inferring it',
      () {
        final analysis = parsePastedSongText(
          text: '''
2024 KEYLAND
ON:AND ON
SET LIST
NUM
01
02
03
04
05
NAME
Good & Great
Live Without You
G.O.A.T
(Greatest Of All Time)
Helium (헬륨)
Forever Yours
ALBUM
Good & Great
BAD LOVE
Gasoline
KEY
''',
          existingSongs: const [],
        );

        final titles = analysis.drafts.map((draft) => draft.title).toList();
        expect(analysis.inferredArtist, 'KEY');
        expect(analysis.inferredArtist, isNot('Without You'));
        expect(titles, contains('Live Without You'));
        expect(titles, contains('G.O.A.T (Greatest Of All Time)'));
      },
    );

    test('stops a KEYLAND table after song 23 before QR narrative text', () {
      final numbers = List.generate(
        23,
        (index) => (index + 1).toString().padLeft(2, '0'),
      ).join('\n');
      final songNames = [
        ...List.generate(22, (index) => 'Song ${index + 1}'),
        'Forever Yours',
      ].join('\n');
      final analysis = parsePastedSongText(
        text:
            '''
2024 KEYLAND
SET LIST
NUM
$numbers
NAME
$songNames
공연을 함께해 주신 모든 분들께 진심으로 감사드립니다. 우리 앞으로도 오래오래 행복한 추억을 만들어요.
QR CODE
Total 2:35:46
END
ALBUM
Good & Great
BAD LOVE
KEY
''',
        existingSongs: const [],
      );

      final titles = analysis.drafts.map((draft) => draft.title).toList();
      expect(analysis.inferredArtist, 'KEY');
      expect(titles, hasLength(23));
      expect(titles.last, 'Forever Yours');
      expect(titles, isNot(contains('QR CODE')));
      expect(
        titles,
        isNot(
          contains('공연을 함께해 주신 모든 분들께 진심으로 감사드립니다. 우리 앞으로도 오래오래 행복한 추억을 만들어요.'),
        ),
      );
      expect(titles, isNot(contains('Good & Great')));
      expect(titles, isNot(contains('BAD LOVE')));
    });

    test('parses the full two-section KEYLAND table in order', () {
      final analysis = parsePastedSongText(
        text: '''
2024 KEYLAND
ONANDON
SET LIST
NUM
01
02
03
04
05
06
07
08
09
10
11
12
13
14
NAME
Opening VCR
Good & Great
Saturday Night
MENT
I Wanna Be
Easy To Love
미워 (The Duty of Love)
Heartless
Hologram
BAND TIME
BAD LOVE
Can't Say Goodbye
CoolAs
Live Without You
Killer
Intoxicating (with Kany)
Imagine
ALBUM
Good & Great
BAD LOVE
Gasoline
NUM
KEY
15
16
17
18
19
20
21
22
23
NAME
DANCER TIME
Helium (헬륨)
Bound
MENT
Another Life
Yellow Tape
MENT
Mirror, Mirror
G. O. A. T
(Greatest Of All Time)
ENCORE
I Can't Sleep
MENT
가솔린(Gasoline)
RE-ENCORE
Forever Yours
공연을 함께해 주신 모든 분들께 진심으로 감사드립니다. 우리 앞으로도 오래오래 행복한 추억을 만들어요.
Total
2:35:46
END
ALBUM
BAD LOVE
Gasoline
Good & Great
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, 'KEY');
      expect(analysis.inferredArtist, isNot(anyOf('Gasoline', 'Without You')));
      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        'Good & Great',
        'Saturday Night',
        'I Wanna Be',
        'Easy To Love',
        '미워 (The Duty of Love)',
        'Heartless',
        'Hologram',
        'BAD LOVE',
        "Can't Say Goodbye",
        'CoolAs',
        'Live Without You',
        'Killer',
        'Intoxicating (with Kany)',
        'Imagine',
        'Helium (헬륨)',
        'Bound',
        'Another Life',
        'Yellow Tape',
        'Mirror, Mirror',
        'G.O.A.T (Greatest Of All Time)',
        "I Can't Sleep",
        '가솔린(Gasoline)',
        'Forever Yours',
      ]);
    });

    test('parses the exact KEYLAND phone OCR text', () {
      final analysis = parsePastedSongText(
        text: '''
ONANDON
NUM
DATE:2024. 1. 27.- 2024. 1. 28.
ADDRESS: OLYMPIC HANDBALL GYMNASIUM
01
02
03
04
05
06
07
09
10
11
12
2024 KEYLAND
13
14
SET LIST
NAME
Opning VCR
Good & Great
Saturday Night
IWanna Be
Easy To Love
미워 (The Duty of Love)
MENT
Heartless
Hologram
BAND TIME
BAD LOVE
Can't Say Goodbye
CoolAs
Live Without You
Killer
MENT
Intoxicating (with Kany)
Imagine
ALBUM
Good & Great
BAD LOVE
IWanna Be
FACE
FACE
Killer
Hologram
BAD LOVE
Good & Great
Good & Great
Good & Great
Killer
Good & Great
FACE
NUM
KEY
15
16
17
18
19
20
21
22
23
NAME
DANCER TIME
Helium (헬륨)
Bound
MENT
Another Life
Yellow Tape
MENT
Mirror, Mirror
G.0.A.T
(Greatest Of All Time)
ENCORE
ICan't Sleep
MENT
가솔린(Gasoline)
RE-ENCORE
Forever Yours
이전아니g어 알지?
이는 꽃이아니아
내일일나서 선운해랑 일전혀 아나야
우뢰 다 여기 있었어
겨우시 출려가도 여기서먼나자
기버하면살이가주세.
저도 그력게요
Total
END
ALBUM
BAD LOVE
Gasoline
Gasoline
BAD LOVE
Good & Great
Gasoline
Gasoline
Gasoline
Forever Yours
2:35:46
''',
        existingSongs: const [],
      );

      final titles = analysis.drafts.map((draft) => draft.title).toList();
      expect(analysis.inferredArtist, 'KEY');
      expect(titles, hasLength(23));
      expect(analysis.candidates, hasLength(23));
      expect(titles, contains('Live Without You'));
      expect(titles, contains('G.O.A.T (Greatest Of All Time)'));
      expect(titles, contains('Forever Yours'));
      expect(titles, isNot(contains('이전아니g어 알지?')));
      expect(titles, isNot(contains('Gasoline')));
    });

    test('does not infer an artist from structured table cell values', () {
      final analysis = parsePastedSongText(
        text: '''
2024 KEYLAND
SET LIST
NUM
01
NAME
Live Without You
ALBUM
Gasoline
Good & Great
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, isEmpty);
      expect(analysis.inferredArtist, isNot(anyOf('Gasoline', 'Without You')));
      expect(analysis.drafts.single.title, 'Live Without You');
    });

    test('preserves dotted and ampersand title abbreviations in NAME', () {
      final analysis = parsePastedSongText(
        text: '''
2024 KEYLAND
SET LIST
NUM
01
02
03
04
NAME
G.O.A.T
(Greatest Of All Time)
F.T.W
U&I
A.B.C
ALBUM
Gasoline
KEY
''',
        existingSongs: const [],
      );

      expect(analysis.inferredArtist, 'KEY');
      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        'G.O.A.T (Greatest Of All Time)',
        'F.T.W',
        'U&I',
        'A.B.C',
      ]);
    });

    test('does not over-filter NAME and ALBUM outside table context', () {
      final analysis = parsePastedSongText(
        text: '''
N.Flying SETLIST
NAME
ALBUM
Blue Moon
''',
        existingSongs: const [],
      );

      expect(analysis.drafts.map((draft) => draft.title).toList(), [
        'NAME',
        'ALBUM',
        'Blue Moon',
      ]);
    });

    test(
      'keeps numeric song titles while cleaning repeated OCR number noise',
      () {
        final analysis = parsePastedSongText(
          text: '''
N.Flying SETLIST
O Star
3 Blue Moon
6 Sunset
@ \uC544\uC9C4\uC9DC\uC694.
7 Days
10\uBD84 \uC804
24\uC2DC\uAC04
1000 Years
4242
''',
          existingSongs: const [],
        );

        expect(analysis.drafts.map((draft) => draft.title).toList(), [
          'Star',
          'Blue Moon',
          'Sunset',
          '\uC544\uC9C4\uC9DC\uC694.',
          '7 Days',
          '10\uBD84 \uC804',
          '24\uC2DC\uAC04',
          '1000 Years',
          '4242',
        ]);
      },
    );

    test('excludes receipt metadata and long narrative noise', () {
      final analysis = parsePastedSongText(
        text: '''
N.Flying SETLIST
DATE: 2025.05.22
ADDRESS: SOME HALL
Star
TOTAL 2:35:46
\uC624\uB298 \uACF5\uC5F0\uC744 \uD568\uAED8\uD574 \uC8FC\uC154\uC11C \uC815\uB9D0 \uAC10\uC0AC\uD569\uB2C8\uB2E4. \uB2E4\uC74C\uC5D0\uB3C4 \uAF2D \uB9CC\uB098\uC694.
END
''',
        existingSongs: const [],
      );

      expect(analysis.drafts.map((draft) => draft.title).toList(), ['Star']);
    });

    test('handles empty input', () {
      final analysis = parsePastedSongText(text: '', existingSongs: const []);

      expect(analysis.inferredArtist, isEmpty);
      expect(analysis.drafts, isEmpty);
      expect(analysis.candidates, isEmpty);
    });
  });
}
