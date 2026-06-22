import 'dart:convert';

import '../song.dart';
import 'backup_models.dart';
import 'backup_validation.dart';

class BackupSerializer {
  final BackupValidator validator;

  const BackupSerializer({this.validator = const BackupValidator()});

  BackupDocument createDocument({
    required BackupSourceSnapshot source,
    required String appVersion,
    required DateTime createdAt,
    String platform = 'android',
  }) {
    final backupSongs = <BackupSong>[];
    final backedUpSongIds = <String>{};
    final songIdsByObject = Map<Song, String>.identity();
    final songIdsByLegacyKey = <String, List<String>>{};

    for (var index = 0; index < source.songs.length; index++) {
      final song = source.songs[index];
      final id = song.id.trim().isEmpty
          ? 'song-${(index + 1).toString().padLeft(6, '0')}'
          : song.id;
      if (!backedUpSongIds.add(id)) {
        throw FormatException('Cannot back up duplicate song id: $id.');
      }
      backupSongs.add(BackupSong.fromSong(id: id, song: song, order: index));
      songIdsByObject[song] = id;
      songIdsByLegacyKey.putIfAbsent(_legacySongKey(song), () => []).add(id);
    }

    final backupSets = <BackupSongSet>[];
    for (var index = 0; index < source.sets.length; index++) {
      final sourceSet = source.sets[index];
      final songIds = <String>[];
      for (final song in sourceSet.songs) {
        final legacyMatches = songIdsByLegacyKey[_legacySongKey(song)];
        final songId =
            (song.id.isNotEmpty && backedUpSongIds.contains(song.id)
                ? song.id
                : songIdsByObject[song]) ??
            (legacyMatches?.length == 1 ? legacyMatches!.single : null);
        if (songId == null) {
          throw FormatException(
            'Set ${sourceSet.name} references a song outside the song storage: '
            '${song.artist} - ${song.title}.',
          );
        }
        songIds.add(songId);
      }

      backupSets.add(
        BackupSongSet(
          id: sourceSet.id.trim().isEmpty
              ? 'set-${(index + 1).toString().padLeft(6, '0')}'
              : sourceSet.id,
          name: sourceSet.name,
          songIds: songIds,
          order: index,
        ),
      );
    }

    final document = BackupDocument(
      backupFormatVersion: currentBackupFormatVersion,
      appVersion: appVersion,
      createdAt: createdAt,
      platform: platform,
      summary: BackupSummary(
        songCount: backupSongs.length,
        setCount: backupSets.length,
        favoriteCount: backupSongs.where((song) => song.isFavorite).length,
      ),
      data: BackupData(
        songs: backupSongs,
        sets: backupSets,
        artistRandomSettings: BackupArtistRandomSettings(
          disabledArtists: source.disabledRandomArtists.toList()..sort(),
        ),
        selectedSetIds: List<String>.of(source.selectedSetIds),
        shareSettings: BackupShareSettings(
          defaultMessage: source.defaultShareMessage,
        ),
        appSettings: BackupAppSettings(
          randomMode: source.randomMode,
          artistOrder: List<String>.of(source.artistOrder),
        ),
      ),
    );
    validator.validateOrThrow(document);
    return document;
  }

  String encode(BackupDocument document, {bool pretty = true}) {
    validator.validateOrThrow(document);
    final encoder = pretty ? const JsonEncoder.withIndent('  ') : jsonEncode;
    if (encoder is JsonEncoder) {
      return encoder.convert(document.toJson());
    }
    return jsonEncode(document.toJson());
  }

  BackupDocument decode(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException('Backup root must be an object.');
    }
    final document = BackupDocument.fromJson(
      Map<String, Object?>.from(decoded),
    );
    validator.validateOrThrow(document);
    return document;
  }

  BackupRestoreSnapshot restore(BackupDocument document) {
    validator.validateOrThrow(document);

    final sortedSongs = List<BackupSong>.of(document.data.songs)
      ..sort((left, right) => left.order.compareTo(right.order));
    final songs = sortedSongs.map((song) => song.toSong()).toList();
    final songsById = {
      for (final backupSong in document.data.songs)
        backupSong.id: backupSong.toSong(),
    };

    final sortedSets = List<BackupSongSet>.of(document.data.sets)
      ..sort((left, right) => left.order.compareTo(right.order));
    final sets = sortedSets
        .map(
          (set) => BackupRestoredSet(
            id: set.id,
            name: set.name,
            songs: set.songIds.map((songId) => songsById[songId]!).toList(),
          ),
        )
        .toList();

    return BackupRestoreSnapshot(
      songs: songs,
      sets: sets,
      disabledRandomArtists: document.data.artistRandomSettings.disabledArtists
          .toSet(),
      selectedSetIds: List<String>.of(document.data.selectedSetIds),
      defaultShareMessage: document.data.shareSettings.defaultMessage,
      randomMode: document.data.appSettings.randomMode,
      artistOrder: List<String>.of(document.data.appSettings.artistOrder),
    );
  }

  String _legacySongKey(Song song) {
    return '${song.artist.trim().toLowerCase()}\u0000'
        '${song.title.trim().toLowerCase()}';
  }
}
