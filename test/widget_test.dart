import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:today_music/main.dart';

void main() {
  Future<void> pumpTodayMusicApp(
    WidgetTester tester, {
    Map<String, Object>? initialValues,
  }) async {
    SharedPreferences.setMockInitialValues(
      initialValues ??
          {
            'tdm_alpha_songs':
                '[{"artist":"N.Flying","title":"Blue Moon","tags":[],"memo":"","link":"","isFavorite":false}]',
            'sample_prompt_checked': true,
          },
    );
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const TodayMusicApp());
  }

  test('platform image recognition policy is explicit', () {
    expect(
      shouldShowImageRecognitionControls(isWeb: true, isSupported: true),
      isFalse,
    );
    expect(
      shouldShowImageRecognitionControls(isWeb: false, isSupported: true),
      isTrue,
    );
    expect(
      shouldShowImageRecognitionControls(isWeb: false, isSupported: false),
      isFalse,
    );
    expect(
      imageRecognitionHelpMessage,
      '셋리스트 이미지를 선택하면 이미지 속 글자를 읽어 곡 목록을 분석합니다. '
      '인식 결과가 정확하지 않을 수 있으므로 저장 전 가수명과 곡명을 확인해 주세요.',
    );
  });

  testWidgets('Today music prototype renders', (WidgetTester tester) async {
    await pumpTodayMusicApp(tester);

    expect(find.text('\uC624\uB298\uC758 \uD55C \uACE1'), findsOneWidget);
    expect(
      find.text('\uC624\uB298\uC758 \uD55C \uACE1 \uBF51\uAE30'),
      findsOneWidget,
    );
    expect(find.text('\uB178\uB798 \uC800\uC7A5\uC18C'), findsOneWidget);
    expect(find.text('\uC124\uC815'), findsOneWidget);
  });

  testWidgets('image recognition help stays concise and accessible', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HelpIconButton(
            title: '이미지에서 곡 불러오기',
            message: imageRecognitionHelpMessage,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
    expect(find.byTooltip('도움말'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pumpAndSettle();
    expect(find.text(imageRecognitionHelpMessage), findsOneWidget);
  });

  testWidgets('Pick button shows a song', (WidgetTester tester) async {
    await pumpTodayMusicApp(tester);

    await tester.tap(
      find.text('\uC624\uB298\uC758 \uD55C \uACE1 \uBF51\uAE30'),
    );
    await tester.pumpAndSettle();

    expect(find.text('\uB2E4\uB978 \uACE1 \uBF51\uAE30'), findsOneWidget);
    expect(
      find.text(
        '\uBC84\uD2BC\uC744 \uB20C\uB7EC \uC624\uB298 \uB4E4\uC744 \uACE1\uC744 \uBF51\uC544\uBCF4\uC138\uC694.',
      ),
      findsNothing,
    );
  });

  testWidgets('settings shows the shared app version', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(tester);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    expect(find.text('앱 버전'), findsOneWidget);
    expect(find.text(appDisplayVersion), findsOneWidget);
  });

  testWidgets('settings exposes app backup and reset actions in safe order', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(tester);

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    expect(find.text('데이터 관리'), findsOneWidget);
    expect(find.text('앱 백업 내보내기'), findsOneWidget);
    expect(find.text('앱 백업 불러오기'), findsOneWidget);
    expect(find.text('앱 초기화'), findsOneWidget);
    expect(find.textContaining('곡, 세트, 좋아요, 공유 문구'), findsOneWidget);

    final exportTop = tester.getTopLeft(find.text('앱 백업 내보내기')).dy;
    final importTop = tester.getTopLeft(find.text('앱 백업 불러오기')).dy;
    final resetTop = tester.getTopLeft(find.text('앱 초기화')).dy;
    expect(exportTop, lessThan(importTop));
    expect(importTop, lessThan(resetTop));

    await tester.tap(find.text('앱 초기화'));
    await tester.pumpAndSettle();
    expect(find.text('앱을 초기화할까요?'), findsOneWidget);
    expect(find.textContaining('초기화 전 앱 백업을 내보내는 것을 권장합니다.'), findsOneWidget);
  });

  test('update candidate uses a distinct blue status color', () {
    expect(updateAvailableColor, const Color(0xFF5B8DEF));
    expect(updateAvailableColor, isNot(tdmPrimary));
    expect(updateAvailableColor, isNot(tdmTextSub));
  });

  test('app backup filename includes local date and time', () {
    expect(
      buildAppBackupFileBaseName(DateTime(2026, 6, 21, 17)),
      'today_music_backup_2026-06-21_1700',
    );
  });

  test('app reset removes every persisted app data key', () async {
    SharedPreferences.setMockInitialValues({
      'tdm_alpha_songs': '[]',
      'tdm_song_sets': '[]',
      'tdm_random_mode': 'songSets',
      'tdm_selected_song_set_ids': <String>['set-1'],
      'sample_prompt_checked': true,
      'tdm_default_share_message': '공유 문구',
      'tdm_disabled_random_artists': <String>['KEY'],
      'tdm_last_add_song_tab': 'paste',
    });

    await SongStorage.resetAllAppData();
    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getKeys(), isEmpty);
  });

  testWidgets('missing artist and review candidates show gentle guidance', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(tester);

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('곡 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('붙여넣기'));
    await tester.pumpAndSettle();

    if (kIsWeb) {
      expect(
        find.byKey(const ValueKey('image-recognition-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('image-recognition-help')),
        findsNothing,
      );
    }

    await tester.enterText(
      find.byKey(const ValueKey('paste-song-input')),
      'SETLIST\nBrand New Song',
    );
    await tester.tap(find.text('분석하기'));
    await tester.pumpAndSettle();

    expect(
      find.text('가수명을 확인하지 못한 곡이 있습니다. 저장하기 전에 가수명을 입력하거나 수정해 주세요.'),
      findsOneWidget,
    );
    expect(find.text('확인이 필요한 곡이 있어요.'), findsOneWidget);
    expect(find.text('선택한 항목 저장'), findsOneWidget);
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '선택한 항목 저장'),
    );
    expect(addButton.onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('inferred-artist-input')),
      'N.Flying',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('가수명을 확인하지 못한 곡이 있습니다. 저장하기 전에 가수명을 입력하거나 수정해 주세요.'),
      findsNothing,
    );
    final enabledAddButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '선택한 항목 저장'),
    );
    expect(enabledAddButton.onPressed, isNotNull);
  });

  testWidgets('selected update candidate merges metadata without clearing memo', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs':
            '[{"artist":"N.Flying","title":"Flowerwork","tags":["#엔플라잉"],"memo":"기존 메모","link":"","isFavorite":true}]',
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('곡 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('붙여넣기'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('paste-song-input')), '''
[곡]
가수명: N.Flying
제목: Flowerwork
메모:
태그: #엔플라잉 #승협
링크: https://example.com/flowerwork
''');
    await tester.tap(find.text('분석하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('업데이트 가능 1곡'), findsOneWidget);
    expect(find.text('업데이트 가능'), findsOneWidget);
    expect(find.textContaining('링크: 비어 있음'), findsOneWidget);

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).last);
    expect(checkbox.value, isFalse);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택한 항목 저장'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString('tdm_alpha_songs')!;
    expect(stored, contains('"memo":"기존 메모"'));
    expect(stored, contains('"link":"https://example.com/flowerwork"'));
    expect(stored, contains('"tags":["#엔플라잉","#승협"]'));
    expect(stored, contains('"isFavorite":true'));
  });
}
