# TDM Alpha 0.7.0-b Android 식별자·서명·OAuth 준비

## 확정된 Android 식별자

| 항목 | 변경 전 | 최종 값 |
| --- | --- | --- |
| application ID | `com.example.today_music` | `com.todaydrawmusic.app` |
| namespace | `com.example.today_music` | `com.todaydrawmusic.app` |
| 앱 표시 이름 | `today_music` | `오늘의 한 곡` |
| MainActivity package | `com.example.today_music` | `com.todaydrawmusic.app` |
| MainActivity 경로 | `android/app/src/main/kotlin/com/example/today_music/MainActivity.kt` | `android/app/src/main/kotlin/com/todaydrawmusic/app/MainActivity.kt` |

앱 화면 표시 버전은 `Alpha 0.7.0`, Android versionName/versionCode는
`0.7.0` / `9`다.

## 기존 설치 앱과 데이터

Android는 application ID를 앱의 고유 식별자로 사용한다. 따라서
`com.example.today_music`으로 설치된 기존 개발 앱과
`com.todaydrawmusic.app` 앱은 서로 다른 앱이다.

- 새 앱은 기존 앱과 나란히 설치될 수 있다.
- 기존 앱의 SharedPreferences는 새 앱이 읽을 수 없다.
- `tdm_alpha_songs` 등 저장 키가 같아도 application sandbox가 달라 자동 승계되지 않는다.
- 이번 단계에는 데이터 이전이나 자동 마이그레이션을 추가하지 않는다.
- 필요한 데이터는 기존 앱에서 TXT로 내보내고 새 앱에서 불러오는 수동 경로를 사용할 수 있다.

Web 빌드는 Android application ID와 namespace를 사용하지 않으므로 영향을 받지
않는다.

## SDK 기준

Flutter 3.44.1의 현재 Android 기본값을 사용한다.

- minSdk: 24
- targetSdk: 36
- compileSdk: 36
- Android SDK 설치 버전: 36.1
- Java/Kotlin target: JVM 17

## debug 서명

debug 빌드는 Android 기본 debug keystore를 계속 사용한다.

- keystore: 사용자 홈의 `.android/debug.keystore`
- SHA-1:
  `39:7F:80:78:3A:D4:F0:07:28:55:C7:50:0E:B3:72:7C:8F:5F:BF:15`
- SHA-256:
  `49:9F:57:B6:5D:A0:92:26:B6:C9:FE:E1:72:B0:D1:3A:02:7E:68:9E:F2:D4:49:FB:D4:F3:EE:86:C5:97:25:4B`

이 SHA는 현재 개발 PC의 debug 앱으로 Google 로그인을 시험할 Android OAuth
클라이언트에만 사용한다. 다른 개발 PC가 자체 debug keystore를 만들면 SHA도
달라진다.

## release 서명 구조

release 빌드는 더 이상 debug signing config를 사용하지 않는다.

`android/app/build.gradle.kts`는 로컬 `android/key.properties`를 읽어
`release` signing config를 만든다. release 작업에서 이 파일이 없으면 명확한
오류로 중단하며 debug 키로 대체하지 않는다.

Git에 포함되는 예시:

```text
android/key.properties.example
```

Git에서 제외되는 비밀 파일:

```text
android/key.properties
*.jks
*.keystore
```

권장 keystore 위치는 저장소 바깥의 별도 암호화 백업 폴더다.
`storeFile`은 `android/` 디렉터리를 기준으로 해석된다.

예시 생성 명령은 다음과 같다. 실제 경로, alias와 비밀번호는 사용자가 직접
정하고 안전한 비밀번호 관리자에 보관한다.

```powershell
keytool -genkeypair -v `
  -keystore "D:\private\tdm\todaydrawmusic-upload.jks" `
  -alias "todaydrawmusic-upload" `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000
```

생성 후 `android/key.properties.example`을 `android/key.properties`로
복사하고 실제 값을 입력한다. 비밀번호, private key, keystore 파일은 커밋하거나
작업 보고에 붙이지 않는다.

release keystore가 아직 생성되지 않았으므로 release SHA-1/SHA-256은 현재
확정되지 않았다. 생성 후 다음 명령으로 확인한다.

```powershell
keytool -list -v `
  -keystore "D:\private\tdm\todaydrawmusic-upload.jks" `
  -alias "todaydrawmusic-upload"
```

## Google Play App Signing

Play App Signing을 사용하면 인증서가 두 종류로 나뉜다.

- 업로드 키: 로컬에서 AAB를 서명하는 현재 release/upload keystore
- 앱 서명 키: Google Play가 사용자에게 배포하는 APK를 최종 서명하는 키

내부 로컬 APK 또는 Play 업로드 전 테스트에는 upload key SHA를 사용한다.
Play를 통해 설치된 앱의 Google OAuth에는 Play Console의 앱 서명 키 SHA-1도
Android OAuth 클라이언트에 등록해야 한다. 두 키가 다르므로 Play 공개 전
Play Console `앱 무결성` 화면의 fingerprint를 추가 확인한다.

## Google Cloud Console 준비

1. TDM용 Google Cloud 프로젝트를 생성하거나 선택한다.
2. Google Drive API를 활성화한다.
3. Google Auth Platform의 브랜딩, 대상 사용자와 데이터 액세스를 설정한다.
4. 앱 이름, 지원 이메일, 개발자 연락처와 개인정보처리방침 URL을 입력한다.
5. 테스트 상태라면 로그인할 Google 계정을 테스트 사용자로 등록한다.
6. Android OAuth 클라이언트를 만든다.
7. 패키지 이름에 `com.todaydrawmusic.app`을 입력한다.
8. 개발 앱용 클라이언트에는 debug SHA-1을 입력한다.
9. release/upload keystore 생성 후 release SHA-1용 클라이언트를 추가한다.
10. Play 배포 전 Play App Signing 앱 서명 키 SHA-1도 추가한다.
11. Drive 접근은 다음 최소 범위만 요청한다.

```text
https://www.googleapis.com/auth/drive.appdata
```

`drive`, `drive.readonly`, `drive.file` 등 전체 또는 사용자 파일 접근 범위는
요청하지 않는다.

## google-services.json 필요 여부

Firebase는 사용하지 않으며 Google Services Gradle plugin도 추가하지 않는다.
따라서 이번 구성에서 `google-services.json`은 필수가 아니다.

`google_sign_in_android`은 다음 두 방식 중 하나로 Android OAuth 설정을 받을
수 있다.

1. Google Services 설정 파일에 Web OAuth client가 포함된 방식
2. Google Services 파일 없이 Dart 초기화의 `serverClientId`에 Web OAuth
   client ID를 전달하는 방식

TDM은 불필요한 Firebase 의존성을 피하기 위해 두 번째 방식을 우선한다. 실제
로그인 구현 단계에서 Google Cloud Console에 Web application 유형의 OAuth
client를 만들고 그 client ID를 Android Google Sign-In의 `serverClientId`로
전달할지, 사용 중인 `google_sign_in` 7.x 버전의 공식 문서를 다시 확인한다.
client secret은 모바일 앱에 포함하지 않는다.

Drive API 권한은 로그인만으로 자동 획득된다고 가정하지 않는다. 로그인 후
`drive.appdata` 범위를 명시적으로 승인받고, 승인된 인증 클라이언트만
`googleapis` Drive API에 전달한다.

## 실제 로그인 구현 전 남은 작업

1. release/upload keystore 생성과 암호화된 별도 백업
2. `android/key.properties` 로컬 작성
3. release SHA-1/SHA-256 확인
4. Google Cloud 프로젝트와 Drive API 활성화
5. OAuth 동의 화면, 테스트 사용자와 개인정보처리방침 준비
6. debug/release/Play App Signing SHA별 Android OAuth client 등록
7. 필요할 경우 Web OAuth client ID 생성
8. `google_sign_in`, `googleapis`와 인증 클라이언트 연결 패키지 추가
9. Android 전용 로그인 및 `appDataFolder` 저장소 구현
10. 실제 계정에서 로그인 취소, 토큰 만료, 네트워크 실패, 로그아웃 검증

이번 단계에서는 Google 로그인 버튼, 계정 선택, Drive 업로드·다운로드와 복원
UI를 구현하지 않는다.

## 변경하지 않은 영역

- 기존 SharedPreferences 키와 저장 형식
- 곡·세트 및 붙여넣기 파서
- TXT 내보내기·불러오기 형식
- 백업 JSON 형식 버전 1
- 백업 직렬화 및 검증 규칙
- Web 저장 구조와 UI

## 공식 참고 문서

- Flutter Android release signing:
  <https://docs.flutter.dev/deployment/android#sign-the-app>
- Android application ID:
  <https://developer.android.com/build/configure-app-module#set-application-id>
- Google Sign-In Flutter Android:
  <https://pub.dev/packages/google_sign_in_android>
- Google Drive app data folder:
  <https://developers.google.com/workspace/drive/api/guides/appdata>
- Google Drive API OAuth scopes:
  <https://developers.google.com/workspace/drive/api/guides/api-specific-auth>
