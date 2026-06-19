import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:today_music/main.dart';

void main() {
  Future<void> pumpTodayMusicApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'tdm_alpha_songs':
          '[{"artist":"N.Flying","title":"Blue Moon","tags":[],"memo":"","link":"","isFavorite":false}]',
      'sample_prompt_checked': true,
    });
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
    expect(find.text('선택곡 추가'), findsOneWidget);
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '선택곡 추가'),
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
      find.widgetWithText(FilledButton, '선택곡 추가'),
    );
    expect(enabledAddButton.onPressed, isNotNull);
  });
}
