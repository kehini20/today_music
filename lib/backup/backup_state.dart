import 'backup_models.dart';
import 'backup_repository.dart';

enum BackupScreenStatus {
  signedOut,
  signingIn,
  loadingBackupInfo,
  noRemoteBackup,
  ready,
  backingUp,
  restoring,
  error,
}

class BackupScreenState {
  final BackupScreenStatus status;
  final BackupAccount? account;
  final BackupSummary? localSummary;
  final RemoteBackupMetadata? remoteBackup;
  final String? errorMessage;

  const BackupScreenState({
    required this.status,
    this.account,
    this.localSummary,
    this.remoteBackup,
    this.errorMessage,
  });

  const BackupScreenState.signedOut()
    : this(status: BackupScreenStatus.signedOut);

  bool get isBusy => const {
    BackupScreenStatus.signingIn,
    BackupScreenStatus.loadingBackupInfo,
    BackupScreenStatus.backingUp,
    BackupScreenStatus.restoring,
  }.contains(status);

  bool get canStartBackup => account != null && localSummary != null && !isBusy;

  bool get canStartRestore =>
      account != null && remoteBackup != null && !isBusy;

  BackupScreenState copyWith({
    BackupScreenStatus? status,
    BackupAccount? account,
    BackupSummary? localSummary,
    RemoteBackupMetadata? remoteBackup,
    String? errorMessage,
    bool clearError = false,
    bool clearRemoteBackup = false,
  }) {
    return BackupScreenState(
      status: status ?? this.status,
      account: account ?? this.account,
      localSummary: localSummary ?? this.localSummary,
      remoteBackup: clearRemoteBackup
          ? null
          : remoteBackup ?? this.remoteBackup,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
