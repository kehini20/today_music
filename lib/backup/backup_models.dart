import '../song.dart';

const int currentBackupFormatVersion = 1;
const String tdmDriveBackupFileName = 'tdm_backup.json';
const String tdmLocalSafetyBackupFileName = 'tdm_restore_safety_backup.json';

class BackupSummary {
  final int songCount;
  final int setCount;
  final int favoriteCount;

  const BackupSummary({
    required this.songCount,
    required this.setCount,
    required this.favoriteCount,
  });

  factory BackupSummary.fromJson(Map<String, Object?> json) {
    return BackupSummary(
      songCount: _requiredInt(json, 'songCount'),
      setCount: _requiredInt(json, 'setCount'),
      favoriteCount: _requiredInt(json, 'favoriteCount'),
    );
  }

  Map<String, Object?> toJson() => {
    'songCount': songCount,
    'setCount': setCount,
    'favoriteCount': favoriteCount,
  };
}

class BackupSong {
  final String id;
  final String artist;
  final String title;
  final List<String> tags;
  final String memo;
  final String link;
  final bool isFavorite;
  final int order;

  const BackupSong({
    required this.id,
    required this.artist,
    required this.title,
    required this.tags,
    required this.memo,
    required this.link,
    required this.isFavorite,
    required this.order,
  });

  factory BackupSong.fromJson(
    Map<String, Object?> json, {
    required int fallbackOrder,
  }) {
    return BackupSong(
      id: _requiredString(json, 'id'),
      artist: _requiredString(json, 'artist'),
      title: _requiredString(json, 'title'),
      tags: _optionalStringList(json, 'tags'),
      memo: _optionalString(json, 'memo'),
      link: _optionalString(json, 'link'),
      isFavorite: _optionalBool(json, 'isFavorite'),
      order: _optionalInt(json, 'order', fallbackOrder),
    );
  }

  factory BackupSong.fromSong({
    required String id,
    required Song song,
    required int order,
  }) {
    return BackupSong(
      id: id,
      artist: song.artist,
      title: song.title,
      tags: List<String>.of(song.tags),
      memo: song.memo,
      link: song.link,
      isFavorite: song.isFavorite,
      order: order,
    );
  }

  Song toSong() {
    return Song(
      id: id,
      artist: artist,
      title: title,
      tags: List<String>.of(tags),
      memo: memo,
      link: link,
      isFavorite: isFavorite,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'artist': artist,
    'title': title,
    'tags': tags,
    'memo': memo,
    'link': link,
    'isFavorite': isFavorite,
    'order': order,
  };
}

class BackupSongSet {
  final String id;
  final String name;
  final List<String> songIds;
  final int order;

  const BackupSongSet({
    required this.id,
    required this.name,
    required this.songIds,
    required this.order,
  });

  factory BackupSongSet.fromJson(
    Map<String, Object?> json, {
    required int fallbackOrder,
  }) {
    return BackupSongSet(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      songIds: _requiredStringList(json, 'songIds'),
      order: _optionalInt(json, 'order', fallbackOrder),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'order': order,
  };
}

class BackupArtistRandomSettings {
  final List<String> disabledArtists;

  const BackupArtistRandomSettings({required this.disabledArtists});

  factory BackupArtistRandomSettings.fromJson(Map<String, Object?> json) {
    return BackupArtistRandomSettings(
      disabledArtists: _optionalStringList(json, 'disabledArtists'),
    );
  }

  Map<String, Object?> toJson() => {'disabledArtists': disabledArtists};
}

class BackupShareSettings {
  final String defaultMessage;

  const BackupShareSettings({required this.defaultMessage});

  factory BackupShareSettings.fromJson(Map<String, Object?> json) {
    return BackupShareSettings(
      defaultMessage: _optionalString(json, 'defaultMessage'),
    );
  }

  Map<String, Object?> toJson() => {'defaultMessage': defaultMessage};
}

class BackupAppSettings {
  final String randomMode;
  final List<String> artistOrder;

  const BackupAppSettings({
    required this.randomMode,
    this.artistOrder = const [],
  });

  factory BackupAppSettings.fromJson(Map<String, Object?> json) {
    return BackupAppSettings(
      randomMode: _optionalString(json, 'randomMode', fallback: 'artistRandom'),
      artistOrder: _optionalStringList(json, 'artistOrder'),
    );
  }

  Map<String, Object?> toJson() => {
    'randomMode': randomMode,
    'artistOrder': artistOrder,
  };
}

class BackupData {
  final List<BackupSong> songs;
  final List<BackupSongSet> sets;
  final BackupArtistRandomSettings artistRandomSettings;
  final List<String> selectedSetIds;
  final BackupShareSettings shareSettings;
  final BackupAppSettings appSettings;

  const BackupData({
    required this.songs,
    required this.sets,
    required this.artistRandomSettings,
    required this.selectedSetIds,
    required this.shareSettings,
    required this.appSettings,
  });

  factory BackupData.fromJson(Map<String, Object?> json) {
    final rawSongs = _requiredList(json, 'songs');
    final rawSets = _requiredList(json, 'sets');

    return BackupData(
      songs: [
        for (var index = 0; index < rawSongs.length; index++)
          BackupSong.fromJson(
            _requiredMapValue(rawSongs[index], 'songs[$index]'),
            fallbackOrder: index,
          ),
      ],
      sets: [
        for (var index = 0; index < rawSets.length; index++)
          BackupSongSet.fromJson(
            _requiredMapValue(rawSets[index], 'sets[$index]'),
            fallbackOrder: index,
          ),
      ],
      artistRandomSettings: BackupArtistRandomSettings.fromJson(
        _optionalMap(json, 'artistRandomSettings'),
      ),
      selectedSetIds: _optionalStringList(json, 'selectedSetIds'),
      shareSettings: BackupShareSettings.fromJson(
        _optionalMap(json, 'shareSettings'),
      ),
      appSettings: BackupAppSettings.fromJson(
        _optionalMap(json, 'appSettings'),
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'songs': songs.map((song) => song.toJson()).toList(),
    'sets': sets.map((set) => set.toJson()).toList(),
    'artistRandomSettings': artistRandomSettings.toJson(),
    'selectedSetIds': selectedSetIds,
    'shareSettings': shareSettings.toJson(),
    'appSettings': appSettings.toJson(),
  };
}

class BackupDocument {
  final int backupFormatVersion;
  final String appVersion;
  final DateTime createdAt;
  final String platform;
  final BackupSummary summary;
  final BackupData data;

  const BackupDocument({
    required this.backupFormatVersion,
    required this.appVersion,
    required this.createdAt,
    required this.platform,
    required this.summary,
    required this.data,
  });

  factory BackupDocument.fromJson(Map<String, Object?> json) {
    final createdAtText = _requiredString(json, 'createdAt');
    final createdAt = DateTime.tryParse(createdAtText);
    if (createdAt == null) {
      throw const FormatException('createdAt must be an ISO-8601 date.');
    }

    return BackupDocument(
      backupFormatVersion: _requiredInt(json, 'backupFormatVersion'),
      appVersion: _requiredString(json, 'appVersion'),
      createdAt: createdAt,
      platform: _requiredString(json, 'platform'),
      summary: BackupSummary.fromJson(_requiredMap(json, 'summary')),
      data: BackupData.fromJson(_requiredMap(json, 'data')),
    );
  }

  Map<String, Object?> toJson() => {
    'backupFormatVersion': backupFormatVersion,
    'appVersion': appVersion,
    'createdAt': _formatIso8601WithOffset(createdAt),
    'platform': platform,
    'summary': summary.toJson(),
    'data': data.toJson(),
  };
}

class BackupSourceSet {
  final String id;
  final String name;
  final List<Song> songs;

  const BackupSourceSet({
    required this.id,
    required this.name,
    required this.songs,
  });
}

class BackupSourceSnapshot {
  final List<Song> songs;
  final List<BackupSourceSet> sets;
  final Set<String> disabledRandomArtists;
  final List<String> selectedSetIds;
  final String defaultShareMessage;
  final String randomMode;
  final List<String> artistOrder;

  const BackupSourceSnapshot({
    required this.songs,
    required this.sets,
    required this.disabledRandomArtists,
    required this.selectedSetIds,
    required this.defaultShareMessage,
    required this.randomMode,
    this.artistOrder = const [],
  });
}

class BackupRestoredSet {
  final String id;
  final String name;
  final List<Song> songs;

  const BackupRestoredSet({
    required this.id,
    required this.name,
    required this.songs,
  });
}

class BackupRestoreSnapshot {
  final List<Song> songs;
  final List<BackupRestoredSet> sets;
  final Set<String> disabledRandomArtists;
  final List<String> selectedSetIds;
  final String defaultShareMessage;
  final String randomMode;
  final List<String> artistOrder;

  const BackupRestoreSnapshot({
    required this.songs,
    required this.sets,
    required this.disabledRandomArtists,
    required this.selectedSetIds,
    required this.defaultShareMessage,
    required this.randomMode,
    this.artistOrder = const [],
  });
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

String _optionalString(
  Map<String, Object?> json,
  String key, {
  String fallback = '',
}) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! String) {
    throw FormatException('$key must be a string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

int _optionalInt(Map<String, Object?> json, String key, int fallback) {
  final value = json[key];
  if (value == null) {
    return fallback;
  }
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

bool _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return false;
  }
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be an array.');
  }
  return List<Object?>.from(value);
}

List<String> _requiredStringList(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('$key is required.');
  }
  return _optionalStringList(json, key);
}

List<String> _optionalStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const [];
  }
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be an array of strings.');
  }
  return value.cast<String>().toList();
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('$key is required.');
  }
  return _requiredMapValue(json[key], key);
}

Map<String, Object?> _optionalMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const {};
  }
  return _requiredMapValue(value, key);
}

Map<String, Object?> _requiredMapValue(Object? value, String path) {
  if (value is! Map) {
    throw FormatException('$path must be an object.');
  }
  return Map<String, Object?>.from(value);
}

String _formatIso8601WithOffset(DateTime value) {
  if (value.isUtc) {
    return value.toIso8601String();
  }

  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absoluteMinutes = offset.inMinutes.abs();
  final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
  final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
  return '${value.toIso8601String()}$sign$hours:$minutes';
}
