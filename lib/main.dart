import 'dart:convert';
import 'dart:math';

import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sample_songs.dart';
import 'song.dart';
import 'sponsor_ad.dart';

void main() {
  runApp(const TodayMusicApp());
}

class SongStorage {
  static const String _songsKey = 'tdm_alpha_songs';
  static const String _samplePromptCheckedKey = 'sample_prompt_checked';
  static const String _defaultShareMessageKey = 'tdm_default_share_message';

  static Future<List<Song>?> loadSongs() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final rawJson = preferences.getString(_songsKey);

      if (rawJson == null || rawJson.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(rawJson);

      if (decoded is! List) {
        return null;
      }

      final songs = decoded
          .whereType<Map>()
          .map((songJson) => Song.fromJson(Map<String, Object?>.from(songJson)))
          .where((song) => song.artist.isNotEmpty && song.title.isNotEmpty)
          .toList();

      return songs;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSongs(List<Song> songs) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encodedSongs = jsonEncode(
        songs.map((song) => song.toJson()).toList(),
      );

      await preferences.setString(_songsKey, encodedSongs);
    } catch (_) {
      // Prototype persistence should never crash the app.
    }
  }

  static Future<bool> isSamplePromptChecked() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_samplePromptCheckedKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setSamplePromptChecked(bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_samplePromptCheckedKey, value);
    } catch (_) {
      // Prompt state should never crash the app.
    }
  }

  static Future<String> loadDefaultShareMessage() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_defaultShareMessageKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> saveDefaultShareMessage(String message) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_defaultShareMessageKey, message);
    } catch (_) {
      // Settings persistence should never crash the app.
    }
  }
}

class TodayMusicApp extends StatelessWidget {
  const TodayMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘의 한 곡',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4DB6AC),
          primary: const Color(0xFF00897B),
          surface: const Color(0xFFEEF8F6),
        ),
        scaffoldBackgroundColor: const Color(0xFFEEF8F6),
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFEEF8F6),
          foregroundColor: Color(0xFF004D40),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF00897B);
            }
            return null;
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00695C),
            side: const BorderSide(color: Color(0xFF80CBC4)),
          ),
        ),
      ),
      home: const TodaySongPage(),
    );
  }
}

class TodaySongPage extends StatefulWidget {
  const TodaySongPage({super.key});

  @override
  State<TodaySongPage> createState() => _TodaySongPageState();
}

class _TodaySongPageState extends State<TodaySongPage> {
  final Random _random = Random();
  List<Song> _songs = [];
  final TextEditingController _shareTextController = TextEditingController();
  Song? _selectedSong;
  SponsorAd _bottomAd = fallbackBottomAd;
  String _defaultShareMessage = '';
  bool _includeTodayTag = true;
  bool _includeSongLink = true;

  @override
  void initState() {
    super.initState();
    _loadSavedSongs();
    _loadBottomAd();
  }

  @override
  void dispose() {
    _shareTextController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSongs() async {
    final savedSongs = await SongStorage.loadSongs();
    final samplePromptChecked = await SongStorage.isSamplePromptChecked();
    final defaultShareMessage = await SongStorage.loadDefaultShareMessage();

    if (!mounted) {
      return;
    }

    setState(() {
      _songs = savedSongs ?? [];
      _selectedSong = null;
      _defaultShareMessage = defaultShareMessage;
      _includeTodayTag = true;
      _shareTextController.clear();
    });

    if ((savedSongs == null || savedSongs.isEmpty) && !samplePromptChecked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showSampleSongsPromptDialog();
        }
      });
    }
  }

  void _saveSongs() {
    SongStorage.saveSongs(_songs);
  }

  Future<void> _loadBottomAd() async {
    final bottomAd = await loadBottomSponsorAd();
    if (!mounted) {
      return;
    }

    setState(() {
      _bottomAd = bottomAd;
    });
  }

  Future<void> _showSampleSongsPromptDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('안내'),
          content: const Text(
            '샘플곡으로 시작할까요?\n\n'
            '오늘의 한 곡 뽑기를 바로 체험할 수 있도록\n'
            '샘플곡 몇 곡을 추가할 수 있어요.\n\n'
            '샘플곡은 나중에 수정하거나 삭제할 수 있습니다.',
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await SongStorage.setSamplePromptChecked(true);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: const Text('빈 저장소', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await SongStorage.setSamplePromptChecked(true);
                      if (!mounted) {
                        return;
                      }

                      setState(() {
                        _songs = List<Song>.of(sampleSongs);
                      });
                      _saveSongs();

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    child: const Text('샘플곡', maxLines: 1),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _buildShareText(Song song) {
    final link = song.link.trim();
    final tags = [
      ...visibleSongTags(song.tags),
      if (_includeTodayTag) '#오늘의한곡',
    ];
    final lines = <String>['오늘의 한 곡 🎧'];

    if (_defaultShareMessage.trim().isNotEmpty) {
      lines.addAll(['', _defaultShareMessage.trim()]);
    }

    lines.addAll(['', '${song.artist} - ${song.title}']);

    if (_includeSongLink && link.isNotEmpty) {
      lines.addAll(['', link]);
    }

    if (tags.isNotEmpty) {
      lines.addAll(['', tags.join(' ')]);
    }

    return lines.join('\n');
  }

  void _resetShareText(Song song) {
    _shareTextController.text = _buildShareText(song);
  }

  void _toggleTodayTag(bool? value) {
    final includeTag = value ?? false;
    final selectedSong = _selectedSong;

    setState(() {
      _includeTodayTag = includeTag;
      if (selectedSong != null) {
        _resetShareText(selectedSong);
      }
    });
  }

  void _toggleSongLink(bool? value) {
    final selectedSong = _selectedSong;
    if (selectedSong == null) {
      return;
    }

    final includeLink = value ?? false;
    setState(() {
      _includeSongLink = includeLink;
      _resetShareText(selectedSong);
    });
  }

  void _pickRandomSong() {
    if (_songs.isEmpty) {
      _showRootSnackBar('저장된 곡이 없어요. 노래 저장소에서 곡을 추가해주세요.');
      return;
    }

    Song nextSong = _songs[_random.nextInt(_songs.length)];
    while (_songs.length > 1 && nextSong == _selectedSong) {
      nextSong = _songs[_random.nextInt(_songs.length)];
    }

    setState(() {
      _selectedSong = nextSong;
      _includeSongLink = true;
      _resetShareText(nextSong);
    });
  }

  String? _currentShareTextOrNotify() {
    final currentText = _shareTextController.text;
    if (currentText.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('공유할 문구를 입력해주세요.')));
      return null;
    }

    return currentText;
  }

  Future<void> _shareCurrentText() async {
    final shareText = _currentShareTextOrNotify();
    if (shareText == null) {
      return;
    }

    await SharePlus.instance.share(ShareParams(text: shareText));
  }

  Future<void> _shareCurrentTextToX() async {
    final shareText = _currentShareTextOrNotify();
    if (shareText == null) {
      return;
    }

    final uri = Uri.https('twitter.com', '/intent/tweet', {'text': shareText});

    try {
      final didLaunch = await launchUrl(uri, webOnlyWindowName: '_blank');

      if (!didLaunch) {
        _showRootSnackBar('X 공유창을 열 수 없습니다.');
      }
    } catch (_) {
      _showRootSnackBar('X 공유창을 열 수 없습니다.');
    }
  }

  Future<void> _copyCurrentShareText() async {
    final shareText = _currentShareTextOrNotify();
    if (shareText == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: shareText));
    _showRootSnackBar('공유 문구가 복사되었습니다.');
  }

  Future<void> _openYoutubeSearch(Song song) async {
    final query = [
      song.artist.trim(),
      song.title.trim(),
    ].where((part) => part.isNotEmpty).join(' ');

    if (query.isEmpty) {
      _showRootSnackBar('유튜브 검색을 열 수 없습니다.');
      return;
    }

    final uri = Uri.https('www.youtube.com', '/results', {
      'search_query': query,
    });

    try {
      final didLaunch = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!didLaunch) {
        _showRootSnackBar('유튜브 검색을 열 수 없습니다.');
      }
    } catch (_) {
      _showRootSnackBar('유튜브 검색을 열 수 없습니다.');
    }
  }

  bool _hasSongLink(Song song) => song.link.trim().isNotEmpty;

  String _songOpenButtonLabel(Song song) =>
      _hasSongLink(song) ? '링크 열기' : '유튜브 검색';

  String _compactSongOpenButtonLabel(Song song) =>
      _hasSongLink(song) ? '링크' : '검색';

  Future<void> _openSongLinkOrYoutube(Song song) async {
    if (!_hasSongLink(song)) {
      await _openYoutubeSearch(song);
      return;
    }

    final rawLink = song.link.trim();
    final normalizedLink = rawLink.contains('://')
        ? rawLink
        : 'https://$rawLink';
    final uri = Uri.tryParse(normalizedLink);

    if (uri == null || !uri.hasScheme) {
      _showRootSnackBar('링크를 열 수 없습니다.');
      return;
    }

    try {
      final didLaunch = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );

      if (!didLaunch) {
        _showRootSnackBar('링크를 열 수 없습니다.');
      }
    } catch (_) {
      _showRootSnackBar('링크를 열 수 없습니다.');
    }
  }

  Future<void> _openSponsorAdLink(SponsorAd ad) async {
    final rawLink = ad.linkUrl.trim();
    if (rawLink.isEmpty) {
      return;
    }

    final normalizedLink = rawLink.contains('://')
        ? rawLink
        : 'https://$rawLink';
    final uri = Uri.tryParse(normalizedLink);

    if (uri == null || !uri.hasScheme) {
      _showRootSnackBar('링크를 열 수 없습니다.');
      return;
    }

    try {
      final didLaunch = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );

      if (!didLaunch) {
        _showRootSnackBar('링크를 열 수 없습니다.');
      }
    } catch (_) {
      _showRootSnackBar('링크를 열 수 없습니다.');
    }
  }

  Future<void> _exportSongs() async {
    if (_songs.isEmpty) {
      _showRootSnackBar('내보낼 곡이 없습니다.');
      return;
    }

    await _saveExportFileToPhone(songs: _songs);
  }

  Future<void> _exportArtistSongs(String artist) async {
    final artistSongs = _songs.where((song) => song.artist == artist).toList();
    if (artistSongs.isEmpty) {
      _showRootSnackBar('내보낼 곡이 없습니다.');
      return;
    }

    await _saveExportFileToPhone(
      songs: artistSongs,
      filePrefix: 'today_music_export_${_safeFileNamePart(artist)}',
    );
  }

  String _safeFileNamePart(String value) {
    final sanitized = value
        .trim()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return sanitized.isEmpty ? 'artist' : sanitized;
  }

  Future<void> _saveExportFileToPhone({
    required List<Song> songs,
    String filePrefix = 'today_music_export',
  }) async {
    final timestamp = _exportTimestamp();
    final fileName = _exportFileName(timestamp, filePrefix: filePrefix);

    try {
      final exportText = _buildSongExportText(songs);

      final savedPath = await FileSaver.instance.saveAs(
        name: _exportFileBaseName(timestamp, filePrefix: filePrefix),
        bytes: Uint8List.fromList(utf8.encode(exportText)),
        fileExtension: 'txt',
        mimeType: MimeType.text,
      );

      if (savedPath == null || savedPath.trim().isEmpty) {
        _showExportResultDialog('파일 저장에 실패했습니다.');
        return;
      }

      _showExportResultDialog('내보내기 파일을 저장했습니다: $fileName');
    } catch (_) {
      _showExportResultDialog('파일 저장에 실패했습니다.');
    }
  }

  void _showExportResultDialog(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    });
  }

  String _exportTimestamp() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${now.year}'
        '${twoDigits(now.month)}'
        '${twoDigits(now.day)}_'
        '${twoDigits(now.hour)}'
        '${twoDigits(now.minute)}';
  }

  String _exportFileBaseName(
    String timestamp, {
    String filePrefix = 'today_music_export',
  }) {
    return '${filePrefix}_$timestamp';
  }

  String _exportFileName(
    String timestamp, {
    String filePrefix = 'today_music_export',
  }) {
    return '${_exportFileBaseName(timestamp, filePrefix: filePrefix)}.txt';
  }

  String _buildSongExportText(List<Song> songs) {
    final buffer = StringBuffer()
      ..writeln('# 오늘의 한 곡 내보내기')
      ..writeln('# 이 파일은 오늘의 한 곡 앱에서 다시 불러올 수 있도록 만든 곡 세트 파일입니다.')
      ..writeln('# 곡은 [곡] 단위로 구분됩니다.')
      ..writeln('# 가수와 제목은 필수입니다.')
      ..writeln('# 메모와 태그는 비워둘 수 있습니다.')
      ..writeln('# 태그는 공백으로 구분해주세요.');

    for (final song in songs) {
      final tags = visibleSongTags(
        song.tags,
      ).where((tag) => tag != '#오늘의한곡').join(' ');

      buffer
        ..writeln()
        ..writeln('[곡]')
        ..writeln('가수: ${_exportSingleLine(song.artist)}')
        ..writeln('제목: ${_exportSingleLine(song.title)}')
        ..writeln('메모: ${_exportSingleLine(song.memo)}')
        ..writeln('태그: ${_exportSingleLine(tags)}')
        ..writeln('링크: ${_exportSingleLine(song.link)}');
    }

    return buffer.toString();
  }

  String _exportSingleLine(String text) {
    return text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
  }

  Future<void> _importSongs({VoidCallback? onSongsImported}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _showImportResultDialog('불러오기에 실패했습니다.');
        return;
      }

      final importedText = utf8.decode(bytes, allowMalformed: true);
      final parsedSongs = _parseImportedSongs(importedText);

      if (parsedSongs.isEmpty) {
        _showImportResultDialog('불러올 수 있는 곡이 없습니다.');
        return;
      }

      final existingKeys = _songs.map(_songDuplicateKey).toSet();
      final songsToAdd = <Song>[];
      var existingSongCount = 0;

      for (final song in parsedSongs) {
        final key = _songDuplicateKey(song);
        if (existingKeys.contains(key)) {
          existingSongCount++;
          continue;
        }

        existingKeys.add(key);
        songsToAdd.add(song);
      }

      if (songsToAdd.isEmpty) {
        _showImportResultDialog('0곡 추가\n이미 저장된 목록입니다.');
        return;
      }

      setState(() {
        _songs.addAll(songsToAdd);
      });
      _saveSongs();
      onSongsImported?.call();

      _showImportResultDialog(
        _buildImportResultMessage(
          addedCount: songsToAdd.length,
          existingSongCount: existingSongCount,
        ),
      );
    } catch (_) {
      _showImportResultDialog('불러오기에 실패했습니다.');
    }
  }

  String _buildImportResultMessage({
    required int addedCount,
    required int existingSongCount,
  }) {
    if (existingSongCount == 0) {
      return '$addedCount곡 추가되었습니다.';
    }

    return '$addedCount곡 추가되었습니다.\n이미 저장된 곡은 제외되었습니다.';
  }

  List<Song> _parseImportedSongs(String text) {
    final songs = <Song>[];
    final currentFields = <String, String>{};

    void flushSong() {
      final artist = currentFields['artist']?.trim() ?? '';
      final title = currentFields['title']?.trim() ?? '';

      if (artist.isNotEmpty && title.isNotEmpty) {
        songs.add(
          Song(
            artist: artist,
            title: title,
            memo: currentFields['memo']?.trim() ?? '',
            tags: normalizeTagInput(currentFields['tags'] ?? ''),
            link: currentFields['link']?.trim() ?? '',
          ),
        );
      }

      currentFields.clear();
    }

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();

      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      if (line == '[곡]') {
        flushSong();
        continue;
      }

      final separatorIndex = line.indexOf(':');
      if (separatorIndex == -1) {
        continue;
      }

      final key = line.substring(0, separatorIndex).trim();
      final value = line.substring(separatorIndex + 1).trim();

      switch (key) {
        case '가수':
          currentFields['artist'] = value;
        case '제목':
          currentFields['title'] = value;
        case '메모':
          currentFields['memo'] = value;
        case '태그':
          currentFields['tags'] = value;
        case '링크':
          currentFields['link'] = value;
      }
    }

    flushSong();

    return songs;
  }

  String _songDuplicateKey(Song song) {
    return '${song.artist.trim().toLowerCase()}\n'
        '${song.title.trim().toLowerCase()}';
  }

  void _showImportResultDialog(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('확인'),
              ),
            ],
          );
        },
      );
    });
  }

  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return SettingsDialog(
          initialDefaultMessage: _defaultShareMessage,
          onSave: (message) {
            if (!mounted) {
              return;
            }

            final trimmedMessage = message.trim();
            setState(() {
              _defaultShareMessage = trimmedMessage;
              final selectedSong = _selectedSong;
              if (selectedSong != null) {
                _resetShareText(selectedSong);
              }
            });
            SongStorage.saveDefaultShareMessage(trimmedMessage);
          },
          onContactEmail: _openContactEmail,
          onResetSongs: _showResetSongsDialog,
        );
      },
    );
  }

  Future<void> _openContactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      queryParameters: {'subject': '오늘의 한 곡 문의'},
    );

    try {
      final didLaunch = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!didLaunch) {
        _showRootSnackBar('이메일 앱을 열 수 없습니다.');
      }
    } catch (_) {
      _showRootSnackBar('이메일 앱을 열 수 없습니다.');
    }
  }

  void _showResetSongsDialog() {
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('전체 곡을 초기화할까요?'),
          content: const Text(
            '저장된 곡 목록이 모두 삭제됩니다.\n'
            '이 작업은 되돌릴 수 없습니다.\n\n'
            '곡 목록을 보관하려면\n'
            '초기화 전에 TXT로 내보내기 해주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop();
                _resetAllSongs();
              },
              child: const Text('초기화'),
            ),
          ],
        );
      },
    );
  }

  void _resetAllSongs() {
    setState(() {
      _songs = [];
      _selectedSong = null;
      _shareTextController.clear();
      _includeTodayTag = true;
      _includeSongLink = true;
    });
    SongStorage.setSamplePromptChecked(true);
    _saveSongs();
    _showRootSnackBar('저장된 곡 목록을 초기화했어요.');
  }

  void _addSong(Song song) {
    setState(() {
      _songs.add(song);
    });
    _saveSongs();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('곡이 추가되었습니다.')));
  }

  void _updateSong(Song originalSong, Song updatedSong) {
    var didUpdate = false;

    setState(() {
      final index = _songs.indexWhere((song) => identical(song, originalSong));

      if (index == -1) {
        return;
      }

      _songs[index] = updatedSong;
      didUpdate = true;

      if (identical(_selectedSong, originalSong)) {
        _selectedSong = updatedSong;
        _includeSongLink = true;
        _resetShareText(updatedSong);
      }
    });

    if (!didUpdate) {
      return;
    }

    _saveSongs();

    _showRootSnackBar('곡이 수정되었습니다.');
  }

  void _showRootSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }

  void _deleteSong(Song song) {
    setState(() {
      _songs.remove(song);
      if (_selectedSong == song) {
        _selectedSong = null;
        _shareTextController.clear();
        _includeSongLink = true;
      }
    });
    _saveSongs();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('곡이 삭제되었습니다.')));
  }

  void _resetToInitialScreen() {
    setState(() {
      _selectedSong = null;
      _shareTextController.clear();
      _includeSongLink = true;
    });
  }

  void _deleteArtistSongs(String artist) {
    final songsToDelete = _songs
        .where((song) => song.artist == artist)
        .toList();
    if (songsToDelete.isEmpty) {
      return;
    }

    final selectedSong = _selectedSong;
    final shouldResetResult =
        selectedSong != null && songsToDelete.contains(selectedSong);

    setState(() {
      _songs.removeWhere((song) => song.artist == artist);
      if (shouldResetResult) {
        _selectedSong = null;
        _shareTextController.clear();
        _includeSongLink = true;
      }
    });
    _saveSongs();
    _showRootSnackBar('$artist 곡 ${songsToDelete.length}개를 삭제했어요.');
  }

  void _showDeleteArtistSongsDialog(String artist, {VoidCallback? onDeleted}) {
    final artistSongCount = _songs
        .where((song) => song.artist == artist)
        .length;
    if (artistSongCount == 0) {
      return;
    }

    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('전체 삭제'),
          content: Text(
            '이 가수의 곡을 모두 삭제할까요?\n\n'
            '$artist에 저장된 곡 $artistSongCount개가 모두 삭제됩니다.\n'
            '이 작업은 되돌릴 수 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop();
                _deleteArtistSongs(artist);
                onDeleted?.call();
              },
              child: const Text('전체 삭제'),
            ),
          ],
        );
      },
    );
  }

  void _showSongStorageSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, refreshSheet) {
            final groupedSongs = songsByArtist(_songs);
            final colorScheme = Theme.of(bottomSheetContext).colorScheme;
            final maxHeight =
                MediaQuery.sizeOf(bottomSheetContext).height * 0.82;

            return SafeArea(
              top: false,
              child: SizedBox(
                height: maxHeight,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '노래 저장소',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '총 ${_songs.length}곡 · ${groupedSongs.length}가수',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: () {
                              _showAddSongDialog(
                                onSongAdded: () => refreshSheet(() {}),
                              );
                            },
                            child: const Text('곡 추가'),
                          ),
                          OutlinedButton(
                            onPressed: _exportSongs,
                            child: const Text('내보내기'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              _importSongs(
                                onSongsImported: () => refreshSheet(() {}),
                              );
                            },
                            child: const Text('불러오기'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ...groupedSongs.entries.map(
                        (entry) => ArtistSongGroupTile(
                          artist: entry.key,
                          songs: entry.value,
                          onTap: () => _showArtistSongsDialog(
                            entry.key,
                            onSongChanged: () => refreshSheet(() {}),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddSongDialog({VoidCallback? onSongAdded}) {
    final artistNames = songsByArtist(_songs).keys.toList();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AddSongDialog(
          artistNames: artistNames,
          existingSongs: _songs,
          onSubmit: (song) {
            _addSong(song);
            onSongAdded?.call();
          },
        );
      },
    );
  }

  void _showEditSongDialog(Song song, {VoidCallback? onSongUpdated}) {
    final artistNames = songsByArtist(_songs).keys.toList();

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AddSongDialog(
          artistNames: artistNames,
          existingSongs: _songs,
          initialSong: song,
          onSubmit: (updatedSong) {
            _updateSong(song, updatedSong);
            onSongUpdated?.call();
          },
        );
      },
    );
  }

  void _showArtistSongsDialog(String artist, {VoidCallback? onSongChanged}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final songs = _songs
                .where((song) => song.artist == artist)
                .toList();
            final compactButtonStyle = TextButton.styleFrom(
              minimumSize: const Size(40, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            );

            return AlertDialog(
              title: Text('$artist 곡 목록'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.55,
                ),
                child: SizedBox(
                  width: double.maxFinite,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: songs.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 10),
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      final hasLink = _hasSongLink(song);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _openSongLinkOrYoutube(song),
                              style: compactButtonStyle,
                              child: Text(
                                _compactSongOpenButtonLabel(song),
                                style: TextStyle(
                                  color: hasLink
                                      ? const Color(0xFF2679A8)
                                      : null,
                                  fontWeight: hasLink
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                _showEditSongDialog(
                                  song,
                                  onSongUpdated: () {
                                    refreshDialog(() {});
                                    onSongChanged?.call();
                                  },
                                );
                              },
                              style: compactButtonStyle,
                              child: const Text('수정'),
                            ),
                            TextButton(
                              onPressed: () {
                                _showDeleteSongDialog(
                                  song,
                                  onDeleted: () {
                                    if (songs.length == 1) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                    refreshDialog(() {});
                                    onSongChanged?.call();
                                  },
                                );
                              },
                              style: compactButtonStyle,
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _exportArtistSongs(artist),
                            child: const Text('목록 내보내기', maxLines: 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _showDeleteArtistSongsDialog(
                                artist,
                                onDeleted: () {
                                  Navigator.of(dialogContext).pop();
                                  onSongChanged?.call();
                                },
                              );
                            },
                            child: const Text('목록 삭제', maxLines: 1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('닫기', maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteSongDialog(Song song, {VoidCallback? onDeleted}) {
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('삭제'),
          content: Text('${song.artist} - ${song.title}\n\n이 곡을 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop();
                _deleteSong(song);
                onDeleted?.call();
              },
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _selectedSong == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _selectedSong == null) {
          return;
        }

        _resetToInitialScreen();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('오늘의 한 곡'), centerTitle: true),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + keyboardInset),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 480,
                        minHeight: max(0, constraints.maxHeight - 48),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SongResultCard(song: _selectedSong),
                          if (_selectedSong != null) ...[
                            const SizedBox(height: 16),
                            _PickSongButton(
                              label: '다른 곡 뽑기',
                              onPressed: _pickRandomSong,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () {
                                final selectedSong = _selectedSong;
                                if (selectedSong == null) {
                                  return;
                                }

                                _openSongLinkOrYoutube(selectedSong);
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: Text(_songOpenButtonLabel(_selectedSong!)),
                            ),
                            const SizedBox(height: 24),
                            ShareTextEditor(controller: _shareTextController),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 0,
                              children: [
                                if (_selectedSong != null &&
                                    _hasSongLink(_selectedSong!))
                                  _CompactShareCheck(
                                    value: _includeSongLink,
                                    onChanged: _toggleSongLink,
                                    label: '링크 포함',
                                  ),
                                _CompactShareCheck(
                                  value: _includeTodayTag,
                                  onChanged: _toggleTodayTag,
                                  label: '#오늘의한곡 포함',
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (kIsWeb) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _shareCurrentTextToX,
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(44),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: const Text('X에 공유하기', maxLines: 1),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _copyCurrentShareText,
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size.fromHeight(44),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: const Text('문구 복사하기', maxLines: 1),
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              OutlinedButton(
                                onPressed: _shareCurrentText,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                ),
                                child: const Text('공유하기'),
                              ),
                          ] else ...[
                            const SizedBox(height: 32),
                            _PickSongButton(
                              label: '오늘의 한 곡 뽑기',
                              onPressed: _pickRandomSong,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_bottomAd.enabled) ...[
                        SponsorBottomBanner(
                          ad: _bottomAd,
                          onTap: () => _openSponsorAdLink(_bottomAd),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _showSongStorageSheet,
                              child: const Text('노래 저장소'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _showSettingsDialog,
                              child: const Text('설정'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ArtistSongGroupTile extends StatelessWidget {
  final String artist;
  final List<Song> songs;
  final VoidCallback onTap;

  const ArtistSongGroupTile({
    super.key,
    required this.artist,
    required this.songs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${songs.length}곡',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsDialog extends StatefulWidget {
  final String initialDefaultMessage;
  final ValueChanged<String> onSave;
  final VoidCallback onContactEmail;
  final VoidCallback onResetSongs;

  const SettingsDialog({
    super.key,
    required this.initialDefaultMessage,
    required this.onSave,
    required this.onContactEmail,
    required this.onResetSongs,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _defaultMessageController;

  @override
  void initState() {
    super.initState();
    _defaultMessageController = TextEditingController(
      text: widget.initialDefaultMessage,
    );
  }

  @override
  void dispose() {
    _defaultMessageController.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_defaultMessageController.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('설정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _defaultMessageController,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '공유 기본 메시지',
                hintText: '예: 오늘의 한 곡 🎧',
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 28),
            OutlinedButton(
              onPressed: widget.onContactEmail,
              child: const Text('이메일로 문의하기'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onResetSongs,
              child: const Text('전체 곡 초기화'),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(onPressed: _save, child: const Text('저장')),
      ],
    );
  }
}

List<String> normalizeTagInput(String text) {
  return text
      .split(RegExp(r'\s+'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .map((tag) => tag.startsWith('#') ? tag : '#$tag')
      .toList();
}

List<String> visibleSongTags(List<String> tags) {
  return tags.where((tag) => tag != '#오늘의한곡').toList();
}

class HashTagTextField extends StatefulWidget {
  final TextEditingController controller;

  const HashTagTextField({super.key, required this.controller});

  @override
  State<HashTagTextField> createState() => _HashTagTextFieldState();
}

class _HashTagTextFieldState extends State<HashTagTextField> {
  bool _isFormatting = false;

  void _formatTags() {
    if (_isFormatting) {
      return;
    }

    final original = widget.controller.text;
    if (!original.contains(' ')) {
      return;
    }

    final hasTrailingSpace = RegExp(r'\s$').hasMatch(original);
    final formattedTags = normalizeTagInput(original);
    final formatted =
        '${formattedTags.join(' ')}${hasTrailingSpace ? ' ' : ''}';

    if (formatted == original) {
      return;
    }

    _isFormatting = true;
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormatting = false;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_formatTags);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_formatTags);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      decoration: const InputDecoration(
        labelText: '해시태그',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class AddSongDialog extends StatefulWidget {
  final List<String> artistNames;
  final List<Song> existingSongs;
  final ValueChanged<Song> onSubmit;
  final Song? initialSong;

  const AddSongDialog({
    super.key,
    required this.artistNames,
    required this.existingSongs,
    required this.onSubmit,
    this.initialSong,
  });

  @override
  State<AddSongDialog> createState() => _AddSongDialogState();
}

class _AddSongDialogState extends State<AddSongDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _memoController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  String _artistName = '';
  String? _artistErrorText;
  String? _titleErrorText;
  bool get _isEditMode => widget.initialSong != null;

  @override
  void initState() {
    super.initState();

    final initialSong = widget.initialSong;
    if (initialSong == null) {
      return;
    }

    _artistName = initialSong.artist;
    _titleController.text = initialSong.title;
    _memoController.text = initialSong.memo;
    _tagsController.text = initialSong.tags.join(' ');
    _linkController.text = initialSong.link;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    _tagsController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final artist = _artistName.trim();
    final title = _titleController.text.trim();

    final hasArtist = artist.isNotEmpty;
    final hasTitle = title.isNotEmpty;

    if (!hasArtist || !hasTitle) {
      setState(() {
        _artistErrorText = hasArtist ? null : '가수명을 입력해주세요.';
        _titleErrorText = hasTitle ? null : '곡 제목을 입력해주세요.';
      });
      return;
    }

    final tags = normalizeTagInput(_tagsController.text);

    final song = Song(
      artist: artist,
      title: title,
      tags: tags,
      memo: _memoController.text.trim(),
      link: _linkController.text.trim(),
    );

    if (_hasDuplicateSong(artist: artist, title: title)) {
      _showDuplicateTitleDialog(song);
      return;
    }

    _submitSong(song);
  }

  bool _hasDuplicateSong({required String artist, required String title}) {
    final normalizedArtist = artist.trim().toLowerCase();
    final normalizedTitle = title.trim().toLowerCase();

    return widget.existingSongs.any((existingSong) {
      if (identical(existingSong, widget.initialSong)) {
        return false;
      }

      return existingSong.artist.trim().toLowerCase() == normalizedArtist &&
          existingSong.title.trim().toLowerCase() == normalizedTitle;
    });
  }

  void _submitSong(Song song) {
    Navigator.of(context).pop();
    widget.onSubmit(song);
  }

  void _showDuplicateTitleDialog(Song song) {
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('경고'),
          content: Text(
            '이미 같은 제목의 곡이 있어요.\n\n'
            '${song.artist} - ${song.title}\n\n'
            '${_isEditMode ? '그래도 저장할까요?' : '그래도 추가할까요?'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop();
                _submitSong(song);
              },
              child: Text(_isEditMode ? '저장하기' : '추가하기'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditMode ? '곡 수정하기' : '곡 추가하기'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ArtistAutocompleteField(
                artistNames: widget.artistNames,
                initialValue: _artistName,
                errorText: _artistErrorText,
                onChanged: (artist) {
                  _artistName = artist;
                  if (_artistErrorText != null && artist.trim().isNotEmpty) {
                    setState(() {
                      _artistErrorText = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                onChanged: (title) {
                  if (_titleErrorText != null && title.trim().isNotEmpty) {
                    setState(() {
                      _titleErrorText = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  label: const RequiredInputLabel(text: '곡 제목'),
                  border: const OutlineInputBorder(),
                  errorText: _titleErrorText,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _memoController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '메모',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              HashTagTextField(controller: _tagsController),
              const SizedBox(height: 12),
              TextField(
                controller: _linkController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: '링크',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
        FilledButton(
          onPressed: _handleSubmit,
          child: Text(_isEditMode ? '저장하기' : '추가하기'),
        ),
      ],
    );
  }
}

class ArtistAutocompleteField extends StatelessWidget {
  final List<String> artistNames;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final String initialValue;

  const ArtistAutocompleteField({
    super.key,
    required this.artistNames,
    required this.onChanged,
    required this.errorText,
    this.initialValue = '',
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue),
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();

        if (query.isEmpty) {
          return artistNames;
        }

        return artistNames.where(
          (artist) => artist.toLowerCase().contains(query),
        );
      },
      onSelected: onChanged,
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              onChanged: onChanged,
              decoration: const InputDecoration(
                label: RequiredInputLabel(text: '가수명'),
                border: OutlineInputBorder(),
              ).copyWith(errorText: errorText),
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        final colorScheme = Theme.of(context).colorScheme;
        final optionList = options.toList();

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionList.length,
                itemBuilder: (context, index) {
                  final artist = optionList[index];

                  return ListTile(
                    dense: true,
                    title: Text(artist),
                    onTap: () => onSelected(artist),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class RequiredInputLabel extends StatelessWidget {
  final String text;

  const RequiredInputLabel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: text,
        children: [
          TextSpan(
            text: ' *',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickSongButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PickSongButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}

class ShareTextEditor extends StatelessWidget {
  final TextEditingController controller;

  const ShareTextEditor({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '공유 문구',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  return Text(
                    '${value.text.characters.length}자',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 5,
            maxLines: 8,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactShareCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;

  const _CompactShareCheck({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SponsorBottomBanner extends StatelessWidget {
  final SponsorAd ad;
  final VoidCallback onTap;

  const SponsorBottomBanner({super.key, required this.ad, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasLink = ad.linkUrl.trim().isNotEmpty;
    final label = [
      ad.title.trim(),
      ad.message.trim(),
    ].where((text) => text.isNotEmpty).join(' ');

    return Semantics(
      button: hasLink,
      label: label.isEmpty ? '홍보 배너' : label,
      child: SizedBox(
        width: double.infinity,
        height: 80,
        child: Material(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hasLink ? onTap : null,
            child: _SponsorAdImage(imageUrl: ad.imageUrl),
          ),
        ),
      ),
    );
  }
}

class _SponsorAdImage extends StatelessWidget {
  final String imageUrl;

  const _SponsorAdImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return const _FallbackSponsorAdImage();
    }

    return Image.network(
      imageUrl.trim(),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('SponsorAd image load error: ${imageUrl.trim()} / $error');
        return const _FallbackSponsorAdImage();
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return const _FallbackSponsorAdImage();
      },
    );
  }
}

class _FallbackSponsorAdImage extends StatelessWidget {
  const _FallbackSponsorAdImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(fallbackBottomAdAssetPath, fit: BoxFit.contain);
  }
}

class SongResultCard extends StatelessWidget {
  final Song? song;

  const SongResultCard({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (song == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '버튼을 눌러 오늘 들을 곡을 뽑아보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            song!.artist,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            song!.title,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (song!.memo.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              song!.memo,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
