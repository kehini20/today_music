int _songIdSequence = 0;

String createSongId() {
  _songIdSequence++;
  return 'song-${DateTime.now().microsecondsSinceEpoch}-$_songIdSequence';
}

class Song {
  final String id;
  final String artist;
  final String title;
  final List<String> tags;
  final String memo;
  final String link;
  final bool isFavorite;

  const Song({
    this.id = '',
    required this.artist,
    required this.title,
    required this.tags,
    this.memo = '',
    this.link = '',
    this.isFavorite = false,
  });

  factory Song.fromJson(Map<String, Object?> json) {
    final rawTags = json['tags'];

    return Song(
      id: (json['id'] as String?)?.trim() ?? '',
      artist: (json['artist'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? '',
      tags: rawTags is List
          ? rawTags.whereType<String>().map((tag) => tag.trim()).toList()
          : const [],
      memo: (json['memo'] as String?)?.trim() ?? '',
      link: (json['link'] as String?)?.trim() ?? '',
      isFavorite: json['isFavorite'] == true,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'artist': artist,
      'title': title,
      'tags': tags,
      'memo': memo,
      'link': link,
      'isFavorite': isFavorite,
    };
  }

  Song copyWith({
    String? id,
    String? artist,
    String? title,
    List<String>? tags,
    String? memo,
    String? link,
    bool? isFavorite,
  }) {
    return Song(
      id: id ?? this.id,
      artist: artist ?? this.artist,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      memo: memo ?? this.memo,
      link: link ?? this.link,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! Song) {
      return false;
    }
    if (id.isNotEmpty && other.id.isNotEmpty) {
      return id == other.id;
    }
    return artist.trim().toLowerCase() == other.artist.trim().toLowerCase() &&
        title.trim().toLowerCase() == other.title.trim().toLowerCase();
  }

  @override
  int get hashCode => id.isNotEmpty
      ? id.hashCode
      : Object.hash(artist.trim().toLowerCase(), title.trim().toLowerCase());
}

List<Song> ensureSongIds(Iterable<Song> songs) {
  final usedIds = <String>{};
  return [
    for (final song in songs)
      if (song.id.isNotEmpty && usedIds.add(song.id))
        song
      else
        song.copyWith(id: _nextUniqueSongId(usedIds)),
  ];
}

String _nextUniqueSongId(Set<String> usedIds) {
  var id = createSongId();
  while (!usedIds.add(id)) {
    id = createSongId();
  }
  return id;
}

Map<String, List<Song>> songsByArtist(List<Song> songs) {
  final groupedSongs = <String, List<Song>>{};

  for (final song in songs) {
    groupedSongs.putIfAbsent(song.artist, () => []).add(song);
  }

  return groupedSongs;
}
