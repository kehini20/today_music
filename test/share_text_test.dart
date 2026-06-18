import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/share_text.dart';
import 'package:today_music/song.dart';

void main() {
  const song = Song(
    artist: 'N.Flying',
    title: 'Blue Moon',
    tags: ['#엔플라잉'],
    link: 'https://youtu.be/example',
  );

  test('builds the new default share message', () {
    expect(
      buildSongShareText(song: song),
      '🎧 N.Flying - Blue Moon\n'
      '\n'
      'https://youtu.be/example\n'
      '\n'
      '#엔플라잉 #오늘의한곡\n'
      '오늘의 한 곡 뽑기 → https://today-music.pages.dev/',
    );
  });

  test('song link option does not remove the TDM service link', () {
    final text = buildSongShareText(song: song, includeSongLink: false);

    expect(text, isNot(contains('https://youtu.be/example')));
    expect(text, contains(tdmServiceShareLine));
  });

  test('today tag option preserves artist tags', () {
    final text = buildSongShareText(song: song, includeTodayTag: false);

    expect(text, contains('#엔플라잉'));
    expect(text, isNot(contains('#오늘의한곡')));
  });

  test('handles empty link and empty artist tags', () {
    const plainSong = Song(artist: 'ONEWE', title: 'ICARUS', tags: []);
    final text = buildSongShareText(
      song: plainSong,
      includeSongLink: true,
      includeTodayTag: false,
    );

    expect(text, '🎧 ONEWE - ICARUS\n\n$tdmServiceShareLine');
  });

  test('keeps the editable default message', () {
    final text = buildSongShareText(
      song: song,
      defaultMessage: '오늘은 이 곡을 들어보세요.',
    );

    expect(text, startsWith('🎧 N.Flying - Blue Moon\n\n오늘은 이 곡을 들어보세요.'));
  });
}
