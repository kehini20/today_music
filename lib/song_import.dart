import 'dart:convert';

import 'song.dart';

enum SongImportCandidateStatus {
  newSong,
  updateAvailable,
  identical,
  needsReview,
}

class SongImportChange {
  final String field;
  final String before;
  final String after;

  const SongImportChange({
    required this.field,
    required this.before,
    required this.after,
  });

  String get description {
    final beforeLabel = before.isEmpty ? '비어 있음' : before;
    return '$field: $beforeLabel → $after';
  }
}

class SongImportCandidate {
  final Song? incomingSong;
  final Song? existingSong;
  final Song? mergedSong;
  final SongImportCandidateStatus status;
  final List<SongImportChange> changes;

  const SongImportCandidate({
    required this.incomingSong,
    required this.existingSong,
    required this.mergedSong,
    required this.status,
    this.changes = const [],
  });
}

String normalizeSongIdentityPart(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String songIdentityKey(Song song) {
  return '${normalizeSongIdentityPart(song.artist)}\n'
      '${normalizeSongIdentityPart(song.title)}';
}

String looseSongIdentityKey(Song song) {
  String normalize(String value) {
    return normalizeSongIdentityPart(value)
        .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[~!@#$%^&*_+=|\\<>?;:,.·ㆍ`’‘"“”\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  return '${normalize(song.artist)}\n${normalize(song.title)}';
}

Song? findMatchingSong(Song incoming, Iterable<Song> existingSongs) {
  final exactKey = songIdentityKey(incoming);
  for (final song in existingSongs) {
    if (songIdentityKey(song) == exactKey) {
      return song;
    }
  }

  final looseKey = looseSongIdentityKey(incoming);
  for (final song in existingSongs) {
    if (looseSongIdentityKey(song) == looseKey) {
      return song;
    }
  }
  return null;
}

List<String> mergeSongTags(List<String> existing, List<String> incoming) {
  final merged = <String>[];
  final seen = <String>{};

  for (final tag in [...existing, ...incoming]) {
    final normalized = tag.trim();
    if (normalized.isEmpty) {
      continue;
    }
    final withHash = normalized.startsWith('#') ? normalized : '#$normalized';
    if (seen.add(withHash.toLowerCase())) {
      merged.add(withHash);
    }
  }
  return merged;
}

Song mergeImportedSong(Song existing, Song incoming) {
  return existing.copyWith(
    link: incoming.link.trim().isEmpty ? existing.link : incoming.link.trim(),
    memo: incoming.memo.trim().isEmpty ? existing.memo : incoming.memo.trim(),
    tags: mergeSongTags(existing.tags, incoming.tags),
  );
}

SongImportCandidate classifyImportedSong({
  required Song incoming,
  required Iterable<Song> existingSongs,
}) {
  if (incoming.artist.trim().isEmpty || incoming.title.trim().isEmpty) {
    return SongImportCandidate(
      incomingSong: incoming,
      existingSong: null,
      mergedSong: null,
      status: SongImportCandidateStatus.needsReview,
    );
  }

  final existing = findMatchingSong(incoming, existingSongs);
  if (existing == null) {
    return SongImportCandidate(
      incomingSong: incoming,
      existingSong: null,
      mergedSong: incoming,
      status: SongImportCandidateStatus.newSong,
    );
  }

  final merged = mergeImportedSong(existing, incoming);
  final changes = <SongImportChange>[
    if (merged.link != existing.link)
      SongImportChange(field: '링크', before: existing.link, after: merged.link),
    if (merged.memo != existing.memo)
      SongImportChange(field: '메모', before: existing.memo, after: merged.memo),
    if (!_sameTags(merged.tags, existing.tags))
      SongImportChange(
        field: '태그',
        before: existing.tags.join(' '),
        after: merged.tags.join(' '),
      ),
  ];

  return SongImportCandidate(
    incomingSong: incoming,
    existingSong: existing,
    mergedSong: merged,
    status: changes.isEmpty
        ? SongImportCandidateStatus.identical
        : SongImportCandidateStatus.updateAvailable,
    changes: changes,
  );
}

List<SongImportCandidate> classifyImportedSongs({
  required Iterable<Song> incomingSongs,
  required Iterable<Song> existingSongs,
}) {
  final comparisonSongs = existingSongs.toList();
  final candidates = <SongImportCandidate>[];

  for (final incoming in incomingSongs) {
    final candidate = classifyImportedSong(
      incoming: incoming,
      existingSongs: comparisonSongs,
    );
    candidates.add(candidate);
    if (candidate.status == SongImportCandidateStatus.newSong) {
      comparisonSongs.add(incoming);
    } else if (candidate.status == SongImportCandidateStatus.updateAvailable) {
      final existing = candidate.existingSong;
      final merged = candidate.mergedSong;
      if (existing != null && merged != null) {
        final index = comparisonSongs.indexWhere(
          (song) => identical(song, existing),
        );
        if (index != -1) {
          comparisonSongs[index] = merged;
        }
      }
    }
  }
  return candidates;
}

bool _sameTags(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

bool looksLikeTdmSongText(String text) {
  final lines = const LineSplitter().convert(text);
  return lines.any((line) => line.trim() == '[곡]') &&
      lines.any(
        (line) =>
            line.trimLeft().startsWith('가수명:') ||
            line.trimLeft().startsWith('가수:'),
      ) &&
      lines.any((line) => line.trimLeft().startsWith('제목:'));
}

List<Song> parseTdmSongText(String text) {
  if (!looksLikeTdmSongText(text)) {
    return const [];
  }

  final songs = <Song>[];
  final fields = <String, String>{};

  void flush() {
    final artist = fields['artist']?.trim() ?? '';
    final title = fields['title']?.trim() ?? '';
    if (artist.isNotEmpty && title.isNotEmpty) {
      songs.add(
        Song(
          artist: artist,
          title: title,
          memo: fields['memo']?.trim() ?? '',
          tags: _parseTags(fields['tags'] ?? ''),
          link: fields['link']?.trim() ?? '',
        ),
      );
    }
    fields.clear();
  }

  for (final rawLine in const LineSplitter().convert(text)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line == '[곡]') {
      flush();
      continue;
    }

    final separatorIndex = line.indexOf(':');
    if (separatorIndex == -1) {
      continue;
    }
    final key = line.substring(0, separatorIndex).trim();
    final value = line.substring(separatorIndex + 1).trim();
    switch (key) {
      case '가수':
      case '가수명':
        fields['artist'] = value;
      case '제목':
        fields['title'] = value;
      case '메모':
        fields['memo'] = value;
      case '태그':
        fields['tags'] = value;
      case '링크':
        fields['link'] = value;
    }
  }
  flush();
  return songs;
}

List<String> _parseTags(String text) {
  return text
      .split(RegExp(r'\s+'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .map((tag) => tag.startsWith('#') ? tag : '#$tag')
      .toList();
}
