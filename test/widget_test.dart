import 'package:flutter_test/flutter_test.dart';

import 'package:today_music/main.dart';

void main() {
  testWidgets('Today music prototype renders', (WidgetTester tester) async {
    await tester.pumpWidget(const TodayMusicApp());

    expect(find.text('오늘의 한 곡'), findsOneWidget);
    expect(find.text('오늘의 한 곡 뽑기'), findsOneWidget);
    expect(find.text('노래 저장소'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
  });

  testWidgets('Pick button shows a song', (WidgetTester tester) async {
    await tester.pumpWidget(const TodayMusicApp());

    await tester.tap(find.text('오늘의 한 곡 뽑기'));
    await tester.pump();

    expect(find.text('#오늘의한곡'), findsOneWidget);
    expect(find.text('버튼을 눌러 오늘 들을 곡을 뽑아보세요.'), findsNothing);
  });
}
