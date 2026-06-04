class Song {
  final String artist;
  final String title;
  final List<String> tags;
  final String memo;
  final String link;

  const Song({
    required this.artist,
    required this.title,
    required this.tags,
    this.memo = '',
    this.link = '',
  });

  factory Song.fromJson(Map<String, Object?> json) {
    final rawTags = json['tags'];

    return Song(
      artist: (json['artist'] as String?)?.trim() ?? '',
      title: (json['title'] as String?)?.trim() ?? '',
      tags: rawTags is List
          ? rawTags.whereType<String>().map((tag) => tag.trim()).toList()
          : const [],
      memo: (json['memo'] as String?)?.trim() ?? '',
      link: (json['link'] as String?)?.trim() ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'artist': artist,
      'title': title,
      'tags': tags,
      'memo': memo,
      'link': link,
    };
  }
}

Map<String, List<Song>> songsByArtist(List<Song> songs) {
  final groupedSongs = <String, List<Song>>{};

  for (final song in songs) {
    groupedSongs.putIfAbsent(song.artist, () => []).add(song);
  }

  return groupedSongs;
}
