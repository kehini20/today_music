class Song {
  final String artist;
  final String title;
  final List<String> tags;
  final String memo;
  final String link;
  final bool isFavorite;

  const Song({
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
      'artist': artist,
      'title': title,
      'tags': tags,
      'memo': memo,
      'link': link,
      'isFavorite': isFavorite,
    };
  }

  Song copyWith({
    String? artist,
    String? title,
    List<String>? tags,
    String? memo,
    String? link,
    bool? isFavorite,
  }) {
    return Song(
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
    return other is Song &&
        artist.trim().toLowerCase() == other.artist.trim().toLowerCase() &&
        title.trim().toLowerCase() == other.title.trim().toLowerCase();
  }

  @override
  int get hashCode =>
      Object.hash(artist.trim().toLowerCase(), title.trim().toLowerCase());
}

Map<String, List<Song>> songsByArtist(List<Song> songs) {
  final groupedSongs = <String, List<Song>>{};

  for (final song in songs) {
    groupedSongs.putIfAbsent(song.artist, () => []).add(song);
  }

  return groupedSongs;
}
