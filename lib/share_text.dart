import 'song.dart';

const String tdmServiceShareLine =
    '오늘의 한 곡 뽑기 → https://today-music.pages.dev/';

String buildSongShareText({
  required Song song,
  String defaultMessage = '',
  bool includeSongLink = true,
  bool includeTodayTag = true,
}) {
  final lines = <String>['🎧 ${song.artist} - ${song.title}'];
  final trimmedMessage = defaultMessage.trim();
  final link = song.link.trim();
  final tags = [
    ...song.tags.where((tag) => tag != '#오늘의한곡'),
    if (includeTodayTag) '#오늘의한곡',
  ];

  if (trimmedMessage.isNotEmpty) {
    lines.addAll(['', trimmedMessage]);
  }

  if (includeSongLink && link.isNotEmpty) {
    lines.addAll(['', link]);
  }

  if (tags.isNotEmpty) {
    lines.addAll(['', tags.join(' '), tdmServiceShareLine]);
  } else {
    lines.addAll(['', tdmServiceShareLine]);
  }

  return lines.join('\n');
}
