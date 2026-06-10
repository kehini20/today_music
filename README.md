# today_music

TDM / 오늘의 한 곡 Flutter 프로젝트입니다.

## 배포 전략

- 개발 확인: GitHub Pages
- 안정판/공개판: Netlify
- Netlify 크레딧 보호를 위해 production deploy는 안정화 후에만 진행합니다.
- 광고 정적 파일은 `web/ads/`에서 관리합니다. `public/ads`는 사용하지 않습니다.
- `build/web` 산출물은 Git에 직접 커밋하지 않고, CI artifact 또는 배포 서비스의 빌드 결과로 사용합니다.

## GitHub Pages 개발 배포

GitHub Pages는 개발 중 잦은 웹 확인용입니다.

- workflow: `.github/workflows/deploy-gh-pages.yml`
- 실행 방식:
  - `develop` 브랜치 push 시 자동 배포
  - GitHub Actions에서 `workflow_dispatch`로 수동 실행
- Pages URL 기준:
  - `https://kehini20.github.io/today_music/`
- Flutter Web base href:
  - `/today_music/`

workflow는 다음 광고 설정 URL을 사용합니다.

```text
https://kehini20.github.io/today_music/ads/ad_config.json
```

로컬에서 같은 조건으로 확인하려면:

```bash
flutter build web --release --base-href /today_music/ --dart-define SPONSOR_AD_CONFIG_URL=https://kehini20.github.io/today_music/ads/ad_config.json
```

배포 후 확인 경로:

```text
/ads/ad_config.json
/ads/ad_tdm_main_self_002.png
/ads/ad_tdm_bottom_self_002.png
```

## Netlify 안정판 배포

Netlify는 안정판/공개판 확인용으로 유지합니다.

- 기존 `netlify.toml`
- 기존 `netlify_build.sh`
- 기본 광고 설정 URL은 앱 코드의 기본값으로 Netlify 주소를 사용합니다.

Netlify가 `main` push마다 production deploy를 계속 실행한다면, 코드만으로 제어하기보다 Netlify UI에서 자동 배포/브랜치 배포 설정을 확인해야 합니다.

## 광고 설정 URL

앱 기본값은 Netlify의 광고 설정을 바라봅니다.

```text
https://tangerine-nougat-072e10.netlify.app/ads/ad_config.json
```

환경별로 바꾸고 싶을 때는 Flutter 빌드 시 `SPONSOR_AD_CONFIG_URL`을 전달합니다.

```bash
flutter build web --release --dart-define SPONSOR_AD_CONFIG_URL=https://example.com/ads/ad_config.json
```

## 기본 검증

```bash
dart format lib/main.dart lib/sponsor_ad.dart
flutter analyze
flutter build web --release --base-href /today_music/
```
