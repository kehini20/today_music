import 'backup_models.dart';

class BackupValidationResult {
  final List<String> errors;
  final List<String> warnings;

  const BackupValidationResult({required this.errors, required this.warnings});

  bool get isValid => errors.isEmpty;
}

class BackupValidationException implements Exception {
  final List<String> errors;

  const BackupValidationException(this.errors);

  @override
  String toString() => 'BackupValidationException: ${errors.join(' ')}';
}

class BackupValidator {
  final int maxSetCount;

  const BackupValidator({this.maxSetCount = 30});

  BackupValidationResult validate(BackupDocument document) {
    final errors = <String>[];
    final warnings = <String>[];

    if (document.backupFormatVersion != currentBackupFormatVersion) {
      errors.add(
        'Unsupported backup format version: '
        '${document.backupFormatVersion}.',
      );
    }
    if (!const {'android', 'web'}.contains(document.platform)) {
      errors.add('Unsupported backup platform: ${document.platform}.');
    }

    final songIds = <String>{};
    for (final song in document.data.songs) {
      if (!songIds.add(song.id)) {
        errors.add('Duplicate song id: ${song.id}.');
      }
      if (song.artist.trim().isEmpty) {
        errors.add('Song ${song.id} has an empty artist.');
      }
      if (song.title.trim().isEmpty) {
        errors.add('Song ${song.id} has an empty title.');
      }
      if (song.order < 0) {
        errors.add('Song ${song.id} has a negative order.');
      }
    }

    final setIds = <String>{};
    for (final set in document.data.sets) {
      if (!setIds.add(set.id)) {
        errors.add('Duplicate set id: ${set.id}.');
      }
      if (set.name.trim().isEmpty) {
        errors.add('Set ${set.id} has an empty name.');
      }
      if (set.order < 0) {
        errors.add('Set ${set.id} has a negative order.');
      }

      final uniqueSongIds = <String>{};
      for (final songId in set.songIds) {
        if (!uniqueSongIds.add(songId)) {
          errors.add('Set ${set.id} contains duplicate song id: $songId.');
        }
        if (!songIds.contains(songId)) {
          errors.add('Set ${set.id} references missing song id: $songId.');
        }
      }
    }

    if (document.data.sets.length > maxSetCount) {
      errors.add(
        'Set count ${document.data.sets.length} exceeds the limit '
        'of $maxSetCount.',
      );
    }

    final selectedSetIds = <String>{};
    for (final setId in document.data.selectedSetIds) {
      if (!selectedSetIds.add(setId)) {
        errors.add('Selected set ids contain duplicate id: $setId.');
      }
      if (!setIds.contains(setId)) {
        errors.add('Selected set id does not exist: $setId.');
      }
    }

    if (!const {
      'artistRandom',
      'songSets',
    }.contains(document.data.appSettings.randomMode)) {
      errors.add(
        'Unknown random mode: ${document.data.appSettings.randomMode}.',
      );
    }
    if (document.data.appSettings.randomMode == 'songSets' &&
        document.data.selectedSetIds.isEmpty) {
      warnings.add(
        'songSets mode has no selected sets and will fall back to artistRandom.',
      );
    }

    final actualFavoriteCount = document.data.songs
        .where((song) => song.isFavorite)
        .length;
    if (document.summary.songCount != document.data.songs.length) {
      errors.add('Summary songCount does not match songs.');
    }
    if (document.summary.setCount != document.data.sets.length) {
      errors.add('Summary setCount does not match sets.');
    }
    if (document.summary.favoriteCount != actualFavoriteCount) {
      errors.add('Summary favoriteCount does not match songs.');
    }

    return BackupValidationResult(errors: errors, warnings: warnings);
  }

  void validateOrThrow(BackupDocument document) {
    final result = validate(document);
    if (!result.isValid) {
      throw BackupValidationException(result.errors);
    }
  }
}
