import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/backup/backup_models.dart';
import 'package:today_music/backup/backup_repository.dart';
import 'package:today_music/backup/backup_state.dart';

void main() {
  test('backup screen state blocks duplicate actions while busy', () {
    const account = BackupAccount(
      id: 'account-id',
      email: 'user@example.com',
      displayName: '사용자',
    );
    const summary = BackupSummary(songCount: 10, setCount: 2, favoriteCount: 3);
    final remote = RemoteBackupMetadata(
      fileId: 'file-id',
      modifiedAt: DateTime.parse('2026-06-20T12:00:00+09:00'),
      summary: summary,
    );

    final ready = BackupScreenState(
      status: BackupScreenStatus.ready,
      account: account,
      localSummary: summary,
      remoteBackup: remote,
    );
    final backingUp = ready.copyWith(status: BackupScreenStatus.backingUp);

    expect(ready.canStartBackup, isTrue);
    expect(ready.canStartRestore, isTrue);
    expect(backingUp.isBusy, isTrue);
    expect(backingUp.canStartBackup, isFalse);
    expect(backingUp.canStartRestore, isFalse);
  });
}
