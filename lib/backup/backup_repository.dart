import 'backup_models.dart';

abstract interface class BackupLocalDataRepository {
  Future<BackupSourceSnapshot> readCurrentData();

  Future<void> replaceAll(BackupRestoreSnapshot snapshot);
}

abstract interface class BackupSafetyRepository {
  Future<void> writeSafetyBackup(String jsonText);

  Future<String?> readSafetyBackup();
}

class RemoteBackupMetadata {
  final String fileId;
  final DateTime modifiedAt;
  final BackupSummary summary;

  const RemoteBackupMetadata({
    required this.fileId,
    required this.modifiedAt,
    required this.summary,
  });
}

abstract interface class BackupRemoteRepository {
  Future<RemoteBackupMetadata?> findBackup();

  Future<String> downloadBackup(String fileId);

  Future<RemoteBackupMetadata> uploadReplacement({
    required String jsonText,
    required RemoteBackupMetadata? previousBackup,
  });
}

abstract interface class BackupAccountRepository {
  Future<BackupAccount?> signIn();

  Future<BackupAccount?> restorePreviousSession();

  Future<void> signOut();
}

class BackupAccount {
  final String id;
  final String email;
  final String displayName;

  const BackupAccount({
    required this.id,
    required this.email,
    required this.displayName,
  });
}
