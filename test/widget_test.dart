import 'dart:ui';

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
}
