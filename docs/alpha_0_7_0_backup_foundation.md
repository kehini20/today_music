# TDM Alpha 0.7.0 Android 수동 백업·복원 기반 설계

## 범위

- Alpha 0.7.0의 Google 로그인 및 Drive 백업·복원은 Android에만 제공한다.
- 사용자가 `지금 백업` 또는 `백업 불러오기`를 누른 경우에만 데이터가 이동한다.
- Web에는 진입 버튼, 준비 중 문구, 로그인 및 Drive 코드를 노출하지 않는다.
- 기존 TXT 내보내기·불러오기는 Android와 Web 모두 그대로 유지한다.
- 이 단계에서는 JSON 모델, 직렬화, 검증, 저장소 경계, 화면 상태와 안전한 흐름을 고정한다.
- Google Cloud 프로젝트 설정이 필요한 실제 로그인 및 Drive API 연결은 다음 구현 단계에서 연결한다.

## 현재 저장 구조 조사

현재 영구 저장소는 모두 `SharedPreferences`이며 별도 로컬 JSON 파일이나 데이터베이스는 없다.

| 저장 키 | 형식 | 모델/값 | 시작 시 로드 | 기록 시점 | 백업 |
| --- | --- | --- | --- | --- | --- |
| `tdm_alpha_songs` | JSON 문자열 배열 | `Song` | `SongStorage.loadSongs` | 곡 추가·수정·삭제·초기화·TXT 가져오기 | 포함 |
| `tdm_song_sets` | JSON 문자열 배열 | `SongSet` | `SongStorage.loadSongSets` | 세트 추가·수정·삭제·곡 구성 변경 | 포함 |
| `tdm_random_mode` | 문자열 | `artistRandom` / `songSets` | `SongStorage.loadRandomMode` | 랜덤 모드 변경 | 포함 |
| `tdm_selected_song_set_ids` | 문자열 목록 | 선택된 세트 ID | `SongStorage.loadSelectedSongSetIds` | 세트 랜덤 선택 변경 | 포함 |
| `tdm_default_share_message` | 문자열 | 기본 공유 문구 | `SongStorage.loadDefaultShareMessage` | 설정에서 공유 문구 저장 | 포함 |
| `tdm_disabled_random_artists` | 문자열 목록 | 랜덤에서 제외한 가수명 | `SongStorage.loadDisabledRandomArtists` | 가수별 랜덤 활성 상태 변경 | 포함 |
| `sample_prompt_checked` | 불리언 | 샘플 곡 안내 확인 | `SongStorage.isSamplePromptChecked` | 안내 확인·초기화 | 제외 |
| `tdm_last_add_song_tab` | 문자열 | `individual` / `paste` | `SongStorage.loadLastAddSongTab` | 곡 추가 탭 변경 | 제외 |

앱 시작 시 `TodayMusicHomePageState._loadSavedSongs`가 위 값을 불러온다. 저장 메서드와 `SongSet`은 현재 `lib/main.dart`, `Song`은 `lib/song.dart`에 있다.

### 현재 모델의 제약

- `Song` 필드: `artist`, `title`, `tags`, `memo`, `link`, `isFavorite`
- `Song`에는 영구 ID와 추가 시각이 없다.
- `SongSet` 필드: `id`, `name`, `songs`
- 세트는 곡 ID가 아니라 `Song` 객체 전체를 중복 저장한다.
- 앱에서 곡 동일성은 공백을 제거하지 않고 가수명·곡명을 trim/lowercase 한 조합으로 판단한다.

기존 사용자 저장 형식을 바꾸지 않기 위해 로컬 모델에는 ID나 시각을 추가하지 않는다. 백업 생성 시 곡 순서에 따라 `song-000001` 형식의 백업 전용 ID를 만들고, 세트의 곡 객체를 해당 ID 참조로 정규화한다. 같은 가수명·곡명이 중복되거나 세트가 전체 곡 저장소에 없는 곡을 참조하면 백업 생성을 중단한다.

## 백업 포함·제외 정책

### 포함

- 전체 곡과 현재 `Song`의 모든 사용자 데이터
- 곡 순서
- 즐겨찾기 상태
- 전체 세트, 세트 ID·이름·순서·곡 참조
- 가수별 랜덤 비활성 목록
- 선택된 세트 ID
- 랜덤 모드
- 기본 공유 문구

### 제외

- Google 로그인 토큰, 계정 인증 정보
- 광고 원격 설정과 이미지 캐시
- OCR 원문·분석 중 후보
- 검색어, 정렬 방식, 스크롤 위치, 현재 탭 등 화면 상태
- 샘플 곡 안내 확인 상태
- 마지막 곡 추가 탭
- 현재 뽑힌 곡, 스폰서 곡 여부, 공유 입력창 임시 내용
- 빌드 정보와 디버그 로그

`#오늘의한곡 포함`과 `링크 포함`은 현재 영구 저장되지 않고 앱 실행 중에만 유지되므로 백업 대상이 아니다. 추후 이 값을 사용자 설정으로 영구 저장하게 되면 `shareSettings`에 선택 필드로 추가한다.

## 백업 JSON 스키마

```json
{
  "backupFormatVersion": 1,
  "appVersion": "0.7.0",
  "createdAt": "2026-06-20T12:00:00+09:00",
  "platform": "android",
  "summary": {
    "songCount": 1,
    "setCount": 1,
    "favoriteCount": 1
  },
  "data": {
    "songs": [
      {
        "id": "song-000001",
        "artist": "KEY",
        "title": "Good & Great",
        "tags": ["#KEYLAND"],
        "memo": "",
        "link": "",
        "isFavorite": true,
        "order": 0
      }
    ],
    "sets": [
      {
        "id": "set-id",
        "name": "KEYLAND",
        "songIds": ["song-000001"],
        "order": 0
      }
    ],
    "artistRandomSettings": {
      "disabledArtists": []
    },
    "selectedSetIds": ["set-id"],
    "shareSettings": {
      "defaultMessage": ""
    },
    "appSettings": {
      "randomMode": "songSets"
    }
  }
}
```

### 형식 버전 정책

- 앱 버전과 `backupFormatVersion`을 분리한다.
- 현재 지원 형식은 `1`이다.
- 루트, `data`, `songs`, `sets`와 필수 식별 필드가 없으면 복원을 중단한다.
- 알 수 없는 필드는 무시한다.
- 형식 1 안에서 나중에 추가되는 선택 필드는 기본값을 사용한다.
- 지원하지 않는 형식 버전은 추측해서 변환하지 않고 복원을 중단한다.
- 형식 변경이 필요할 때 `BackupMigrator`를 추가하고 변환 테스트를 먼저 만든다.

## 코드 구조

| 파일 | 역할 |
| --- | --- |
| `lib/backup/backup_models.dart` | JSON 문서, 요약, 곡·세트·설정 모델, 앱 데이터 입출력 스냅샷 |
| `lib/backup/backup_serializer.dart` | 앱 데이터에서 문서 생성, UTF-8 JSON 직렬화·역직렬화, 복원 스냅샷 생성 |
| `lib/backup/backup_validation.dart` | 형식 버전, 요약, ID, 참조, 설정 값, 세트 상한 검증 |
| `lib/backup/backup_repository.dart` | 로컬 데이터, 안전 백업, 계정, 원격 Drive 저장소 인터페이스 |
| `lib/backup/backup_state.dart` | Android 백업 화면 상태와 작업 중 중복 실행 방지 |

Drive 구현은 `BackupRemoteRepository`, 로그인 구현은 `BackupAccountRepository` 뒤에 둔다. 따라서 JSON 생성·복원 검증은 Google API 없이 테스트할 수 있다.

## 복원 전 검증

복원 파일 전체를 메모리에서 파싱하고 다음 검증이 모두 끝나기 전에는 로컬 저장소를 변경하지 않는다.

- JSON 루트와 필수 배열
- 지원 형식 버전과 Android 플랫폼
- ISO-8601 생성 시각
- 곡·세트 ID 중복
- 빈 가수명·곡명·세트명
- 음수 순서
- 한 세트 안의 곡 ID 중복
- 존재하지 않는 곡 ID 참조
- 존재하지 않는 선택 세트 ID
- 최대 세트 수 30개
- `artistRandom` / `songSets` 외 랜덤 모드
- 실제 데이터와 요약 개수 일치

알 수 없는 필드와 형식 1의 선택 필드 누락은 허용한다. `songSets`인데 선택 세트가 없으면 경고를 남기고 적용 시 `artistRandom`으로 안전하게 보정한다.

## 수동 백업 흐름

1. 로그인과 `drive.appdata` 권한을 확인한다.
2. 현재 SharedPreferences 데이터를 읽어 `BackupSourceSnapshot`을 만든다.
3. JSON 문서를 생성하고 자체 검증한다.
4. `spaces=appDataFolder`에서 고정 파일명 `tdm_backup.json`을 조회한다.
5. 기존 백업이 있으면 현재 기기/Drive 요약과 시각을 확인창에 표시한다.
6. 현재 곡이 0개이고 기존 백업이 있으면 강한 경고를 한 번 더 표시한다.
7. 임시 이름으로 새 파일을 업로드하고 다운로드해 해시 또는 바이트를 확인한다.
8. 검증이 끝난 새 파일만 정식 백업으로 교체한다.
9. 성공 후에만 화면의 마지막 백업 시각과 요약을 갱신한다.
10. 기존 파일 정리 실패는 새 백업 성공과 별도로 기록하고 다음 조회 때 중복을 정리한다.

`appDataFolder` 파일은 휴지통으로 이동할 수 없으므로 교체 시 삭제 또는 파일 내용 업데이트의 실패 순서를 주의한다. 가장 단순한 안전 방식은 기존 파일 ID의 내용 업데이트 전에 새 파일 업로드·검증을 완료하고, 새 파일을 정식 파일로 선택한 뒤 이전 파일을 삭제하는 것이다.

## 수동 복원과 로컬 안전 백업

1. Drive 파일을 다운로드한다.
2. JSON 파싱과 전체 검증을 완료한다.
3. 현재 기기/Drive 요약과 백업 시각을 확인창에 표시한다.
4. 현재 데이터를 같은 JSON 형식으로 생성한다.
5. 앱 지원 디렉터리에 `tdm_restore_safety_backup.json.tmp`을 쓴 뒤 flush하고 정식 파일명으로 교체한다.
6. 안전 백업을 다시 읽고 검증한다.
7. `restore_in_progress` 표시를 기록한다.
8. 복원 스냅샷을 SharedPreferences 키에 적용한다.
9. 저장값을 다시 읽어 요약과 참조를 검증한다.
10. 성공하면 `restore_in_progress`를 지우고 앱 상태를 재로드한다.
11. 실패하면 안전 백업으로 기존 데이터를 복구하고 오류를 표시한다.

SharedPreferences의 여러 키는 하나의 원자적 트랜잭션이 아니다. 따라서 복원 중 앱이 종료될 가능성까지 다루려면 시작 표시와 안전 백업이 필요하다. 앱 시작 시 `restore_in_progress`가 남아 있으면 일반 데이터 로드 전에 안전 백업 복구를 제안하거나 자동 롤백해야 한다. 0.7.0에서는 최근 안전 백업 1개만 유지한다. 안전 백업 생성이나 재검증에 실패하면 Drive 복원을 시작하지 않는다.

## Android 화면 상태

`BackupScreenStatus`는 다음 상태를 제공한다.

- `signedOut`
- `signingIn`
- `loadingBackupInfo`
- `noRemoteBackup`
- `ready`
- `backingUp`
- `restoring`
- `error`

작업 중에는 로그인, 백업, 복원, 로그아웃 버튼을 중복 실행할 수 없게 한다. 로그인 전에는 데이터가 Google Drive 앱 전용 공간에 저장되고 자동 동기화하지 않는다는 점을 안내한다. 로그인 후에는 계정, 현재 기기 요약, Drive 백업 요약을 분리해 표시한다.

Web 빌드에는 이 화면의 진입점과 Google 구현을 import하지 않는다. 다음 단계에서 조건부 export 또는 Android 전용 구현 파일을 사용하고, `kIsWeb` 조건으로 메인 상단 버튼 자체를 만들지 않는다.

## Google 로그인·Drive 구현 후보

### 권장 패키지

- `google_sign_in` 7.x: Android 계정 인증과 필요한 범위의 사용자 승인
- `googleapis`: Drive API v3 클라이언트
- `extension_google_sign_in_as_googleapis_auth`: 승인 결과를 `googleapis`용 인증 클라이언트로 연결
- `path_provider`: 앱 내부 안전 백업 파일 위치
- 선택: `crypto`: 업로드 후 바이트 해시 검증

패키지는 실제 Google Cloud OAuth 클라이언트가 준비되는 다음 단계에서 추가한다. 이번 단계에 사용하지 않는 Google 패키지를 넣어 Web와 Android 빌드에 불필요한 네이티브 변경을 만들지 않는다.

### 최소 권한

`https://www.googleapis.com/auth/drive.appdata`

이 범위는 앱 자체 구성 데이터를 Drive 앱 전용 공간에서 조회·관리하며 전체 Drive 접근 권한을 주지 않는다. `drive`, `drive.readonly`, `drive.file`은 요청하지 않는다.

### Drive API 사용

- 생성: 파일 metadata의 `parents`에 `appDataFolder`
- 조회: `files.list(spaces: 'appDataFolder')`
- 다운로드: 조회한 파일 ID의 media 다운로드
- 교체: 새 파일 업로드·검증 후 이전 파일 정리
- 파일명: `tdm_backup.json`
- MIME: `application/json`

앱 전용 공간은 사용자 Drive UI에 노출되지 않고 다른 앱이 접근할 수 없다. 폴더 안 파일은 공유할 수 없고 휴지통 이동도 지원하지 않는다.

## Google Cloud Console 및 Android 설정

1. 최종 배포용 Google Cloud 프로젝트를 정한다.
2. Google Drive API를 활성화한다.
3. OAuth 동의 화면의 앱 이름, 지원 이메일, 개인정보처리방침, 사용자 데이터 사용 설명을 등록한다.
4. 동의 화면에 `drive.appdata`만 선언한다.
5. Android OAuth 클라이언트에 최종 application ID와 서명 SHA-1을 등록한다.
6. debug, 내부 테스트, Play App Signing이 서로 다른 인증서를 쓰면 필요한 SHA-1을 각각 등록한다.
7. 패키지가 요구하는 Web OAuth client/server client ID를 같은 프로젝트에 만든다.
8. 테스트 모드에서는 테스트 사용자를 등록하고, 공개 전 OAuth 앱 게시·검증 상태를 확인한다.
9. 개인정보처리방침에 곡 목록·메모·설정이 사용자의 Google Drive 앱 전용 공간에 저장되고 자동 업로드되지 않는다고 명시한다.

Alpha 0.7.0-a 작성 시 Android `applicationId`는
`com.example.today_music`이었고 release 빌드도 debug 서명을 사용했다.
Alpha 0.7.0-b에서 최종 ID를 `com.todaydrawmusic.app`으로 확정하고 release
keystore 분리 구조를 추가했다. 실제 Google 로그인 구현 전에는 로컬 upload
keystore와 Play App Signing 인증서의 SHA를 각각 OAuth 환경에 맞게 등록해야 한다.

## 오류와 안전장치

- 로그인 취소와 로그인 실패를 구분한다.
- 토큰/권한 만료 시 재승인을 요청한다.
- 네트워크 오류와 손상된 백업을 구분한다.
- 사용자 화면에는 내부 예외나 토큰을 표시하지 않는다.
- 로그의 이메일은 마스킹하고 JSON 본문·메모·토큰은 기록하지 않는다.
- 백업 실패 시 기존 Drive 백업을 유지한다.
- 검증 실패 또는 안전 백업 실패 시 로컬 데이터를 변경하지 않는다.
- 복원 실패 시 안전 백업으로 롤백한다.
- 모든 긴 작업에서 버튼 중복 실행을 막는다.

권장 사용자 문구:

- `Google 로그인에 실패했습니다. 다시 시도해 주세요.`
- `로그인이 취소되었습니다.`
- `Google 계정 연결이 만료되었습니다. 다시 로그인해 주세요.`
- `현재 기기의 데이터를 백업하고 있습니다.`
- `백업에 실패했습니다. 기존 Drive 백업은 변경되지 않았습니다.`
- `백업 파일을 읽을 수 없습니다.`
- `지원하지 않는 백업 형식입니다.`
- `복원에 실패했습니다. 현재 기기의 데이터는 유지되었습니다.`
- `인터넷 연결을 확인해 주세요.`

## 다음 구현 단계

1. 운영 application ID와 서명 전략 확정
2. Google Cloud OAuth 및 Drive API 설정
3. Android 전용 `GoogleBackupAccountRepository` 구현
4. `DriveAppDataBackupRepository` 구현과 fake 저장소 서비스 테스트
5. `SharedPreferencesBackupLocalDataRepository`와 원자적 롤백 처리 구현
6. `path_provider` 기반 최근 안전 백업 1개 구현
7. Android 전용 백업 및 복원 화면과 메인 진입 버튼 구현
8. 확인창·빈 데이터 경고·오류 상태 위젯 테스트
9. 실제 계정으로 업로드, 덮어쓰기, 다운로드, 복원, 로그아웃, 인증 만료 테스트
10. Web 빌드에서 버튼과 Google 코드가 없음을 회귀 테스트

자동 업로드, 자동 다운로드, 백그라운드 동기화, 여러 기기 병합과 충돌 해결은 포함하지 않는다.
