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
      'tdm_app_backup_2026-06-21_1700',
    );
  });

  test('export filenames use short safe tdm prefixes', () {
    final timestamp = DateTime(2026, 6, 22, 1, 45);

    expect(buildExportTimestamp(timestamp), '2026-06-22_0145');
    expect(
      buildSongsExportFileBaseName(timestamp),
      'tdm_songs_2026-06-22_0145',
    );
    expect(
      buildSongsExportFileBaseName(timestamp, artist: 'N.Flying'),
      'tdm_NFlying_2026-06-22_0145',
    );
    expect(
      buildSongsExportFileBaseName(timestamp, artist: '가수/이름:테스트'),
      'tdm_가수이름테스트_2026-06-22_0145',
    );
    expect(buildSetsExportFileBaseName(timestamp), 'tdm_sets_2026-06-22_0145');
    expect(safeExportFileNamePart(r'\/:*?"<>|.'), 'artist');
  });

  test('file import guidance distinguishes TXT and app backup JSON', () {
    expect(songTxtImportGuidance, contains('곡 목록 TXT 파일'));
    expect(songTxtImportGuidance, contains('앱 전체 백업 JSON 파일'));
    expect(appBackupImportGuidance, contains('앱 전체 백업 JSON 파일'));
    expect(appBackupImportGuidance, contains('곡 목록 TXT 파일'));
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
      'tdm_artist_order': <String>['KEY'],
    });

    await SongStorage.resetAllAppData();
    final preferences = await SharedPreferences.getInstance();

    expect(preferences.getKeys(), isEmpty);
  });

  test('artist order removes deleted artists and appends new artists', () {
    expect(
      reconcileArtistOrder(
        ['N.Flying', 'CNBLUE', 'Touched'],
        ['CNBLUE', 'Deleted', 'N.Flying'],
      ),
      ['CNBLUE', 'N.Flying', 'Touched'],
    );
    expect(reconcileArtistOrder(['N.Flying', 'CNBLUE'], const []), isEmpty);
  });

  testWidgets('artist order editor uses drag handles without checkboxes', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs':
            '[{"artist":"N.Flying","title":"Blue Moon","tags":[]},'
            '{"artist":"CNBLUE","title":"Loner","tags":[]},'
            '{"artist":"ONEWE","title":"Rain To Be","tags":[]}]',
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    expect(find.text('편집'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('artist-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사용자지정'));
    await tester.pumpAndSettle();

    expect(find.text('가수 순서 편집'), findsWidgets);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );
    expect(find.text('기본 정렬로 되돌리기'), findsOneWidget);

    await tester.drag(
      find.byIcon(Icons.drag_handle).first,
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    final savedOrder = preferences.getStringList('tdm_artist_order');
    expect(savedOrder, hasLength(3));
    expect(savedOrder, isNot(['N.Flying', 'CNBLUE', 'ONEWE']));
    expect(find.text('사용자지정'), findsOneWidget);
    expect(find.text('편집'), findsOneWidget);
    final customToolbarRect = tester.getRect(
      find.byKey(const ValueKey('artist-storage-toolbar')),
    );
    final editRect = tester.getRect(find.text('편집'));
    final customAllSongsRect = tester.getRect(
      find.byKey(const ValueKey('all-songs-button')),
    );
    expect(editRect.right, lessThan(customAllSongsRect.left));
    expect(
      (customToolbarRect.right - customAllSongsRect.right).abs(),
      lessThan(1),
    );
  });

  testWidgets('artist sort options use the compact dropdown labels', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs':
            '[{"artist":"N.Flying","title":"Blue Moon","tags":[]},'
            '{"artist":"CNBLUE","title":"Loner","tags":[]}]',
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();

    expect(find.text('정렬순서'), findsOneWidget);
    expect(find.text('편집'), findsNothing);
    expect(find.text('전체곡 보기'), findsOneWidget);
    expect(find.byType(SegmentedButton<ArtistSortMode>), findsNothing);
    final toolbarRect = tester.getRect(
      find.byKey(const ValueKey('artist-storage-toolbar')),
    );
    final allSongsRect = tester.getRect(
      find.byKey(const ValueKey('all-songs-button')),
    );
    expect((toolbarRect.right - allSongsRect.right).abs(), lessThan(1));

    await tester.tap(find.byKey(const ValueKey('artist-sort-menu')));
    await tester.pumpAndSettle();
    final menuItems = find.descendant(
      of: find.byType(PopupMenuItem<ArtistSortMode>),
      matching: find.byType(Text),
    );
    expect(
      tester
          .widgetList<Text>(menuItems)
          .map((text) => text.data)
          .whereType<String>()
          .toList(),
      ['기본', '이름', '등록', '곡수', '사용자지정'],
    );

    await tester.tap(find.text('이름'));
    await tester.pumpAndSettle();
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('편집'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('artist-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사용자지정'));
    await tester.pumpAndSettle();
    expect(find.text('가수 순서 편집'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '취소').last);
    await tester.pumpAndSettle();
    expect(find.text('이름'), findsOneWidget);
    expect(find.text('편집'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('artist-sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기본'));
    await tester.pumpAndSettle();
    expect(find.text('정렬순서'), findsOneWidget);
  });

  testWidgets(
    'artist detail and all songs use registration and name dropdowns',
    (WidgetTester tester) async {
      await pumpTodayMusicApp(
        tester,
        initialValues: {
          'tdm_alpha_songs':
              '[{"artist":"N.Flying","title":"Zulu","tags":[]},'
              '{"artist":"N.Flying","title":"Alpha","tags":[]},'
              '{"artist":"CNBLUE","title":"Moon","tags":[]}]',
          'sample_prompt_checked': true,
        },
      );

      await tester.tap(find.text('노래 저장소'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('N.Flying'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('artist-song-sort')), findsOneWidget);
      expect(find.text('추가순'), findsNothing);
      expect(find.text('곡명순'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Zulu')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('artist-song-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('Zulu')).dy),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, '닫기').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체곡 보기'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('all-song-sort')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('N.Flying - Zulu')).dy,
        lessThan(tester.getTopLeft(find.text('N.Flying - Alpha')).dy),
      );

      await tester.tap(find.byKey(const ValueKey('all-song-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이름').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('N.Flying - Alpha')).dy,
        lessThan(tester.getTopLeft(find.text('CNBLUE - Moon')).dy),
      );
      expect(
        tester.getTopLeft(find.text('CNBLUE - Moon')).dy,
        lessThan(tester.getTopLeft(find.text('N.Flying - Zulu')).dy),
      );
    },
  );

  testWidgets('artist song rows open the common card only from the title', (
    WidgetTester tester,
  ) async {
    const songsJson =
        '[{"artist":"N.Flying","title":"Linked","tags":[],"link":"https://example.com"},'
        '{"artist":"N.Flying","title":"Search","tags":[],"link":""}]';
    const setsJson =
        '[{"id":"set-1","name":"공연 세트","songs":['
        '{"artist":"N.Flying","title":"Linked","tags":[],"link":"https://example.com"}'
        ']}]';
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs': songsJson,
        'tdm_song_sets': setsJson,
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('N.Flying'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('이 곡 추천하기'), findsNWidgets(2));
    expect(find.byTooltip('링크 열기'), findsNothing);
    expect(find.byTooltip('링크 검색'), findsNothing);
    expect(find.byTooltip('관리'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    await tester.tap(find.byTooltip('즐겨찾기 추가').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('song-action-card')), findsNothing);

    await tester.tap(find.byTooltip('이 곡 추천하기').first);
    await tester.pump();
    expect(find.byKey(const ValueKey('song-action-card')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('artist-song-card-n.flying\nlinked')),
    );
    await tester.pumpAndSettle();

    final songCard = find.byKey(const ValueKey('song-action-card'));
    expect(songCard, findsOneWidget);
    expect(
      find.descendant(of: songCard, matching: find.text('즐겨찾기 해제')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: songCard, matching: find.text('포함된 세트 보기')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: songCard, matching: find.text('링크 열기')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: songCard, matching: find.text('곡 수정')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: songCard, matching: find.text('곡 삭제')),
      findsOneWidget,
    );
    expect(find.text('세트에서 제외'), findsNothing);

    await tester.tap(
      find.descendant(of: songCard, matching: find.text('포함된 세트 보기')),
    );
    await tester.pumpAndSettle();
    expect(find.text('이 곡이 포함된 세트'), findsOneWidget);
    expect(find.text('공연 세트'), findsOneWidget);
    final includedSetsDialog = find.byType(AlertDialog).last;
    final includedSetsClose = find.descendant(
      of: includedSetsDialog,
      matching: find.widgetWithText(OutlinedButton, '닫기'),
    );
    await tester.ensureVisible(includedSetsClose);
    await tester.tap(includedSetsClose);
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: songCard, matching: find.text('곡 수정')),
    );
    await tester.pumpAndSettle();
    expect(find.text('곡 수정하기'), findsOneWidget);
    final editDialog = find.byType(AlertDialog).last;
    expect(
      find.descendant(of: editDialog, matching: find.byTooltip('링크 열기')),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(of: editDialog, matching: find.byType(TextField)).last,
      '',
    );
    await tester.pump();
    expect(
      find.descendant(of: editDialog, matching: find.byTooltip('링크 검색')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, '닫기').last);
    await tester.pumpAndSettle();
  });

  testWidgets('all songs keep batch controls separate from the common card', (
    WidgetTester tester,
  ) async {
    const songsJson =
        '[{"artist":"N.Flying","title":"Linked","tags":[],"link":"https://example.com"},'
        '{"artist":"N.Flying","title":"Search","tags":[],"link":""}]';
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs': songsJson,
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체곡 보기'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('이 곡 추천하기'), findsNWidgets(2));
    expect(find.byTooltip('링크 열기'), findsNothing);
    expect(find.byTooltip('링크 검색'), findsNothing);
    expect(find.byTooltip('관리'), findsNothing);
    expect(find.byIcon(Icons.folder_copy_outlined), findsNothing);

    final linkedRow = find.byKey(
      const ValueKey('all-songs-n.flying\nlinked-0'),
    );
    await tester.tap(
      find.descendant(of: linkedRow, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('song-action-card')), findsNothing);

    await tester.tap(find.text('N.Flying - Linked'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('song-action-card')), findsOneWidget);
    expect(find.text('링크 열기'), findsOneWidget);
    expect(find.text('곡 수정'), findsOneWidget);
    expect(find.text('곡 삭제'), findsOneWidget);

    await tester.tap(find.text('곡 삭제'));
    await tester.pumpAndSettle();
    expect(find.text('이 곡을 삭제할까요?'), findsOneWidget);
    expect(find.textContaining('세트에서도 함께 사라집니다'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '취소').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '닫기').last);
    await tester.pumpAndSettle();
  });

  testWidgets('set song cards replace delete with remove from set', (
    WidgetTester tester,
  ) async {
    const songsJson =
        '[{"artist":"N.Flying","title":"Linked","tags":[],"link":"https://example.com"}]';
    const setsJson =
        '[{"id":"set-1","name":"공연 세트","songs":['
        '{"artist":"N.Flying","title":"Linked","tags":[],"link":"https://example.com"}'
        ']}]';
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs': songsJson,
        'tdm_song_sets': setsJson,
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('세트저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공연 세트'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('이 곡 추천하기'), findsOneWidget);
    expect(find.byTooltip('링크 열기'), findsNothing);
    expect(find.byTooltip('관리'), findsNothing);

    await tester.tap(find.text('1. N.Flying - Linked'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('song-action-card')), findsOneWidget);
    expect(find.text('즐겨찾기 추가'), findsOneWidget);
    expect(find.text('포함된 세트 보기'), findsOneWidget);
    expect(find.text('링크 열기'), findsOneWidget);
    expect(find.text('곡 수정'), findsOneWidget);
    expect(find.text('세트에서 제외'), findsOneWidget);
    expect(find.text('곡 삭제'), findsNothing);

    await tester.tap(find.text('세트에서 제외'));
    await tester.pumpAndSettle();
    expect(find.text('곡 제외'), findsOneWidget);
    expect(find.textContaining('원본 노래 저장소에서는 삭제되지 않아요'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '제외'));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('tdm_alpha_songs'), contains('"Linked"'));
    expect(
      preferences.getString('tdm_song_sets'),
      isNot(contains('"title":"Linked"')),
    );
  });

  testWidgets('song set detail sorting only changes the visible order', (
    WidgetTester tester,
  ) async {
    const storedSet =
        '[{"id":"set-1","name":"공연 세트","songs":['
        '{"artist":"N.Flying","title":"Zulu","tags":[]},'
        '{"artist":"N.Flying","title":"Alpha","tags":[]},'
        '{"artist":"N.Flying","title":"Moon","tags":[]}'
        ']}]';
    await pumpTodayMusicApp(
      tester,
      initialValues: {
        'tdm_alpha_songs':
            '[{"artist":"N.Flying","title":"Zulu","tags":[]},'
            '{"artist":"N.Flying","title":"Alpha","tags":[]},'
            '{"artist":"N.Flying","title":"Moon","tags":[]}]',
        'tdm_song_sets': storedSet,
        'sample_prompt_checked': true,
      },
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('세트저장소'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('공연 세트'));
    await tester.pumpAndSettle();

    expect(find.text('등록'), findsOneWidget);
    expect(find.text('1. N.Flying - Zulu'), findsOneWidget);
    expect(find.text('2. N.Flying - Alpha'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('song-set-detail-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이름 오름').last);
    await tester.pumpAndSettle();
    expect(find.text('1. N.Flying - Alpha'), findsOneWidget);
    expect(find.text('3. N.Flying - Zulu'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('song-set-detail-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이름 내림').last);
    await tester.pumpAndSettle();
    expect(find.text('1. N.Flying - Zulu'), findsOneWidget);
    expect(find.text('3. N.Flying - Alpha'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('song-set-detail-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록').last);
    await tester.pumpAndSettle();
    expect(find.text('1. N.Flying - Zulu'), findsOneWidget);
    expect(find.text('2. N.Flying - Alpha'), findsOneWidget);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('tdm_song_sets'), storedSet);
  });

  testWidgets('first pasted artist refreshes an empty storage sheet', (
    WidgetTester tester,
  ) async {
    await pumpTodayMusicApp(
      tester,
      initialValues: {'tdm_alpha_songs': '[]', 'sample_prompt_checked': true},
    );

    await tester.tap(find.text('노래 저장소'));
    await tester.pumpAndSettle();
    expect(find.text('총 0곡 · 가수명 0팀'), findsOneWidget);

    await tester.tap(find.text('곡 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('붙여넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paste-song-input')),
      'N.Flying - Blue Moon',
    );
    await tester.tap(find.text('분석하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('선택한 항목 저장'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '닫기').last);
    await tester.pumpAndSettle();

    expect(find.text('총 1곡 · 가수명 1팀'), findsOneWidget);
    expect(find.text('N.Flying'), findsOneWidget);
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
