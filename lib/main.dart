import 'dart:convert';
import 'dart:math';

import 'package:file_saver/file_saver.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backup/backup_models.dart';
import 'backup/backup_serializer.dart';
import 'sample_songs.dart';
import 'ocr/text_ocr_service.dart';
import 'paste_parser.dart';
import 'share_text.dart';
import 'song.dart';
import 'song_import.dart';
import 'sponsor_ad.dart';

void main() {
  runApp(const TodayMusicApp());
}

const Color tdmPrimary = Color(0xFF12CDB3);
const Color tdmPrimaryDark = Color(0xFF0FAF9A);
const Color tdmHoverColor = Color(0x1412CDB3);
const Color tdmSky = Color(0xFF87D3FF);
const Color tdmLime = Color(0xFFEBF195);
const Color tdmLimeText = Color(0xFFC9D94F);
const Color tdmBackground = Color(0xFFF6FFFC);
const Color tdmCardBackground = Color(0xFFEFFFFB);
const Color tdmTextMain = Color(0xFF173A3A);
const Color tdmTextSub = Color(0xFF5F7474);
const Color tdmBorder = Color(0xFFB7E8E1);
const Color tdmLinkBlue = Color(0xFF3A8FC3);
const Color updateAvailableColor = Color(0xFF5B8DEF);
const int maxSongSetCount = 30;
const int maxSongMemoLength = 140;
const int maxSongTagCount = 10;
const String appSemanticVersion = '0.7.7';
const String appDisplayVersion = 'Alpha 0.7.7';
const String songTxtImportGuidance =
    '곡 목록 TXT 파일을 선택하세요.\n앱 전체 백업 JSON 파일은 여기서 불러올 수 없습니다.';
const String appBackupImportGuidance =
    '앱 전체 백업 JSON 파일을 선택하세요.\n곡 목록 TXT 파일은 앱 전체 복원에 사용할 수 없습니다.';
const String imageRecognitionHelpMessage =
    '셋리스트 이미지를 선택하면 이미지 속 글자를 읽어 곡 목록을 분석합니다. '
    '인식 결과가 정확하지 않을 수 있으므로 저장 전 가수명과 곡명을 확인해 주세요.';

bool shouldShowImageRecognitionControls({
  required bool isWeb,
  required bool isSupported,
}) {
  return !isWeb && isSupported;
}

String buildAppBackupFileBaseName(DateTime timestamp) {
  return 'tdm_app_backup_${buildExportTimestamp(timestamp)}';
}

String buildExportTimestamp(DateTime timestamp) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${timestamp.year}-${twoDigits(timestamp.month)}-'
      '${twoDigits(timestamp.day)}_'
      '${twoDigits(timestamp.hour)}${twoDigits(timestamp.minute)}';
}

String safeExportFileNamePart(String value, {String fallback = 'artist'}) {
  var sanitized = value
      .trim()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[\\/:*?"<>|.]'), '')
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (sanitized.length > 40) {
    sanitized = sanitized.substring(0, 40).replaceAll(RegExp(r'_+$'), '');
  }
  return sanitized.isEmpty ? fallback : sanitized;
}

String buildSongsExportFileBaseName(DateTime timestamp, {String? artist}) {
  final prefix = artist == null
      ? 'tdm_songs'
      : 'tdm_${safeExportFileNamePart(artist)}';
  return '${prefix}_${buildExportTimestamp(timestamp)}';
}

String buildSetsExportFileBaseName(DateTime timestamp) {
  return 'tdm_sets_${buildExportTimestamp(timestamp)}';
}

String normalizeSongMemo(String value) {
  final trimmed = value.trim();
  return trimmed.length <= maxSongMemoLength
      ? trimmed
      : trimmed.substring(0, maxSongMemoLength);
}

String buildSongCardTagSummary(List<String> tags, {int maxCharacters = 56}) {
  final visible = visibleSongTags(tags).take(maxSongTagCount).toList();
  if (visible.isEmpty) {
    return '';
  }

  final shown = <String>[];
  for (final tag in visible) {
    final candidate = [...shown, tag].join(' ');
    final remaining = visible.length - shown.length - 1;
    final suffix = remaining > 0 ? ' +$remaining' : '';
    if (shown.isNotEmpty && candidate.length + suffix.length > maxCharacters) {
      break;
    }
    shown.add(tag);
  }

  var hiddenCount = visible.length - shown.length;
  while (hiddenCount > 0 &&
      shown.length > 1 &&
      '${shown.join(' ')} +$hiddenCount'.length > maxCharacters) {
    shown.removeLast();
    hiddenCount++;
  }
  return hiddenCount > 0 ? '${shown.join(' ')} +$hiddenCount' : shown.join(' ');
}

List<String> reconcileArtistOrder(
  Iterable<String> currentArtists,
  Iterable<String> storedOrder,
) {
  final current = currentArtists
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toList();
  final stored = storedOrder
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toList();
  if (stored.isEmpty) {
    return const [];
  }

  final currentByKey = {
    for (final artist in current) artist.toLowerCase(): artist,
  };
  final result = <String>[];
  final seen = <String>{};
  for (final artist in stored) {
    final key = artist.toLowerCase();
    final currentSpelling = currentByKey[key];
    if (currentSpelling != null && seen.add(key)) {
      result.add(currentSpelling);
    }
  }
  for (final artist in current) {
    if (seen.add(artist.toLowerCase())) {
      result.add(artist);
    }
  }
  return result;
}

enum AddSongTab { individual, paste }

class SongStorage {
  static const String _songsKey = 'tdm_alpha_songs';
  static const String _songSetsKey = 'tdm_song_sets';
  static const String _randomModeKey = 'tdm_random_mode';
  static const String _selectedSongSetIdsKey = 'tdm_selected_song_set_ids';
  static const String _samplePromptCheckedKey = 'sample_prompt_checked';
  static const String _defaultShareMessageKey = 'tdm_default_share_message';
  static const String _disabledRandomArtistsKey = 'tdm_disabled_random_artists';
  static const String _lastAddSongTabKey = 'tdm_last_add_song_tab';
  static const String _artistOrderKey = 'tdm_artist_order';

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

  static Future<List<SongSet>> loadSongSets() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final rawJson = preferences.getString(_songSetsKey);

      if (rawJson == null || rawJson.trim().isEmpty) {
        return const [];
      }

      final decoded = jsonDecode(rawJson);

      if (decoded is! List) {
        return const [];
      }

      return decoded
          .whereType<Map>()
          .map(
            (setJson) => SongSet.fromJson(Map<String, Object?>.from(setJson)),
          )
          .where((set) => set.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveSongSets(List<SongSet> sets) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encodedSets = jsonEncode(sets.map((set) => set.toJson()).toList());

      await preferences.setString(_songSetsKey, encodedSets);
    } catch (_) {
      // Set persistence should never crash the app.
    }
  }

  static Future<RandomMode> loadRandomMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_randomModeKey) == RandomMode.songSets.name
          ? RandomMode.songSets
          : RandomMode.artistRandom;
    } catch (_) {
      return RandomMode.artistRandom;
    }
  }

  static Future<void> saveRandomMode(RandomMode mode) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_randomModeKey, mode.name);
    } catch (_) {
      // Random mode persistence should never crash the app.
    }
  }

  static Future<List<String>> loadSelectedSongSetIds() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getStringList(_selectedSongSetIdsKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveSelectedSongSetIds(List<String> setIds) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(_selectedSongSetIdsKey, setIds);
    } catch (_) {
      // Random set selection persistence should never crash the app.
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

  static Future<Set<String>> loadDisabledRandomArtists() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return (preferences.getStringList(_disabledRandomArtistsKey) ?? const [])
          .map((artist) => artist.trim())
          .where((artist) => artist.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveDisabledRandomArtists(Set<String> artists) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(
        _disabledRandomArtistsKey,
        artists
            .map((artist) => artist.trim())
            .where((artist) => artist.isNotEmpty)
            .toList(),
      );
    } catch (_) {
      // Filter persistence should never crash the app.
    }
  }

  static Future<AddSongTab> loadLastAddSongTab() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_lastAddSongTabKey) == AddSongTab.paste.name
          ? AddSongTab.paste
          : AddSongTab.individual;
    } catch (_) {
      return AddSongTab.individual;
    }
  }

  static Future<void> saveLastAddSongTab(AddSongTab tab) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_lastAddSongTabKey, tab.name);
    } catch (_) {
      // Add-song tab persistence should never crash the app.
    }
  }

  static Future<List<String>> loadArtistOrder() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getStringList(_artistOrderKey) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveArtistOrder(List<String> artists) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (artists.isEmpty) {
        await preferences.remove(_artistOrderKey);
      } else {
        await preferences.setStringList(_artistOrderKey, artists);
      }
    } catch (_) {
      // Artist order persistence should never crash the app.
    }
  }

  static Future<void> resetAllAppData() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_songsKey),
      preferences.remove(_songSetsKey),
      preferences.remove(_randomModeKey),
      preferences.remove(_selectedSongSetIdsKey),
      preferences.remove(_samplePromptCheckedKey),
      preferences.remove(_defaultShareMessageKey),
      preferences.remove(_disabledRandomArtistsKey),
      preferences.remove(_lastAddSongTabKey),
      preferences.remove(_artistOrderKey),
    ]);
  }
}

class SongSet {
  final String id;
  final String name;
  final List<Song> songs;

  const SongSet({required this.id, required this.name, required this.songs});

  factory SongSet.fromJson(Map<String, Object?> json) {
    final rawSongs = json['songs'];

    return SongSet(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      songs: rawSongs is List
          ? rawSongs
                .whereType<Map>()
                .map(
                  (songJson) =>
                      Song.fromJson(Map<String, Object?>.from(songJson)),
                )
                .where(
                  (song) => song.artist.isNotEmpty && song.title.isNotEmpty,
                )
                .toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'songs': songs.map((song) => song.toJson()).toList(),
    };
  }

  SongSet copyWith({String? name, List<Song>? songs}) {
    return SongSet(id: id, name: name ?? this.name, songs: songs ?? this.songs);
  }
}

class SongSetRandomCandidate {
  final Song song;
  final String setName;

  const SongSetRandomCandidate({required this.song, required this.setName});
}

class SongSetImportDraft {
  final String name;
  final List<Song> songs;
  final int missingSongCount;

  const SongSetImportDraft({
    required this.name,
    required this.songs,
    required this.missingSongCount,
  });
}

class SongSetImportResult {
  final List<SongSetImportDraft> drafts;
  final int missingSongCount;
  final int emptySetCount;

  const SongSetImportResult({
    required this.drafts,
    required this.missingSongCount,
    required this.emptySetCount,
  });
}

enum ArtistSortMode { defaultOrder, name, added, songCount, custom }

enum SongListSortMode { added, title }

enum SongSetDetailSortMode { added, titleAscending, titleDescending }

enum SongStorageTab { songs, sets }

enum RandomMode { artistRandom, songSets }

class TodayMusicApp extends StatelessWidget {
  const TodayMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '오늘의 한 곡',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: tdmPrimary,
              surface: tdmBackground,
            ).copyWith(
              primary: tdmPrimary,
              secondary: tdmSky,
              tertiary: tdmLime,
              primaryContainer: tdmCardBackground,
              onPrimaryContainer: tdmTextMain,
              surface: tdmBackground,
              surfaceContainerHigh: Colors.white,
              surfaceContainerHighest: tdmCardBackground,
              outline: tdmBorder,
              outlineVariant: tdmBorder,
              onSurface: tdmTextMain,
              onSurfaceVariant: tdmTextSub,
            ),
        scaffoldBackgroundColor: tdmBackground,
        useMaterial3: true,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(
          backgroundColor: tdmBackground,
          foregroundColor: tdmTextMain,
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return tdmPrimary;
            }
            return null;
          }),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: tdmPrimary,
            foregroundColor: Colors.white,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: tdmPrimaryDark,
            backgroundColor: Colors.white,
            side: const BorderSide(color: tdmBorder),
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
  Song? _lastResultSong;
  bool _isSponsorPick = false;
  String? _resultSongSetName;
  SponsorAd _bottomAd = fallbackBottomAd;
  MainSponsorAd _mainAd = fallbackMainAd;
  String _defaultShareMessage = '';
  bool _includeTodayTag = true;
  bool _includeSongLink = true;
  ArtistSortMode _artistSortMode = ArtistSortMode.defaultOrder;
  SongStorageTab _songStorageTab = SongStorageTab.songs;
  Set<String> _disabledRandomArtists = {};
  List<SongSet> _songSets = [];
  RandomMode _randomMode = RandomMode.artistRandom;
  List<String> _selectedSongSetIds = [];
  AddSongTab _lastAddSongTab = AddSongTab.individual;
  List<String> _artistOrder = [];

  @override
  void initState() {
    super.initState();
    _loadSavedSongs();
    _loadSponsorAds();
  }

  @override
  void dispose() {
    _shareTextController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSongs() async {
    final savedSongs = await SongStorage.loadSongs();
    final savedSongSets = await SongStorage.loadSongSets();
    final savedRandomMode = await SongStorage.loadRandomMode();
    final selectedSongSetIds = await SongStorage.loadSelectedSongSetIds();
    final disabledRandomArtists = await SongStorage.loadDisabledRandomArtists();
    final samplePromptChecked = await SongStorage.isSamplePromptChecked();
    final defaultShareMessage = await SongStorage.loadDefaultShareMessage();
    final lastAddSongTab = await SongStorage.loadLastAddSongTab();
    final savedArtistOrder = await SongStorage.loadArtistOrder();

    if (!mounted) {
      return;
    }

    final loadedSongs = ensureSongIds(savedSongs ?? const []);
    final migratedSongIds =
        savedSongs != null &&
        (savedSongs.any((song) => song.id.isEmpty) ||
            savedSongs.map((song) => song.id).toSet().length !=
                savedSongs.length);

    setState(() {
      final existingArtists = songsByArtist(loadedSongs).keys.toSet();
      _songs = loadedSongs;
      _songSets = _songSetsSyncedWithSongs(savedSongSets, loadedSongs);
      _selectedSongSetIds = selectedSongSetIds
          .where((setId) => _songSets.any((set) => set.id == setId))
          .toList();
      _randomMode =
          savedRandomMode == RandomMode.songSets &&
              _selectedSongSetIds.isNotEmpty
          ? RandomMode.songSets
          : RandomMode.artistRandom;
      _disabledRandomArtists = disabledRandomArtists
          .where(existingArtists.contains)
          .toSet();
      _artistOrder = reconcileArtistOrder(existingArtists, savedArtistOrder);
      if (_artistOrder.isNotEmpty) {
        _artistSortMode = ArtistSortMode.custom;
      } else {
        _artistSortMode = ArtistSortMode.defaultOrder;
      }
      _selectedSong = null;
      _lastResultSong = null;
      _isSponsorPick = false;
      _resultSongSetName = null;
      _defaultShareMessage = defaultShareMessage;
      _lastAddSongTab = lastAddSongTab;
      _includeTodayTag = true;
      _shareTextController.clear();
    });

    if (migratedSongIds) {
      await Future.wait([
        SongStorage.saveSongs(_songs),
        SongStorage.saveSongSets(_songSets),
      ]);
    }

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

  void _saveSongSets() {
    SongStorage.saveSongSets(_songSets);
  }

  void _saveDisabledRandomArtists() {
    SongStorage.saveDisabledRandomArtists(_disabledRandomArtists);
  }

  void _saveRandomSelection() {
    SongStorage.saveRandomMode(_randomMode);
    SongStorage.saveSelectedSongSetIds(_selectedSongSetIds);
  }

  void _syncArtistFilterState() {
    final existingArtists = songsByArtist(_songs).keys.toSet();
    _disabledRandomArtists = _disabledRandomArtists
        .where(existingArtists.contains)
        .toSet();
    final reconciledOrder = reconcileArtistOrder(existingArtists, _artistOrder);
    if (!listEquals(reconciledOrder, _artistOrder)) {
      _artistOrder = reconciledOrder;
      SongStorage.saveArtistOrder(_artistOrder);
    }
  }

  List<SongSet> _songSetsSyncedWithSongs(List<SongSet> sets, List<Song> songs) {
    final currentSongsById = {
      for (final song in songs)
        if (song.id.isNotEmpty) song.id: song,
    };
    final currentSongsByKey = <String, Song>{};
    for (final song in songs) {
      currentSongsByKey.putIfAbsent(_songDuplicateKey(song), () => song);
    }

    return sets
        .map(
          (set) => set.copyWith(
            songs: set.songs
                .map(
                  (song) => song.id.isNotEmpty
                      ? currentSongsById[song.id]
                      : currentSongsByKey[_songDuplicateKey(song)],
                )
                .whereType<Song>()
                .toList(),
          ),
        )
        .toList();
  }

  void _syncSongSetsWithSongs() {
    _songSets = _songSetsSyncedWithSongs(_songSets, _songs);
    _syncSelectedSongSets();
  }

  void _syncSelectedSongSets({bool showFallbackMessage = false}) {
    final existingSetIds = _songSets.map((set) => set.id).toSet();
    final beforeIds = List<String>.of(_selectedSongSetIds);
    _selectedSongSetIds = _selectedSongSetIds
        .where(existingSetIds.contains)
        .toList();

    final removedSelectedSet = beforeIds.length != _selectedSongSetIds.length;
    if (_selectedSongSetIds.isEmpty) {
      final wasSetRandom = _randomMode == RandomMode.songSets;
      _randomMode = RandomMode.artistRandom;
      if (showFallbackMessage && wasSetRandom && removedSelectedSet) {
        _runAfterFrame(() {
          _showRootSnackBar(
            '\uC120\uD0DD\uB41C \uC138\uD2B8\uAC00 \uC5C6\uC5B4 \uAC00\uC218 \uB79C\uB364\uC73C\uB85C \uBCC0\uACBD\uD588\uC5B4\uC694.',
          );
        });
      }
    }
  }

  List<SongSet> _selectedSongSets() {
    return _selectedSongSetIds.map(_songSetById).whereType<SongSet>().toList();
  }

  void _replaceSongInSets(Song originalSong, Song updatedSong) {
    _songSets = _songSets
        .map(
          (set) => set.copyWith(
            songs: set.songs
                .map(
                  (song) =>
                      _sameStoredSong(song, originalSong) ? updatedSong : song,
                )
                .toList(),
          ),
        )
        .toList();
  }

  void _toggleSongFavorite(Song song, {VoidCallback? onChanged}) {
    Song? updatedSong;

    setState(() {
      final index = _songs.indexWhere(
        (storedSong) => _sameStoredSong(storedSong, song),
      );
      if (index == -1) {
        return;
      }

      final originalSong = _songs[index];
      updatedSong = originalSong.copyWith(isFavorite: !originalSong.isFavorite);
      _songs[index] = updatedSong!;
      _replaceSongInSets(originalSong, updatedSong!);

      if (_selectedSong != null && _isSameSongResult(_selectedSong!, song)) {
        _selectedSong = _songWithCurrentFavorite(_selectedSong!);
      }
      if (_lastResultSong != null &&
          _isSameSongResult(_lastResultSong!, song)) {
        _lastResultSong = _songWithCurrentFavorite(_lastResultSong!);
      }
    });

    if (updatedSong == null) {
      return;
    }

    _saveSongs();
    _saveSongSets();
    onChanged?.call();
  }

  bool _hasSongSetNamed(String name, {String? exceptId}) {
    final normalizedName = name.trim().toLowerCase();
    return _songSets.any(
      (set) =>
          set.id != exceptId && set.name.trim().toLowerCase() == normalizedName,
    );
  }

  Future<void> _loadSponsorAds() async {
    final config = await loadSponsorAdConfig();
    if (!mounted) {
      return;
    }

    setState(() {
      _bottomAd = config.bottomAd;
      final mainAd = config.mainAd;
      if (mainAd == null) {
        debugPrint('MainSponsorAd is null: fallback main panel selected.');
      } else if (!mainAd.enabled) {
        debugPrint('MainSponsorAd is disabled: fallback main panel selected.');
      }
      _mainAd = mainAd != null && mainAd.enabled ? mainAd : fallbackMainAd;
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
                        _songs = ensureSongIds(sampleSongs);
                        _syncArtistFilterState();
                      });
                      _saveSongs();
                      _saveDisabledRandomArtists();

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
    return buildSongShareText(
      song: song,
      defaultMessage: _defaultShareMessage,
      includeSongLink: _includeSongLink,
      includeTodayTag: _includeTodayTag,
    );
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

  Song _canonicalStoredSong(Song song) {
    for (final storedSong in _songs) {
      if (_sameStoredSong(storedSong, song)) {
        return storedSong;
      }
    }
    return song;
  }

  void _recommendSelectedSong(Song song, {String? sourceSetName}) {
    final resultSong = _canonicalStoredSong(song);
    setState(() {
      _selectedSong = resultSong;
      _lastResultSong = resultSong;
      _isSponsorPick = false;
      _resultSongSetName = sourceSetName;
      _includeSongLink = true;
      _resetShareText(resultSong);
    });

    _runAfterFrame(() {
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  void _pickRandomSong() {
    if (_songs.isEmpty) {
      _showRootSnackBar('저장된 곡이 없어요. 노래 저장소에서 곡을 추가해주세요.');
      return;
    }

    if (_randomMode == RandomMode.songSets) {
      _pickRandomSongFromSets();
      return;
    }

    final candidateSongs = _randomCandidateSongs();
    if (candidateSongs.isEmpty) {
      _showRootSnackBar('뽑기 후보가 없어요. 노래 저장소에서 랜덤 후보로 사용할 가수명을 활성화해 주세요.');
      return;
    }

    final previousResult = _isSponsorPick
        ? (_selectedSong ?? _lastResultSong)
        : _selectedSong ?? _lastResultSong;
    var randomCandidates = candidateSongs;
    if (previousResult != null && candidateSongs.length > 1) {
      final filteredSongs = candidateSongs
          .where((song) => !_isSameSongResult(song, previousResult))
          .toList();
      if (filteredSongs.isNotEmpty) {
        randomCandidates = filteredSongs;
      }
    }

    final nextSong = randomCandidates[_random.nextInt(randomCandidates.length)];

    setState(() {
      _selectedSong = nextSong;
      _lastResultSong = nextSong;
      _isSponsorPick = false;
      _resultSongSetName = null;
      _includeSongLink = true;
      _resetShareText(nextSong);
    });
  }

  void _pickRandomSongFromSets() {
    final selectedSets = _selectedSongSets();
    if (selectedSets.isEmpty) {
      setState(() {
        _randomMode = RandomMode.artistRandom;
        _selectedSongSetIds = [];
      });
      _saveRandomSelection();
      _showRootSnackBar('가수명 랜덤으로 변경했어요.');
      return;
    }

    final candidateSongs = _randomSetCandidateSongs(selectedSets);
    if (candidateSongs.isEmpty) {
      _showRootSnackBar('선택한 세트에 곡이 없어요.');
      return;
    }

    final previousResult = _isSponsorPick
        ? (_selectedSong ?? _lastResultSong)
        : _selectedSong ?? _lastResultSong;
    var randomCandidates = candidateSongs;
    if (previousResult != null && candidateSongs.length > 1) {
      final filteredSongs = candidateSongs
          .where(
            (candidate) => !_isSameSongResult(candidate.song, previousResult),
          )
          .toList();
      if (filteredSongs.isNotEmpty) {
        randomCandidates = filteredSongs;
      }
    }

    final nextCandidate =
        randomCandidates[_random.nextInt(randomCandidates.length)];

    setState(() {
      _selectedSong = nextCandidate.song;
      _lastResultSong = nextCandidate.song;
      _isSponsorPick = false;
      _resultSongSetName = nextCandidate.setName;
      _includeSongLink = true;
      _resetShareText(nextCandidate.song);
    });
  }

  void _pickMainSponsorSong() {
    final sponsorSong = _mainAd.song;
    if (sponsorSong == null) {
      _showRootSnackBar('추천곡 정보가 아직 없습니다.');
      return;
    }

    setState(() {
      _selectedSong = sponsorSong;
      _lastResultSong = sponsorSong;
      _isSponsorPick = true;
      _resultSongSetName = null;
      _includeSongLink = true;
      _resetShareText(sponsorSong);
    });
  }

  List<Song> _randomCandidateSongs() {
    return _songs
        .where((song) => !_disabledRandomArtists.contains(song.artist))
        .toList();
  }

  List<SongSetRandomCandidate> _randomSetCandidateSongs(List<SongSet> sets) {
    return [
      for (final songSet in sets)
        for (final song in songSet.songs)
          SongSetRandomCandidate(song: song, setName: songSet.name),
    ];
  }

  String _drawScopeLabel() {
    if (_randomMode == RandomMode.songSets) {
      final selectedSets = _selectedSongSets();
      if (selectedSets.isEmpty) {
        return '현재 뽑기 범위: 선택된 세트 없음';
      }
      if (selectedSets.length == 1) {
        return '현재 뽑기 범위: ‘${selectedSets.first.name}’ 세트';
      }
      return '현재 뽑기 범위: 세트 ${selectedSets.length}개 선택 중';
    }

    final groupedSongs = songsByArtist(_songs);
    if (groupedSongs.isEmpty) {
      return '현재 뽑기 범위: 저장된 곡 없음';
    }

    final activeArtists = groupedSongs.keys
        .where((artist) => !_disabledRandomArtists.contains(artist))
        .toList();
    if (activeArtists.length == groupedSongs.length) {
      return '현재 뽑기 범위: 전체 곡';
    }
    if (activeArtists.length == 1) {
      return '현재 뽑기 범위: ${activeArtists.first}';
    }
    if (activeArtists.isEmpty) {
      return '현재 뽑기 범위: 선택된 가수명 없음';
    }
    return '현재 뽑기 범위: 선택한 가수명 ${activeArtists.length}팀';
  }

  bool _isArtistRandomEnabled(String artist) {
    return !_disabledRandomArtists.contains(artist);
  }

  int _activeArtistCount() {
    return songsByArtist(_songs).keys.where(_isArtistRandomEnabled).length;
  }

  void _showToggleArtistRandomDialog(
    String artist, {
    required bool enable,
    VoidCallback? onChanged,
  }) {
    final willClearFilter =
        !enable && _isArtistRandomEnabled(artist) && _activeArtistCount() <= 1;
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: Text(
            willClearFilter ? '랜덤 필터 비우기' : (enable ? '랜덤 활성화' : '랜덤 해제'),
          ),
          content: Text(
            willClearFilter
                ? '모든 가수명을 랜덤 후보에서 제외하면 오늘의 한 곡을 뽑을 수 없어요.\n'
                      '전부 해제할까요?'
                : enable
                ? '$artist 곡을 오늘의 한 곡 후보에 포함할까요?'
                : '$artist 곡을 오늘의 한 곡 후보에서 제외할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop();
                _setArtistRandomEnabled(artist, enable: enable);
                onChanged?.call();
              },
              child: Text(willClearFilter ? '전부 해제' : (enable ? '활성화' : '해제')),
            ),
          ],
        );
      },
    );
  }

  void _setArtistRandomEnabled(String artist, {required bool enable}) {
    setState(() {
      if (enable) {
        _disabledRandomArtists.remove(artist);
      } else {
        _disabledRandomArtists.add(artist);
      }
    });
    _saveDisabledRandomArtists();
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

  Widget _songRecommendationButton(Song song, {String? sourceSetName}) {
    return IconButton(
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      tooltip: '이 곡 추천하기',
      onPressed: () =>
          _recommendSelectedSong(song, sourceSetName: sourceSetName),
      icon: const Icon(Icons.recommend_outlined, size: 19),
    );
  }

  Future<bool> _showFileImportGuidance({
    required String title,
    required String message,
  }) async {
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (guideContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(guideContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(guideContext).pop(true),
              child: const Text('파일 선택'),
            ),
          ],
        );
      },
    );
    return shouldContinue == true;
  }

  void _showSongActionCard(
    Song song, {
    required VoidCallback onSongChanged,
    VoidCallback? onSongUpdated,
    String? sourceSetName,
    SongSet? removeFromSet,
    VoidCallback? onRemovedFromSet,
    VoidCallback? onDeleted,
  }) {
    showDialog<void>(
      context: context,
      builder: (cardContext) {
        return StatefulBuilder(
          builder: (context, refreshCard) {
            final currentSong = _canonicalStoredSong(song);
            final isFavorite = _isSongFavorite(currentSong);
            final hasLink = _hasSongLink(currentSong);
            final matchingSetCount = _songSetsContainingSong(
              currentSong,
            ).length;
            final visibleTags = visibleSongTags(currentSong.tags);
            final memoText = currentSong.memo.trim();
            final tagSummary = buildSongCardTagSummary(visibleTags);
            final showSetCount =
                memoText.isEmpty && tagSummary.isEmpty && matchingSetCount > 0;

            void closeThen(VoidCallback action) {
              Navigator.of(cardContext).pop();
              _runAfterFrame(action);
            }

            Widget actionItem({
              required Key key,
              required IconData icon,
              required String label,
              required VoidCallback onTap,
              Color? color,
            }) {
              return Expanded(
                child: InkWell(
                  key: key,
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: tdmHoverColor,
                  splashColor: tdmHoverColor,
                  highlightColor: Colors.transparent,
                  onTap: onTap,
                  child: SizedBox(
                    height: 52,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 19, color: color ?? tdmTextMain),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color ?? tdmTextMain,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                key: const ValueKey('song-action-card'),
                width: min(MediaQuery.sizeOf(cardContext).width - 40, 520),
                decoration: BoxDecoration(
                  color: tdmCardBackground,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tdmBorder),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A173A3A),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 10, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                currentSong.artist,
                                key: const ValueKey('song-card-artist'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: tdmTextSub,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('song-card-favorite'),
                              tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
                              onPressed: () {
                                _toggleSongFavorite(
                                  currentSong,
                                  onChanged: () {
                                    refreshCard(() {});
                                    onSongChanged();
                                  },
                                );
                              },
                              icon: Icon(
                                isFavorite ? Icons.star : Icons.star_border,
                                color: isFavorite
                                    ? const Color(0xFFF2B84B)
                                    : tdmTextSub,
                                size: 25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Text(
                          currentSong.title,
                          key: const ValueKey('song-card-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: tdmTextMain,
                            fontSize: 27,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (memoText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: Text(
                            memoText,
                            key: const ValueKey('song-card-memo'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: tdmTextSub,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      if (tagSummary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                          child: Text(
                            tagSummary,
                            key: const ValueKey('song-card-tags'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: tdmPrimaryDark,
                              fontSize: 13,
                              height: 1.35,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (showSetCount)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                          child: Text(
                            '포함된 세트 $matchingSetCount개',
                            key: const ValueKey('song-card-set-count'),
                            style: const TextStyle(
                              color: tdmTextSub,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Container(
                        key: const ValueKey('song-card-action-bar'),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFDFF8F3),
                          border: Border(top: BorderSide(color: tdmBorder)),
                        ),
                        child: Row(
                          children: [
                            actionItem(
                              key: const ValueKey('song-card-link-action'),
                              icon: hasLink ? Icons.link : Icons.search,
                              label: hasLink ? '링크' : '검색',
                              onTap: () => _openSongLinkOrYoutube(currentSong),
                              color: hasLink ? tdmLinkBlue : null,
                            ),
                            actionItem(
                              key: const ValueKey('song-card-sets-action'),
                              icon: Icons.folder_open_outlined,
                              label: '세트',
                              onTap: () =>
                                  _showSongIncludedSetsDialog(currentSong),
                            ),
                            actionItem(
                              key: const ValueKey('song-card-edit-action'),
                              icon: Icons.edit_outlined,
                              label: '수정',
                              onTap: () {
                                closeThen(() {
                                  _showEditSongDialog(
                                    currentSong,
                                    onSongUpdated:
                                        onSongUpdated ?? onSongChanged,
                                  );
                                });
                              },
                            ),
                            if (removeFromSet != null)
                              actionItem(
                                key: const ValueKey('song-card-remove-action'),
                                icon: Icons.remove_circle_outline,
                                label: '제외',
                                onTap: () {
                                  closeThen(() {
                                    _showRemoveSingleSongFromSetDialog(
                                      removeFromSet,
                                      currentSong,
                                      onRemoved: onRemovedFromSet,
                                    );
                                  });
                                },
                              )
                            else
                              actionItem(
                                key: const ValueKey('song-card-delete-action'),
                                icon: Icons.delete_outline,
                                label: '삭제',
                                color: Colors.red.shade700,
                                onTap: () {
                                  closeThen(() {
                                    _showDeleteSongDialog(
                                      currentSong,
                                      onDeleted: onDeleted ?? onSongChanged,
                                    );
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: () => Navigator.of(cardContext).pop(),
                          child: const Text('닫기'),
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

  Future<void> _openSponsorAdLink(SponsorAd ad) async {
    await _openSponsorLink(ad.linkUrl);
  }

  Future<void> _openSponsorLink(String linkUrl) async {
    final rawLink = linkUrl.trim();
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

    await _saveExportFileToPhone(
      songs: _songs,
      fileBaseName: buildSongsExportFileBaseName(DateTime.now()),
    );
  }

  BackupSourceSnapshot _currentBackupSource() {
    return BackupSourceSnapshot(
      songs: List<Song>.of(_songs),
      sets: _songSets
          .map(
            (set) => BackupSourceSet(
              id: set.id,
              name: set.name,
              songs: List<Song>.of(set.songs),
            ),
          )
          .toList(),
      disabledRandomArtists: Set<String>.of(_disabledRandomArtists),
      selectedSetIds: List<String>.of(_selectedSongSetIds),
      defaultShareMessage: _defaultShareMessage,
      randomMode: _randomMode.name,
      artistOrder: List<String>.of(_artistOrder),
    );
  }

  Future<void> _exportAppBackup() async {
    try {
      const serializer = BackupSerializer();
      final now = DateTime.now();
      final document = serializer.createDocument(
        source: _currentBackupSource(),
        appVersion: appSemanticVersion,
        createdAt: now,
        platform: kIsWeb ? 'web' : 'android',
      );
      final jsonText = serializer.encode(document);
      final savedPath = await FileSaver.instance.saveAs(
        name: buildAppBackupFileBaseName(now),
        bytes: Uint8List.fromList(utf8.encode(jsonText)),
        fileExtension: 'json',
        mimeType: MimeType.json,
      );

      if (savedPath == null || savedPath.trim().isEmpty) {
        _showRootSnackBar('앱 백업을 내보내지 못했어요. 다시 시도해 주세요.');
        return;
      }
      _showRootSnackBar('앱 백업을 내보냈어요.');
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('App backup export failed: $error\n$stackTrace');
      }
      _showRootSnackBar('앱 백업을 내보내지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<void> _importAppBackup() async {
    try {
      final shouldSelect = await _showFileImportGuidance(
        title: '앱 백업 불러오기',
        message: appBackupImportGuidance,
      );
      if (!shouldSelect) {
        return;
      }
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        _showRootSnackBar('백업 파일을 불러오지 못했어요. 파일을 확인해 주세요.');
        return;
      }

      const serializer = BackupSerializer();
      final document = serializer.decode(utf8.decode(bytes));
      final restored = serializer.restore(document);
      if (!mounted) {
        return;
      }

      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (confirmContext) {
          return AlertDialog(
            title: const Text('앱 백업을 불러올까요?'),
            content: Text(
              '앱 백업을 불러오면 현재 앱 데이터가 백업 파일 내용으로 바뀝니다.\n'
              '계속할까요?\n\n'
              '곡 ${document.summary.songCount}곡 · '
              '세트 ${document.summary.setCount}개 · '
              '좋아요 ${document.summary.favoriteCount}곡',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(confirmContext).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(confirmContext).pop(true),
                child: const Text('백업 불러오기'),
              ),
            ],
          );
        },
      );
      if (shouldRestore != true || !mounted) {
        return;
      }

      await _applyBackupRestore(restored);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      _showRootSnackBar(
        '앱 백업을 불러왔어요. '
        '곡 ${restored.songs.length}곡, 세트 ${restored.sets.length}개를 복원했습니다.',
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('App backup import failed: $error\n$stackTrace');
      }
      _showRootSnackBar('이 파일은 오늘의 한 곡 앱 백업 파일이 아니거나 손상되었어요.');
    }
  }

  Future<void> _applyBackupRestore(BackupRestoreSnapshot restored) async {
    final restoredSets = restored.sets
        .map((set) => SongSet(id: set.id, name: set.name, songs: set.songs))
        .toList();
    final restoredRandomMode =
        restored.randomMode == RandomMode.songSets.name &&
            restored.selectedSetIds.isNotEmpty
        ? RandomMode.songSets
        : RandomMode.artistRandom;

    setState(() {
      _songs = List<Song>.of(restored.songs);
      _songSets = _songSetsSyncedWithSongs(restoredSets, _songs);
      final existingSetIds = _songSets.map((set) => set.id).toSet();
      _selectedSongSetIds = restored.selectedSetIds
          .where(existingSetIds.contains)
          .toList();
      _randomMode =
          restoredRandomMode == RandomMode.songSets &&
              _selectedSongSetIds.isNotEmpty
          ? RandomMode.songSets
          : RandomMode.artistRandom;
      final existingArtists = songsByArtist(_songs).keys.toSet();
      _disabledRandomArtists = restored.disabledRandomArtists
          .where(existingArtists.contains)
          .toSet();
      _defaultShareMessage = restored.defaultShareMessage;
      _artistOrder = reconcileArtistOrder(
        songsByArtist(_songs).keys,
        restored.artistOrder,
      );
      _artistSortMode = _artistOrder.isEmpty
          ? ArtistSortMode.defaultOrder
          : ArtistSortMode.custom;
      _selectedSong = null;
      _lastResultSong = null;
      _isSponsorPick = false;
      _resultSongSetName = null;
      _shareTextController.clear();
      _includeTodayTag = true;
      _includeSongLink = true;
    });

    await Future.wait([
      SongStorage.saveSongs(_songs),
      SongStorage.saveSongSets(_songSets),
      SongStorage.saveRandomMode(_randomMode),
      SongStorage.saveSelectedSongSetIds(_selectedSongSetIds),
      SongStorage.saveDisabledRandomArtists(_disabledRandomArtists),
      SongStorage.saveDefaultShareMessage(_defaultShareMessage),
      SongStorage.saveArtistOrder(_artistOrder),
    ]);
  }

  Future<void> _exportArtistSongs(String artist) async {
    final artistSongs = _songs.where((song) => song.artist == artist).toList();
    if (artistSongs.isEmpty) {
      _showRootSnackBar('내보낼 곡이 없습니다.');
      return;
    }

    await _saveExportFileToPhone(
      songs: artistSongs,
      fileBaseName: buildSongsExportFileBaseName(
        DateTime.now(),
        artist: artist,
      ),
    );
  }

  String _safeFileNamePart(String value) {
    return safeExportFileNamePart(value);
  }

  Future<void> _saveExportFileToPhone({
    required List<Song> songs,
    required String fileBaseName,
  }) async {
    final fileName = '$fileBaseName.txt';

    try {
      final exportText = _buildSongExportText(songs);

      final savedPath = await FileSaver.instance.saveAs(
        name: fileBaseName,
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
    return buildExportTimestamp(DateTime.now());
  }

  String _buildSongExportText(List<Song> songs) {
    final buffer = StringBuffer()
      ..writeln('# 오늘의 한 곡 내보내기')
      ..writeln('# 이 파일은 오늘의 한 곡 앱에서 다시 불러올 수 있도록 만든 곡 세트 파일입니다.')
      ..writeln('# 곡은 [곡] 단위로 구분됩니다.')
      ..writeln('# 가수명과 곡명은 필수입니다.')
      ..writeln('# 메모와 태그는 비워둘 수 있습니다.')
      ..writeln('# 태그는 공백으로 구분해주세요.');

    for (final song in songs) {
      final tags = visibleSongTags(
        song.tags,
      ).where((tag) => tag != '#오늘의한곡').join(' ');

      buffer
        ..writeln()
        ..writeln('[곡]')
        ..writeln('가수명: ${_exportSingleLine(song.artist)}')
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
      final shouldSelect = await _showFileImportGuidance(
        title: 'TXT 불러오기',
        message: songTxtImportGuidance,
      );
      if (!shouldSelect) {
        return;
      }
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

      final drafts = parsedSongs
          .map(
            (song) => PasteSongDraft(
              sourceLine: '${song.artist} - ${song.title}',
              artist: song.artist,
              title: song.title,
              tags: song.tags,
              memo: song.memo,
              link: song.link,
            ),
          )
          .toList();
      _showPasteSongAnalysisDialog(
        PasteSongAnalysis(
          inferredArtist: '',
          drafts: drafts,
          candidates: buildPasteSongCandidates(
            drafts: drafts,
            inferredArtist: '',
            existingSongs: _songs,
          ),
        ),
        dialogTitle: 'TXT 불러오기 결과',
        onSongsAdded: onSongsImported,
      );
    } catch (_) {
      _showImportResultDialog('불러오기에 실패했습니다.');
    }
  }

  List<Song> _parseImportedSongs(String text) {
    return parseTdmSongText(text);
  }

  String _songDuplicateKey(Song song) {
    return '${song.artist.trim().toLowerCase()}\n'
        '${song.title.trim().toLowerCase()}';
  }

  String _songWidgetKey(Song song) {
    return song.id.isNotEmpty ? song.id : _songDuplicateKey(song);
  }

  bool _sameStoredSong(Song first, Song second) {
    if (first.id.isNotEmpty && second.id.isNotEmpty) {
      return first.id == second.id;
    }
    return _songDuplicateKey(first) == _songDuplicateKey(second);
  }

  Song? _storedSongMatching(Song song) {
    for (final storedSong in _songs) {
      if (_sameStoredSong(storedSong, song)) {
        return storedSong;
      }
    }
    return null;
  }

  Song _songWithCurrentFavorite(Song song) {
    final storedSong = _storedSongMatching(song);
    if (storedSong == null) {
      return song;
    }
    return song.copyWith(isFavorite: storedSong.isFavorite);
  }

  bool _isSongFavorite(Song song) {
    return _storedSongMatching(song)?.isFavorite ?? song.isFavorite;
  }

  bool _isSameSongResult(Song first, Song second) {
    return _sameStoredSong(first, second);
  }

  Widget _favoriteSongIconButton(Song song, {VoidCallback? onChanged}) {
    final isFavorite = _isSongFavorite(song);
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: isFavorite
          ? '\uC990\uACA8\uCC3E\uAE30 \uD574\uC81C'
          : '\uC990\uACA8\uCC3E\uAE30 \uCD94\uAC00',
      onPressed: () => _toggleSongFavorite(song, onChanged: onChanged),
      icon: Icon(
        isFavorite ? Icons.star : Icons.star_border,
        size: 19,
        color: isFavorite ? const Color(0xFFF2B84B) : tdmTextSub,
      ),
    );
  }

  Widget _favoriteFilterToggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: value
          ? '\uC990\uACA8\uCC3E\uAE30\uB9CC \uBCF4\uAE30 \uD574\uC81C'
          : '\uC990\uACA8\uCC3E\uAE30\uB9CC \uBCF4\uAE30',
      onPressed: () => onChanged(!value),
      icon: Icon(
        value ? Icons.star : Icons.star_border,
        size: 22,
        color: value ? const Color(0xFFF2B84B) : tdmTextSub,
      ),
    );
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
          onOpenOfficialX: _openOfficialX,
          onExportBackup: _exportAppBackup,
          onImportBackup: _importAppBackup,
          onResetApp: _showResetAppDialog,
        );
      },
    );
  }

  Future<void> _openContactEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'todaydrawmusic@gmail.com',
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

  Future<void> _openOfficialX() async {
    await _openSponsorLink('https://x.com/todaydrawmusic');
  }

  void _showResetAppDialog() {
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('앱을 초기화할까요?'),
          content: const Text(
            '앱을 초기화하면 모든 곡, 세트, 좋아요와 설정이 삭제됩니다.\n'
            '초기화 전 앱 백업을 내보내는 것을 권장합니다.\n'
            '계속할까요?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop();
                _resetApp();
              },
              child: const Text('초기화'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetApp() async {
    setState(() {
      _songs = [];
      _selectedSong = null;
      _lastResultSong = null;
      _isSponsorPick = false;
      _resultSongSetName = null;
      _disabledRandomArtists.clear();
      _songSets.clear();
      _randomMode = RandomMode.artistRandom;
      _selectedSongSetIds.clear();
      _defaultShareMessage = '';
      _lastAddSongTab = AddSongTab.individual;
      _artistOrder = [];
      _artistSortMode = ArtistSortMode.defaultOrder;
      _shareTextController.clear();
      _includeTodayTag = true;
      _includeSongLink = true;
    });
    await SongStorage.resetAllAppData();
    _showRootSnackBar('앱 데이터를 초기화했어요.');
  }

  void _addSong(Song song) {
    final storedSong = song.id.isEmpty
        ? song.copyWith(id: createSongId())
        : song;
    setState(() {
      _songs.add(storedSong);
      _syncArtistFilterState();
    });
    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('곡이 추가되었습니다.')));
  }

  void _updateSong(Song originalSong, Song updatedSong) {
    var didUpdate = false;

    setState(() {
      final index = _songs.indexWhere(
        (song) => _sameStoredSong(song, originalSong),
      );

      if (index == -1) {
        return;
      }

      updatedSong = updatedSong.copyWith(
        id: _songs[index].id,
        isFavorite: _songs[index].isFavorite,
      );
      _songs[index] = updatedSong;
      didUpdate = true;
      _replaceSongInSets(originalSong, updatedSong);
      _syncArtistFilterState();

      if (identical(_selectedSong, originalSong)) {
        _selectedSong = updatedSong;
        _lastResultSong = updatedSong;
        _includeSongLink = true;
        _resetShareText(updatedSong);
      } else if (_lastResultSong != null &&
          _isSameSongResult(_lastResultSong!, originalSong)) {
        _lastResultSong = updatedSong;
      }
    });

    if (!didUpdate) {
      return;
    }

    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();

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

  void _runAfterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      callback();
    });
  }

  void _runAfterRouteSettled(VoidCallback callback) {
    Future<void>.delayed(const Duration(milliseconds: 160), () {
      if (!mounted) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        callback();
      });
    });
  }

  void _disposeTextControllerAfterRoute(TextEditingController controller) {
    _runAfterRouteSettled(controller.dispose);
  }

  void _deleteSong(Song song) {
    setState(() {
      _songs.removeWhere((storedSong) => _sameStoredSong(storedSong, song));
      _syncArtistFilterState();
      _syncSongSetsWithSongs();
      if (_selectedSong != null && _sameStoredSong(_selectedSong!, song)) {
        _selectedSong = null;
        _shareTextController.clear();
        _includeSongLink = true;
        _resultSongSetName = null;
      }
      if (_lastResultSong != null &&
          _isSameSongResult(_lastResultSong!, song)) {
        _lastResultSong = null;
      }
      if (_selectedSong == null) {
        _isSponsorPick = false;
        _resultSongSetName = null;
      }
    });
    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('곡이 삭제되었습니다.')));
  }

  void _resetToInitialScreen() {
    setState(() {
      _selectedSong = null;
      _isSponsorPick = false;
      _resultSongSetName = null;
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
    final shouldClearLastResult =
        _lastResultSong != null &&
        songsToDelete.any((song) => _isSameSongResult(song, _lastResultSong!));

    setState(() {
      _songs.removeWhere((song) => song.artist == artist);
      _syncArtistFilterState();
      _syncSongSetsWithSongs();
      if (shouldResetResult) {
        _selectedSong = null;
        _shareTextController.clear();
        _includeSongLink = true;
        _resultSongSetName = null;
      }
      if (shouldClearLastResult) {
        _lastResultSong = null;
      }
      if (_selectedSong == null) {
        _isSponsorPick = false;
        _resultSongSetName = null;
      }
    });
    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();
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
            '이 가수명의 곡을 모두 삭제할까요?\n\n'
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

  List<String> _artistNamesForSort(ArtistSortMode mode) {
    final entries = songsByArtist(_songs).entries.toList();
    switch (mode) {
      case ArtistSortMode.defaultOrder:
      case ArtistSortMode.added:
        break;
      case ArtistSortMode.custom:
        final orderIndexes = {
          for (var index = 0; index < _artistOrder.length; index++)
            _artistOrder[index].toLowerCase(): index,
        };
        entries.sort((a, b) {
          final left = orderIndexes[a.key.toLowerCase()] ?? _artistOrder.length;
          final right =
              orderIndexes[b.key.toLowerCase()] ?? _artistOrder.length;
          return left.compareTo(right);
        });
      case ArtistSortMode.name:
        entries.sort(
          (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
        );
      case ArtistSortMode.songCount:
        entries.sort((a, b) {
          final countCompare = b.value.length.compareTo(a.value.length);
          if (countCompare != 0) {
            return countCompare;
          }
          return a.key.toLowerCase().compareTo(b.key.toLowerCase());
        });
    }
    return entries.map((entry) => entry.key).toList();
  }

  Future<void> _showArtistOrderEditor({VoidCallback? onSaved}) async {
    final initialOrder = _artistOrder.isNotEmpty
        ? reconcileArtistOrder(songsByArtist(_songs).keys, _artistOrder)
        : _artistNamesForSort(
            _artistSortMode == ArtistSortMode.custom
                ? ArtistSortMode.added
                : _artistSortMode,
          );
    if (initialOrder.isEmpty) {
      _showRootSnackBar('순서를 편집할 가수명이 없어요.');
      return;
    }
    final draftOrder = List<String>.of(initialOrder);

    await showDialog<void>(
      context: context,
      builder: (editorContext) {
        return StatefulBuilder(
          builder: (context, refreshEditor) {
            return AlertDialog(
              title: const Text('가수 순서 편집'),
              content: SizedBox(
                width: min(MediaQuery.sizeOf(editorContext).width - 64, 520),
                height: min(MediaQuery.sizeOf(editorContext).height * 0.6, 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '드래그 핸들을 움직여 가수별 목록 순서를 정해 주세요.',
                      style: TextStyle(color: tdmTextSub, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        itemCount: draftOrder.length,
                        onReorderItem: (oldIndex, newIndex) {
                          refreshEditor(() {
                            final artist = draftOrder.removeAt(oldIndex);
                            draftOrder.insert(newIndex, artist);
                          });
                        },
                        itemBuilder: (context, index) {
                          final artist = draftOrder[index];
                          return ListTile(
                            key: ValueKey('artist-order-$artist'),
                            contentPadding: EdgeInsets.zero,
                            leading: ReorderableDragStartListener(
                              index: index,
                              child: const Tooltip(
                                message: '드래그해서 순서 변경',
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                            title: Text(artist),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final shouldReset = await showDialog<bool>(
                          context: editorContext,
                          builder: (confirmContext) {
                            return AlertDialog(
                              title: const Text('기본 정렬로 되돌릴까요?'),
                              content: const Text(
                                '가수 순서를 기본 정렬로 되돌릴까요?\n'
                                '직접 정한 순서는 초기화됩니다.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(confirmContext).pop(false),
                                  child: const Text('취소'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.of(confirmContext).pop(true),
                                  child: const Text('되돌리기'),
                                ),
                              ],
                            );
                          },
                        );
                        if (shouldReset != true || !mounted) {
                          return;
                        }
                        setState(() {
                          _artistOrder = [];
                          _artistSortMode = ArtistSortMode.defaultOrder;
                        });
                        await SongStorage.saveArtistOrder(const []);
                        if (editorContext.mounted) {
                          Navigator.of(editorContext).pop();
                        }
                        onSaved?.call();
                      },
                      child: const Text('기본 정렬로 되돌리기'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(editorContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () async {
                    setState(() {
                      _artistOrder = List<String>.of(draftOrder);
                      _artistSortMode = ArtistSortMode.custom;
                    });
                    await SongStorage.saveArtistOrder(_artistOrder);
                    if (editorContext.mounted) {
                      Navigator.of(editorContext).pop();
                    }
                    onSaved?.call();
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSongStorageSheet() {
    final setSearchController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        String? setStorageNotice;

        return StatefulBuilder(
          builder: (context, refreshSheet) {
            final groupedSongs = songsByArtist(_songs);
            final artistEntries = groupedSongs.entries.toList();
            switch (_artistSortMode) {
              case ArtistSortMode.defaultOrder:
              case ArtistSortMode.added:
                break;
              case ArtistSortMode.custom:
                final orderIndexes = {
                  for (var index = 0; index < _artistOrder.length; index++)
                    _artistOrder[index].toLowerCase(): index,
                };
                artistEntries.sort((a, b) {
                  final left =
                      orderIndexes[a.key.toLowerCase()] ?? _artistOrder.length;
                  final right =
                      orderIndexes[b.key.toLowerCase()] ?? _artistOrder.length;
                  return left.compareTo(right);
                });
              case ArtistSortMode.name:
                artistEntries.sort(
                  (a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()),
                );
              case ArtistSortMode.songCount:
                artistEntries.sort((a, b) {
                  final countCompare = b.value.length.compareTo(a.value.length);
                  if (countCompare != 0) {
                    return countCompare;
                  }
                  return a.key.toLowerCase().compareTo(b.key.toLowerCase());
                });
            }
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
                      SegmentedButton<SongStorageTab>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: SongStorageTab.songs,
                            label: Text('노래저장소'),
                          ),
                          ButtonSegment(
                            value: SongStorageTab.sets,
                            label: Text('세트저장소'),
                          ),
                        ],
                        selected: {_songStorageTab},
                        onSelectionChanged: (selection) {
                          refreshSheet(() {
                            _songStorageTab = selection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_songStorageTab == SongStorageTab.songs) ...[
                        Text(
                          '총 ${_songs.length}곡 · 가수명 ${groupedSongs.length}팀',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  _showAddSongsTabbedDialog(
                                    onSongsAdded: () => refreshSheet(() {}),
                                  );
                                },
                                child: const Text(
                                  '곡 추가',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  _showSongBackupMenu(
                                    onSongsImported: () => refreshSheet(() {}),
                                  );
                                },
                                child: const Text(
                                  '설정',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          key: const ValueKey('artist-storage-toolbar'),
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 112,
                                maxWidth: 148,
                              ),
                              child: PopupMenuButton<ArtistSortMode>(
                                key: const ValueKey('artist-sort-menu'),
                                onSelected: (mode) {
                                  if (mode == ArtistSortMode.custom) {
                                    _showArtistOrderEditor(
                                      onSaved: () => refreshSheet(() {}),
                                    );
                                    return;
                                  }
                                  refreshSheet(() {
                                    _artistSortMode = mode;
                                  });
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: ArtistSortMode.defaultOrder,
                                    child: Text('기본'),
                                  ),
                                  PopupMenuItem(
                                    value: ArtistSortMode.name,
                                    child: Text('이름'),
                                  ),
                                  PopupMenuItem(
                                    value: ArtistSortMode.added,
                                    child: Text('등록'),
                                  ),
                                  PopupMenuItem(
                                    value: ArtistSortMode.songCount,
                                    child: Text('곡수'),
                                  ),
                                  PopupMenuItem(
                                    value: ArtistSortMode.custom,
                                    child: Text('사용자지정'),
                                  ),
                                ],
                                child: Container(
                                  height: 40,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          switch (_artistSortMode) {
                                            ArtistSortMode.defaultOrder =>
                                              '정렬순서',
                                            ArtistSortMode.name => '이름',
                                            ArtistSortMode.added => '등록',
                                            ArtistSortMode.songCount => '곡수',
                                            ArtistSortMode.custom => '사용자지정',
                                          },
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.arrow_drop_down),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_artistSortMode == ArtistSortMode.custom) ...[
                              OutlinedButton(
                                onPressed: () => _showArtistOrderEditor(
                                  onSaved: () => refreshSheet(() {}),
                                ),
                                child: const Text('편집', maxLines: 1),
                              ),
                              const SizedBox(width: 4),
                            ],
                            const Spacer(),
                            TextButton(
                              key: const ValueKey('all-songs-button'),
                              onPressed: () => _showAllSongsDialog(
                                onSongsChanged: () => refreshSheet(() {}),
                              ),
                              child: const Text(
                                '전체곡 보기',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_randomMode == RandomMode.songSets &&
                            _selectedSongSetIds.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: const Text(
                              '세트 랜덤 사용 중에는 가수명 랜덤 설정이 잠시 적용되지 않아요.\n'
                              '세트 선택을 모두 해제하면 다시 가수명 랜덤을 사용할 수 있어요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: tdmTextSub,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        ...artistEntries.map(
                          (entry) => ArtistSongGroupTile(
                            artist: entry.key,
                            songs: entry.value,
                            isRandomEnabled: _isArtistRandomEnabled(entry.key),
                            onRandomToggle: _randomMode == RandomMode.songSets
                                ? null
                                : (enabled) {
                                    _showToggleArtistRandomDialog(
                                      entry.key,
                                      enable: enabled,
                                      onChanged: () => refreshSheet(() {}),
                                    );
                                  },
                            onTap: () => _showArtistSongsDialog(
                              entry.key,
                              onSongChanged: () => refreshSheet(() {}),
                            ),
                          ),
                        ),
                      ] else ...[
                        Text(
                          _selectedSongSetIds.isEmpty
                              ? '저장된 세트 ${_songSets.length}개'
                              : '저장된 세트 ${_songSets.length}개 · 랜덤 선택 ${_selectedSongSetIds.length}개',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _songSets.length >= maxSongSetCount
                                    ? null
                                    : () => _showAllSongsDialog(
                                        allowDeleteSelectedSongs: false,
                                        onSongsChanged: () {
                                          _songStorageTab = SongStorageTab.sets;
                                          refreshSheet(() {});
                                        },
                                      ),
                                child: const Text(
                                  '\uC138\uD2B8 \uB9CC\uB4E4\uAE30',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    _showSongSetStorageSettingsMenu(
                                      onChanged: () => refreshSheet(() {}),
                                    ),
                                child: const Text(
                                  '\uC124\uC815',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: setSearchController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText:
                                '\uC138\uD2B8\uBA85, \uAC00\uC218\uBA85, \uACE1\uBA85 \uAC80\uC0C9',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => refreshSheet(() {}),
                        ),
                        if (_songSets.length >= maxSongSetCount) ...[
                          const SizedBox(height: 6),
                          Text(
                            '\uC138\uD2B8\uB294 \uCD5C\uB300 $maxSongSetCount\uAC1C\uAE4C\uC9C0 \uC800\uC7A5\uD560 \uC218 \uC788\uC5B4\uC694.',
                            style: TextStyle(
                              color: tdmTextSub,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),
                        _buildSongSetStorageTab(
                          searchQuery: setSearchController.text,
                          notice: setStorageNotice,
                          onChanged: () {
                            refreshSheet(() {
                              if (_randomMode == RandomMode.songSets &&
                                  _selectedSongSetIds.isNotEmpty) {
                                setStorageNotice = null;
                              }
                            });
                          },
                          onReturnedToArtistRandom: () {
                            refreshSheet(() {
                              setStorageNotice =
                                  '\uAC00\uC218 \uB79C\uB364\uC73C\uB85C \uBCC0\uACBD\uD588\uC5B4\uC694.';
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _disposeTextControllerAfterRoute(setSearchController);
    });
  }

  void _showSongSetStorageSettingsMenu({VoidCallback? onChanged}) {
    showDialog<void>(
      context: context,
      builder: (menuContext) {
        return AlertDialog(
          title: const Text('세트저장소 설정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() {
                    _importSongSets(onImported: onChanged);
                  });
                },
                child: const Text('\uC138\uD2B8 \uBD88\uB7EC\uC624\uAE30'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _songSets.isEmpty
                    ? null
                    : () {
                        Navigator.of(menuContext).pop();
                        _runAfterFrame(_exportAllSongSets);
                      },
                child: const Text('전체 세트 내보내기'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _songSets.isEmpty
                    ? null
                    : () {
                        Navigator.of(menuContext).pop();
                        _runAfterFrame(() {
                          _showDeleteAllSongSetsDialog(onDeleted: onChanged);
                        });
                      },
                child: const Text('전체 세트 삭제'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(menuContext).pop(),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteAllSongSetsDialog({VoidCallback? onDeleted}) {
    if (_songSets.isEmpty) {
      _showRootSnackBar('삭제할 세트가 없어요.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (deleteContext) {
        return AlertDialog(
          title: const Text('전체 세트를 삭제할까요?'),
          content: const Text('원본 노래 저장소의 곡은 삭제되지 않아요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(deleteContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _songSets.clear();
                  _selectedSongSetIds = [];
                  _randomMode = RandomMode.artistRandom;
                  _resultSongSetName = null;
                });
                _saveSongSets();
                _saveRandomSelection();
                Navigator.of(deleteContext).pop();
                _runAfterFrame(() {
                  onDeleted?.call();
                  _showRootSnackBar('전체 세트를 삭제했어요.');
                });
              },
              child: const Text('전체 삭제'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSongSetStorageTab({
    String searchQuery = '',
    String? notice,
    VoidCallback? onChanged,
    VoidCallback? onReturnedToArtistRandom,
  }) {
    final normalizedQuery = searchQuery.trim().toLowerCase();

    if (_songSets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text(
          '아직 만든 세트가 없어요.\n전체보기에서 곡을 선택해 세트를 만들어보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: tdmTextSub, fontWeight: FontWeight.w600),
        ),
      );
    }

    final visibleSongSets = normalizedQuery.isEmpty
        ? List<SongSet>.of(_songSets)
        : _songSets
              .where(
                (songSet) => _matchesSongSetSearch(songSet, normalizedQuery),
              )
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null && notice.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: tdmCardBackground,
              borderRadius: BorderRadius.circular(8),
              border: const Border.fromBorderSide(BorderSide(color: tdmBorder)),
            ),
            child: Text(
              notice.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: tdmTextSub,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (visibleSongSets.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text(
              '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC5B4\uC694.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tdmTextSub, fontWeight: FontWeight.w600),
            ),
          )
        else
          ...visibleSongSets.map(
            (songSet) => SongSetTile(
              songSet: songSet,
              searchMatchSummary: _songSetSearchMatchSummary(
                songSet,
                normalizedQuery,
              ),
              isSelectedForRandom: _selectedSongSetIds.contains(songSet.id),
              onRandomToggle: (selected) => _toggleSongSetRandomSelection(
                songSet,
                selected: selected,
                onChanged: onChanged,
                onReturnedToArtistRandom: onReturnedToArtistRandom,
              ),
              onTap: () =>
                  _showSongSetDetailDialog(songSet.id, onChanged: onChanged),
            ),
          ),
      ],
    );
  }

  bool _matchesSongSetSearch(SongSet songSet, String normalizedQuery) {
    if (normalizedQuery.isEmpty) {
      return true;
    }
    if (songSet.name.toLowerCase().contains(normalizedQuery)) {
      return true;
    }
    return songSet.songs.any(
      (song) =>
          song.artist.toLowerCase().contains(normalizedQuery) ||
          song.title.toLowerCase().contains(normalizedQuery),
    );
  }

  String? _songSetSearchMatchSummary(SongSet songSet, String normalizedQuery) {
    if (normalizedQuery.isEmpty ||
        songSet.name.toLowerCase().contains(normalizedQuery)) {
      return null;
    }

    final matches = songSet.songs
        .where(
          (song) =>
              song.artist.toLowerCase().contains(normalizedQuery) ||
              song.title.toLowerCase().contains(normalizedQuery),
        )
        .toList();
    if (matches.isEmpty) {
      return null;
    }
    if (matches.length == 1 ||
        matches.first.title.toLowerCase().contains(normalizedQuery)) {
      final first = matches.first;
      return '\uC77C\uCE58: ${first.artist} - ${first.title}';
    }
    return '\uC77C\uCE58\uD558\uB294 \uACE1 ${matches.length}\uAC1C';
  }

  List<SongSet> _songSetsContainingSong(Song song) {
    return _songSets
        .where(
          (songSet) =>
              songSet.songs.any((setSong) => _sameStoredSong(setSong, song)),
        )
        .toList();
  }

  void _showSongIncludedSetsDialog(Song song) {
    final matchingSets = _songSetsContainingSong(song);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            '\uC774 \uACE1\uC774 \uD3EC\uD568\uB41C \uC138\uD2B8',
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.52,
            ),
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${song.artist} - ${song.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: tdmTextMain,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (matchingSets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '\uC774 \uACE1\uC774 \uD3EC\uD568\uB41C \uC138\uD2B8\uAC00 \uC5C6\uC5B4\uC694.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tdmTextSub,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: matchingSets.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 8),
                        itemBuilder: (context, index) {
                          final songSet = matchingSets[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              songSet.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text('${songSet.songs.length}\uACE1'),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              _runAfterFrame(
                                () => _showSongSetDetailDialog(songSet.id),
                              );
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            Center(
              child: OutlinedButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('\uB2EB\uAE30'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _toggleSongSetRandomSelection(
    SongSet songSet, {
    required bool selected,
    VoidCallback? onChanged,
    VoidCallback? onReturnedToArtistRandom,
  }) {
    if (selected) {
      if (_selectedSongSetIds.contains(songSet.id)) {
        return;
      }
      if (_randomMode != RandomMode.songSets || _selectedSongSetIds.isEmpty) {
        showDialog<void>(
          context: context,
          builder: (confirmContext) {
            return AlertDialog(
              title: const Text('\uC138\uD2B8 \uB79C\uB364 \uC0AC\uC6A9'),
              content: const Text(
                '\uC138\uD2B8 \uB79C\uB364\uC744 \uC0AC\uC6A9\uD558\uBA74 \uAC00\uC218\uBCC4 \uB79C\uB364 \uC124\uC815\uC740 \uC7A0\uC2DC \uC801\uC6A9\uB418\uC9C0 \uC54A\uC544\uC694.\n'
                '\uAC00\uC218\uBCC4 \uC124\uC815\uC740 \uC720\uC9C0\uB418\uBA70, \uC138\uD2B8 \uC120\uD0DD\uC744 \uBAA8\uB450 \uD574\uC81C\uD558\uBA74 \uB2E4\uC2DC \uAC00\uC218 \uB79C\uB364\uC73C\uB85C \uB3CC\uC544\uAC00\uC694.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(confirmContext).pop(),
                  child: const Text('\uCDE8\uC18C'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(confirmContext).pop();
                    _runAfterFrame(() {
                      _selectSongSetForRandom(songSet, onChanged: onChanged);
                    });
                  },
                  child: const Text('\uC138\uD2B8 \uB79C\uB364 \uC0AC\uC6A9'),
                ),
              ],
            );
          },
        );
      } else {
        _selectSongSetForRandom(songSet, onChanged: onChanged);
      }
      return;
    }

    _unselectSongSetForRandom(
      songSet,
      onChanged: onChanged,
      onReturnedToArtistRandom: onReturnedToArtistRandom,
    );
  }

  void _selectSongSetForRandom(SongSet songSet, {VoidCallback? onChanged}) {
    setState(() {
      _selectedSongSetIds = [..._selectedSongSetIds, songSet.id];
      _randomMode = RandomMode.songSets;
    });
    _saveRandomSelection();
    onChanged?.call();
  }

  void _unselectSongSetForRandom(
    SongSet songSet, {
    VoidCallback? onChanged,
    VoidCallback? onReturnedToArtistRandom,
  }) {
    if (!_selectedSongSetIds.contains(songSet.id)) {
      return;
    }

    setState(() {
      _selectedSongSetIds = _selectedSongSetIds
          .where((setId) => setId != songSet.id)
          .toList();
      if (_selectedSongSetIds.isEmpty) {
        _randomMode = RandomMode.artistRandom;
      }
    });
    _saveRandomSelection();
    onChanged?.call();
    if (_randomMode == RandomMode.artistRandom) {
      onReturnedToArtistRandom?.call();
      _runAfterFrame(() {
        _showRootSnackBar(
          '\uC120\uD0DD\uB41C \uC138\uD2B8\uAC00 \uC5C6\uC5B4 \uAC00\uC218 \uB79C\uB364\uC73C\uB85C \uBCC0\uACBD\uD588\uC5B4\uC694.',
        );
      });
    }
  }

  void _showSongBackupMenu({VoidCallback? onSongsImported}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (menuContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '목록 백업',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(menuContext).pop();
                    _exportSongs();
                  },
                  child: const Text('내보내기'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(menuContext).pop();
                    _importSongs(onSongsImported: onSongsImported);
                  },
                  child: const Text('불러오기'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(menuContext).pop();
                    _runAfterFrame(_showResetAppDialog);
                  },
                  child: const Text('앱 초기화'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddSongsTabbedDialog({VoidCallback? onSongsAdded}) {
    final pasteController = TextEditingController();
    final pasteScrollController = ScrollController();
    final artistNames = songsByArtist(_songs).keys.toList();
    final titleController = TextEditingController();
    final memoController = TextEditingController();
    final tagsController = TextEditingController();
    final linkController = TextEditingController();
    final imagePicker = ImagePicker();
    const textOcrService = TextOcrService();
    String artistName = '';
    String? artistErrorText;
    String? titleErrorText;
    var isOcrRunning = false;
    String? ocrStatusMessage;
    var isOcrStatusError = false;
    List<String?> ocrTitleAlternatives = const [];

    void logOcrUi(String stage, String details) {
      if (kDebugMode) {
        debugPrint('[TDM OCR UI] $stage $details');
      }
    }

    void disposeControllers() {
      logOcrUi('dialog-dispose', 'pasteLength=${pasteController.text.length}');
      pasteController.dispose();
      pasteScrollController.dispose();
      titleController.dispose();
      memoController.dispose();
      tagsController.dispose();
      linkController.dispose();
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            void submitIndividualSong({bool allowDuplicate = false}) {
              final artist = artistName.trim();
              final title = titleController.text.trim();
              final hasArtist = artist.isNotEmpty;
              final hasTitle = title.isNotEmpty;

              if (!hasArtist || !hasTitle) {
                refreshDialog(() {
                  artistErrorText = hasArtist ? null : '가수명을 입력해 주세요.';
                  titleErrorText = hasTitle ? null : '곡 제목을 입력해 주세요.';
                });
                return;
              }

              final song = Song(
                artist: artist,
                title: title,
                memo: normalizeSongMemo(memoController.text),
                tags: normalizeTagInput(tagsController.text),
                link: linkController.text.trim(),
              );
              final isDuplicate = _songs.any(
                (existingSong) =>
                    existingSong.artist.trim().toLowerCase() ==
                        artist.toLowerCase() &&
                    existingSong.title.trim().toLowerCase() ==
                        title.toLowerCase(),
              );

              if (isDuplicate && !allowDuplicate) {
                showDialog<void>(
                  context: dialogContext,
                  builder: (confirmContext) {
                    return AlertDialog(
                      title: const Text('확인'),
                      content: Text(
                        '이미 같은 제목의 곡이 있어요.\n\n'
                        '${song.artist} - ${song.title}\n\n'
                        '그래도 추가할까요?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(confirmContext).pop(),
                          child: const Text('취소'),
                        ),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(confirmContext).pop();
                            submitIndividualSong(allowDuplicate: true);
                          },
                          child: const Text('추가하기'),
                        ),
                      ],
                    );
                  },
                );
                return;
              }

              _addSong(song);
              onSongsAdded?.call();
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(dialogContext).pop();
            }

            Future<void> searchIndividualSong() async {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                refreshDialog(() {
                  titleErrorText = '곡명을 입력해 주세요.';
                });
                return;
              }
              if (artistName.trim().isEmpty) {
                _showRootSnackBar('가수명을 입력하면 더 정확하게 검색할 수 있어요.');
              }
              await _openYoutubeSearch(
                Song(artist: artistName.trim(), title: title, tags: const []),
              );
            }

            void hideKeyboardAndRevealAnalyzeButton() {
              FocusManager.instance.primaryFocus?.unfocus();
              Future<void>.delayed(const Duration(milliseconds: 260), () {
                if (!mounted) {
                  return;
                }

                if (!pasteScrollController.hasClients) {
                  return;
                }

                pasteScrollController.animateTo(
                  pasteScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              });
            }

            String oppositeOcrText(
              OcrRecognitionResult result,
              OcrRecognitionMode source,
            ) {
              final oppositeSource = source == OcrRecognitionMode.korean
                  ? OcrRecognitionMode.japanese
                  : OcrRecognitionMode.korean;
              return result.textForSource(oppositeSource).trim();
            }

            void applyOcrText(
              OcrRecognitionResult result,
              OcrRecognitionMode source,
            ) {
              final text = result.textForSource(source).trim();
              logOcrUi(
                'controller-apply-start',
                'source=${source.name} rawLength=${text.length} '
                    'beforeLength=${pasteController.text.length} '
                    'dialogMounted=${dialogContext.mounted}',
              );
              pasteController.text = text;
              pasteController.selection = TextSelection.collapsed(
                offset: pasteController.text.length,
              );
              ocrTitleAlternatives = buildOcrTitleAlternatives(
                primaryText: text,
                alternateText: oppositeOcrText(result, source),
              );
              logOcrUi(
                'controller-apply-complete',
                'controllerLength=${pasteController.text.length}',
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                logOcrUi(
                  'controller-post-frame',
                  'controllerLength=${pasteController.text.length} '
                      'dialogMounted=${dialogContext.mounted}',
                );
              });
            }

            Future<bool> confirmReplacingText(String message) async {
              final shouldReplace = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) {
                  return AlertDialog(
                    content: Text(message),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(confirmContext).pop(false),
                        child: const Text('\uCDE8\uC18C'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(confirmContext).pop(true),
                        child: const Text('\uBC14\uAFB8\uAE30'),
                      ),
                    ],
                  );
                },
              );
              return shouldReplace == true;
            }

            OcrRecognitionMode sourceForPreferredResult(
              OcrRecognitionResult result,
              OcrRecognitionMode preferredSource,
            ) {
              final preferredText = result
                  .textForSource(preferredSource)
                  .trim();
              if (preferredText.isNotEmpty) {
                return preferredSource;
              }
              final fallbackSource =
                  preferredSource == OcrRecognitionMode.korean
                  ? OcrRecognitionMode.japanese
                  : OcrRecognitionMode.korean;
              return result.textForSource(fallbackSource).trim().isNotEmpty
                  ? fallbackSource
                  : preferredSource;
            }

            Future<void> importTextFromImage(
              OcrRecognitionMode preferredSource,
            ) async {
              if (isOcrRunning) {
                return;
              }

              if (!textOcrService.isSupported) {
                _showRootSnackBar(
                  '\uC774\uBBF8\uC9C0 \uAE00\uC790 \uC778\uC2DD\uC740 \uD604\uC7AC Android \uC571\uC5D0\uC11C\uB9CC \uC9C0\uC6D0\uD569\uB2C8\uB2E4.',
                );
                return;
              }

              refreshDialog(() {
                isOcrRunning = true;
                ocrStatusMessage = '이미지를 불러오고 있습니다.';
                isOcrStatusError = false;
              });
              logOcrUi(
                'picker-start',
                'dialogMounted=${dialogContext.mounted}',
              );

              try {
                final selectedImage = await imagePicker.pickImage(
                  source: ImageSource.gallery,
                );
                if (selectedImage == null) {
                  logOcrUi('picker-cancelled', 'selected=false');
                  if (dialogContext.mounted) {
                    refreshDialog(() {
                      ocrStatusMessage = null;
                    });
                  }
                  return;
                }
                logOcrUi(
                  'picker-complete',
                  'selected=true pathPresent=${selectedImage.path.isNotEmpty} '
                      'dialogMounted=${dialogContext.mounted}',
                );

                logOcrUi('recognition-start', 'mode=auto');
                final recognition = await textOcrService.recognizeText(
                  selectedImage.path,
                  mode: OcrRecognitionMode.auto,
                );
                logOcrUi(
                  'recognition-complete',
                  'koreanLength=${recognition.koreanText.length} '
                      'japaneseLength=${recognition.japaneseText.length} '
                      'selectedLength=${recognition.selectedText.length}',
                );
                final sourceToUse = sourceForPreferredResult(
                  recognition,
                  preferredSource,
                );
                if (recognition.textForSource(sourceToUse).trim().isEmpty) {
                  logOcrUi('recognition-empty', 'source=${sourceToUse.name}');
                  if (dialogContext.mounted) {
                    refreshDialog(() {
                      ocrStatusMessage =
                          '이미지에서 글자를 인식하지 못했습니다. 다른 이미지로 다시 시도해 주세요.';
                      isOcrStatusError = true;
                    });
                  }
                  _showRootSnackBar(
                    '\uC774\uBBF8\uC9C0\uC5D0\uC11C \uAE00\uC790\uB97C \uCC3E\uC9C0 \uBABB\uD588\uC5B4\uC694.',
                  );
                  return;
                }

                if (!dialogContext.mounted) {
                  logOcrUi(
                    'controller-apply-skipped',
                    'reason=dialog-unmounted',
                  );
                  return;
                }

                if (pasteController.text.trim().isNotEmpty) {
                  final shouldReplace = await confirmReplacingText(
                    '\uC785\uB825 \uC911\uC778 \uB0B4\uC6A9\uC744 \uC774\uBBF8\uC9C0\uC5D0\uC11C \uC77D\uC740 \uD14D\uC2A4\uD2B8\uB85C \uBC14\uAFC0\uAE4C\uC694?',
                  );
                  if (!shouldReplace) {
                    return;
                  }
                }

                if (!dialogContext.mounted) {
                  logOcrUi(
                    'controller-apply-skipped',
                    'reason=dialog-unmounted-after-confirm',
                  );
                  return;
                }

                logOcrUi('dialog-refresh-start', 'source=${sourceToUse.name}');
                refreshDialog(() {
                  applyOcrText(recognition, sourceToUse);
                  ocrStatusMessage =
                      '글자 ${pasteController.text.length}자를 인식했습니다.';
                  isOcrStatusError = false;
                });
                logOcrUi(
                  'dialog-refresh-complete',
                  'controllerLength=${pasteController.text.length}',
                );

                hideKeyboardAndRevealAnalyzeButton();
              } on OcrImageLoadException {
                logOcrUi('image-load-error', 'selected-image-unavailable');
                if (dialogContext.mounted) {
                  refreshDialog(() {
                    ocrStatusMessage = '이미지를 불러오지 못했습니다. 다른 이미지로 다시 시도해 주세요.';
                    isOcrStatusError = true;
                  });
                }
              } on OcrUnsupportedException {
                logOcrUi(
                  'unsupported',
                  'platform=${defaultTargetPlatform.name}',
                );
                _showRootSnackBar(
                  '\uC774\uBBF8\uC9C0 \uAE00\uC790 \uC778\uC2DD\uC740 \uD604\uC7AC Android \uC571\uC5D0\uC11C\uB9CC \uC9C0\uC6D0\uD569\uB2C8\uB2E4.',
                );
              } catch (error, stackTrace) {
                logOcrUi(
                  'error',
                  'type=${error.runtimeType} error=$error\n$stackTrace',
                );
                if (dialogContext.mounted) {
                  refreshDialog(() {
                    ocrStatusMessage =
                        '이미지 글자 인식 중 오류가 발생했습니다. 다른 이미지로 다시 시도해 주세요.';
                    isOcrStatusError = true;
                  });
                }
                _showRootSnackBar(
                  '\uC774\uBBF8\uC9C0\uB97C \uC77D\uB294 \uC911 \uBB38\uC81C\uAC00 \uBC1C\uC0DD\uD588\uC5B4\uC694.',
                );
              } finally {
                logOcrUi(
                  'complete',
                  'dialogMounted=${dialogContext.mounted} '
                      'controllerLength=${pasteController.text.length}',
                );
                if (dialogContext.mounted) {
                  refreshDialog(() {
                    isOcrRunning = false;
                  });
                } else {
                  isOcrRunning = false;
                }
              }
            }

            final dialogMedia = MediaQuery.of(dialogContext);
            final availableDialogHeight =
                dialogMedia.size.height - dialogMedia.viewInsets.bottom - 48;
            final maxDialogHeight = min(
              max(200.0, availableDialogHeight - 180),
              520.0,
            );

            final initialTabIndex = _lastAddSongTab == AddSongTab.paste ? 1 : 0;

            return DefaultTabController(
              length: 2,
              initialIndex: initialTabIndex,
              child: AlertDialog(
                title: const Text('\uACE1 \uCD94\uAC00'),
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                content: SizedBox(
                  width: min(
                    MediaQuery.sizeOf(dialogContext).width - 64,
                    560,
                  ).toDouble(),
                  height: maxDialogHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TabBar(
                        onTap: (index) {
                          final tab = index == 1
                              ? AddSongTab.paste
                              : AddSongTab.individual;
                          _lastAddSongTab = tab;
                          SongStorage.saveLastAddSongTab(tab);
                        },
                        tabs: [
                          Tab(text: '\uAC1C\uBCC4 \uACE1 \uCD94\uAC00'),
                          Tab(text: '\uBD99\uC5EC\uB123\uAE30'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            SingleChildScrollView(
                              child: Column(
                                children: [
                                  ArtistAutocompleteField(
                                    artistNames: artistNames,
                                    initialValue: artistName,
                                    errorText: artistErrorText,
                                    onChanged: (artist) {
                                      artistName = artist;
                                      if (artistErrorText != null &&
                                          artist.trim().isNotEmpty) {
                                        refreshDialog(() {
                                          artistErrorText = null;
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: titleController,
                                    onChanged: (title) {
                                      if (titleErrorText != null &&
                                          title.trim().isNotEmpty) {
                                        refreshDialog(() {
                                          titleErrorText = null;
                                        });
                                      }
                                    },
                                    decoration: InputDecoration(
                                      label: const RequiredInputLabel(
                                        text: '\uACE1\uBA85',
                                      ),
                                      border: const OutlineInputBorder(),
                                      errorText: titleErrorText,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: memoController,
                                    maxLines: 3,
                                    maxLength: maxSongMemoLength,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(
                                        maxSongMemoLength,
                                      ),
                                    ],
                                    onChanged: (_) => refreshDialog(() {}),
                                    decoration: InputDecoration(
                                      labelText: '\uBA54\uBAA8',
                                      border: const OutlineInputBorder(),
                                      counterText:
                                          '${memoController.text.characters.length}/$maxSongMemoLength자',
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  HashTagTextField(controller: tagsController),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: linkController,
                                    keyboardType: TextInputType.url,
                                    decoration: InputDecoration(
                                      labelText: '\uB9C1\uD06C',
                                      border: const OutlineInputBorder(),
                                      suffixIcon: IconButton(
                                        key: const ValueKey(
                                          'add-song-youtube-search',
                                        ),
                                        tooltip: '유튜브 검색',
                                        onPressed: searchIndividualSong,
                                        icon: const Icon(Icons.search),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: submitIndividualSong,
                                      child: const Text(
                                        '\uCD94\uAC00\uD558\uAE30',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SingleChildScrollView(
                              controller: pasteScrollController,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    '\uBCF5\uC0AC\uD55C \uACE1 \uBAA9\uB85D\uC744 \uBD99\uC5EC\uB123\uC73C\uBA74 \uAC00\uC218/\uACE1\uBA85\uC744 \uC790\uB3D9\uC73C\uB85C \uCD94\uC815\uD569\uB2C8\uB2E4.',
                                    style: TextStyle(
                                      color: tdmTextSub,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    key: const ValueKey('paste-song-input'),
                                    controller: pasteController,
                                    minLines: 3,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.done,
                                    onEditingComplete:
                                        hideKeyboardAndRevealAnalyzeButton,
                                    keyboardType: TextInputType.multiline,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      hintText:
                                          '\uC608\uC2DC)\nN.Flying - \uD658\uC808\uAE30\n1. Blue Moon',
                                      hintStyle: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.48),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (shouldShowImageRecognitionControls(
                                    isWeb: kIsWeb,
                                    isSupported: textOcrService.isSupported,
                                  )) ...[
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        OutlinedButton.icon(
                                          key: const ValueKey(
                                            'image-recognition-button',
                                          ),
                                          onPressed: isOcrRunning
                                              ? null
                                              : () => importTextFromImage(
                                                  OcrRecognitionMode.korean,
                                                ),
                                          icon: isOcrRunning
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.image_search_outlined,
                                                ),
                                          label: Text(
                                            isOcrRunning
                                                ? '\uC774\uBBF8\uC9C0\uC5D0\uC11C \uAE00\uC790\uB97C \uC77D\uB294 \uC911\uC774\uC5D0\uC694.'
                                                : '\uC774\uBBF8\uC9C0\uC5D0\uC11C \uBD88\uB7EC\uC624\uAE30',
                                          ),
                                        ),
                                        const HelpIconButton(
                                          key: ValueKey(
                                            'image-recognition-help',
                                          ),
                                          title:
                                              '\uC774\uBBF8\uC9C0\uC5D0\uC11C \uACE1 \uBD88\uB7EC\uC624\uAE30',
                                          message: imageRecognitionHelpMessage,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (ocrStatusMessage != null) ...[
                                      Text(
                                        ocrStatusMessage!,
                                        key: const ValueKey(
                                          'image-recognition-status',
                                        ),
                                        style: TextStyle(
                                          color: isOcrStatusError
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.error
                                              : tdmTextSub,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                  OutlinedButton(
                                    onPressed: () {
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      final analysis = parsePastedSongText(
                                        text: pasteController.text,
                                        existingSongs: _songs,
                                        knownSongs: sampleSongs,
                                      );
                                      _showPasteSongAnalysisDialog(
                                        analysis,
                                        titleAlternatives: ocrTitleAlternatives,
                                        onSongsAdded: () {
                                          onSongsAdded?.call();
                                          pasteController.clear();
                                        },
                                      );
                                    },
                                    child: const Text(
                                      '\uBD84\uC11D\uD558\uAE30',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: OutlinedButton(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.of(dialogContext).pop();
                          },
                          child: const Text('\uB2EB\uAE30'),
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
    ).whenComplete(() {
      _runAfterRouteSettled(disposeControllers);
    });
  }

  void _showPasteSongAnalysisDialog(
    PasteSongAnalysis analysis, {
    List<String?> titleAlternatives = const [],
    VoidCallback? onSongsAdded,
    String dialogTitle = '분석 결과',
  }) {
    final inferredArtistController = TextEditingController(
      text: analysis.inferredArtist,
    );
    final drafts = analysis.drafts.toList();
    final excludedIndexes = <int>{};
    final selectedUpdateIndexes = <int>{};
    var showIdenticalCandidates = false;

    showDialog<void>(
      context: context,
      builder: (analysisContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final candidates = buildPasteSongCandidates(
              drafts: drafts,
              inferredArtist: inferredArtistController.text,
              existingSongs: _songs,
            );
            final newSongCount = candidates
                .where(
                  (candidate) =>
                      candidate.status == PasteSongCandidateStatus.newSong,
                )
                .length;
            final existingCount = candidates
                .where(
                  (candidate) =>
                      candidate.status == PasteSongCandidateStatus.existing,
                )
                .length;
            final updateAvailableCount = candidates
                .where(
                  (candidate) =>
                      candidate.status ==
                      PasteSongCandidateStatus.updateAvailable,
                )
                .length;
            final updateAvailableIndexes = candidates
                .asMap()
                .entries
                .where(
                  (entry) =>
                      entry.value.status ==
                      PasteSongCandidateStatus.updateAvailable,
                )
                .map((entry) => entry.key)
                .toSet();
            selectedUpdateIndexes.removeWhere(
              (index) => !updateAvailableIndexes.contains(index),
            );
            final selectedUpdateCount = selectedUpdateIndexes.length;
            final needsReviewCount = candidates
                .where(
                  (candidate) =>
                      candidate.status == PasteSongCandidateStatus.needsReview,
                )
                .length;
            final hasUnconfirmedArtist =
                inferredArtistController.text.trim().isEmpty &&
                candidates.any((candidate) => candidate.song == null);
            final selectedCandidateCount = candidates.asMap().entries.where((
              entry,
            ) {
              if (entry.value.status == PasteSongCandidateStatus.newSong) {
                return !excludedIndexes.contains(entry.key);
              }
              if (entry.value.status ==
                  PasteSongCandidateStatus.updateAvailable) {
                return selectedUpdateIndexes.contains(entry.key);
              }
              return false;
            }).length;
            String currentCandidateTitle(
              int index,
              PasteSongCandidate candidate,
            ) {
              final draft = drafts[index];
              return (candidate.song?.title ??
                      draft.title ??
                      candidate.sourceLine)
                  .trim();
            }

            void applyCandidateTitleEdit(
              int index,
              PasteSongCandidate candidate,
              String title,
            ) {
              final draft = drafts[index];
              final hasOwnArtist = (draft.artist ?? '').trim().isNotEmpty;
              drafts[index] = PasteSongDraft(
                sourceLine: draft.sourceLine,
                artist: draft.artist ?? candidate.song?.artist,
                title: title.trim(),
                tags: draft.tags,
                memo: draft.memo,
                link: draft.link,
                usesInferredArtist:
                    draft.usesInferredArtist ||
                    (!hasOwnArtist &&
                        inferredArtistController.text.trim().isNotEmpty),
                needsReview: false,
              );
            }

            Future<String?> showDirectTitleEditDialog(
              int index,
              PasteSongCandidate candidate,
            ) async {
              final controller = TextEditingController(
                text: currentCandidateTitle(index, candidate),
              );
              String? errorText;

              final editedTitle = await showDialog<String>(
                context: analysisContext,
                builder: (editContext) {
                  return StatefulBuilder(
                    builder: (context, refreshEditDialog) {
                      return AlertDialog(
                        title: const Text(
                          '\uACE1\uBA85 \uC9C1\uC811 \uC218\uC815',
                        ),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: '\uACE1\uBA85',
                            border: const OutlineInputBorder(),
                            errorText: errorText,
                          ),
                          onSubmitted: (_) {
                            final value = controller.text.trim();
                            if (value.isEmpty) {
                              refreshEditDialog(() {
                                errorText =
                                    '\uACE1\uBA85\uC744 \uC785\uB825\uD574 \uC8FC\uC138\uC694.';
                              });
                              return;
                            }
                            Navigator.of(editContext).pop(value);
                          },
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(editContext).pop(),
                            child: const Text('\uCDE8\uC18C'),
                          ),
                          FilledButton(
                            onPressed: () {
                              final value = controller.text.trim();
                              if (value.isEmpty) {
                                refreshEditDialog(() {
                                  errorText =
                                      '\uACE1\uBA85\uC744 \uC785\uB825\uD574 \uC8FC\uC138\uC694.';
                                });
                                return;
                              }
                              Navigator.of(editContext).pop(value);
                            },
                            child: const Text('\uC218\uC815'),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
              _disposeTextControllerAfterRoute(controller);
              return editedTitle;
            }

            Future<void> editCandidateTitle(
              int index,
              PasteSongCandidate candidate,
            ) async {
              final editedTitle = await showDirectTitleEditDialog(
                index,
                candidate,
              );
              if (editedTitle == null || editedTitle.trim().isEmpty) {
                return;
              }

              refreshDialog(() {
                applyCandidateTitleEdit(index, candidate, editedTitle);
              });
            }

            Future<bool> confirmSelectedUpdates() async {
              if (selectedUpdateCount == 0) {
                return true;
              }
              final shouldContinue = await showDialog<bool>(
                context: analysisContext,
                builder: (confirmContext) {
                  return AlertDialog(
                    title: const Text('곡 정보 갱신'),
                    content: Text(
                      '선택한 $selectedUpdateCount곡의 정보를 갱신합니다.\n\n'
                      '새 데이터의 빈 값은 기존 값을 유지합니다.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(confirmContext).pop(false),
                        child: const Text('취소'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(confirmContext).pop(true),
                        child: const Text('갱신'),
                      ),
                    ],
                  );
                },
              );
              return shouldContinue == true;
            }

            Future<void> showUpdateDetails(PasteSongCandidate candidate) async {
              final song = candidate.song;
              final existingSong = candidate.existingSong;
              final mergedSong = candidate.mergedSong;
              if (song == null || existingSong == null || mergedSong == null) {
                return;
              }

              String displayValue(String value) {
                final trimmed = value.trim();
                return trimmed.isEmpty ? '-' : trimmed;
              }

              Widget comparisonSection({
                required String label,
                required String before,
                required String after,
                required bool changed,
              }) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: tdmTextMain,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '기존: ${displayValue(before)}',
                        style: const TextStyle(color: tdmTextSub, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        changed ? '갱신: ${displayValue(after)}' : '갱신: 기존 유지',
                        style: TextStyle(
                          color: changed ? updateAvailableColor : tdmTextSub,
                          fontSize: 13,
                          fontWeight: changed
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final changedFields = candidate.changes
                  .map((change) => change.field)
                  .toSet();
              await showDialog<void>(
                context: analysisContext,
                builder: (detailContext) {
                  return AlertDialog(
                    key: const ValueKey('import-update-detail-card'),
                    title: Text('${song.artist} - ${song.title}'),
                    content: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            comparisonSection(
                              label: '메모',
                              before: existingSong.memo,
                              after: mergedSong.memo,
                              changed: changedFields.contains('메모'),
                            ),
                            comparisonSection(
                              label: '태그',
                              before: existingSong.tags.join(' '),
                              after: mergedSong.tags.join(' '),
                              changed: changedFields.contains('태그'),
                            ),
                            comparisonSection(
                              label: '링크',
                              before: existingSong.link,
                              after: mergedSong.link,
                              changed: changedFields.contains('링크'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(detailContext).pop(),
                        child: const Text('닫기'),
                      ),
                    ],
                  );
                },
              );
            }

            final dialogMedia = MediaQuery.of(analysisContext);
            final maxDialogHeight = max(
              320.0,
              dialogMedia.size.height - dialogMedia.viewInsets.bottom - 120,
            );

            return AlertDialog(
              title: Text(dialogTitle),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              buttonPadding: EdgeInsets.zero,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              content: SizedBox(
                width: min(MediaQuery.sizeOf(analysisContext).width - 64, 560),
                height: min(maxDialogHeight, 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('inferred-artist-input'),
                      controller: inferredArtistController,
                      decoration: InputDecoration(
                        labelText: '\uCD94\uC815 \uAC00\uC218\uBA85',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: hasUnconfirmedArtist
                            ? '가수명을 확인하지 못한 곡이 있습니다. 저장하기 전에 가수명을 입력하거나 수정해 주세요.'
                            : null,
                      ),
                      onChanged: (_) => refreshDialog(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\uC0C8 \uACE1 $newSongCount\uACE1 \u00B7 '
                      '\uD655\uC778 \uD544\uC694 $needsReviewCount\uACE1',
                      style: const TextStyle(
                        color: tdmTextSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (updateAvailableCount > 0) ...[
                      InkWell(
                        key: const ValueKey('update-selection-controls'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          refreshDialog(() {
                            if (selectedUpdateCount == updateAvailableCount) {
                              selectedUpdateIndexes.clear();
                            } else {
                              selectedUpdateIndexes
                                ..clear()
                                ..addAll(updateAvailableIndexes);
                            }
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              key: const ValueKey('select-all-updates'),
                              tristate: true,
                              value: selectedUpdateCount == 0
                                  ? false
                                  : selectedUpdateCount == updateAvailableCount
                                  ? true
                                  : null,
                              onChanged: (_) {
                                refreshDialog(() {
                                  if (selectedUpdateCount ==
                                      updateAvailableCount) {
                                    selectedUpdateIndexes.clear();
                                  } else {
                                    selectedUpdateIndexes
                                      ..clear()
                                      ..addAll(updateAvailableIndexes);
                                  }
                                });
                              },
                              visualDensity: VisualDensity.compact,
                            ),
                            Text(
                              '갱신 가능 '
                              '$selectedUpdateCount/$updateAvailableCount',
                              key: const ValueKey('update-selection-count'),
                              style: const TextStyle(
                                color: tdmTextMain,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (needsReviewCount > 0) ...[
                      const Text(
                        '확인이 필요한 곡이 있어요.',
                        style: TextStyle(
                          color: tdmTextSub,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    const Text(
                      '\uACE1\uBA85\uC774\uB098 \uC5F0\uD544 \uC544\uC774\uCF58\uC744 \uB204\uB974\uBA74 \uC218\uC815\uD560 \uC218 \uC788\uC5B4\uC694.',
                      style: TextStyle(
                        color: tdmTextSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: candidates.isEmpty
                          ? const Center(
                              child: Text(
                                '\uCD94\uAC00\uD560 \uC218 \uC788\uB294 \uD6C4\uBCF4\uAC00 \uC5C6\uC5B4\uC694.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                final primaryEntries = candidates
                                    .asMap()
                                    .entries
                                    .where(
                                      (entry) =>
                                          entry.value.status !=
                                          PasteSongCandidateStatus.existing,
                                    )
                                    .toList();
                                int priority(PasteSongCandidate candidate) {
                                  return switch (candidate.status) {
                                    PasteSongCandidateStatus.newSong => 0,
                                    PasteSongCandidateStatus.updateAvailable =>
                                      1,
                                    PasteSongCandidateStatus.needsReview => 2,
                                    PasteSongCandidateStatus.existing => 3,
                                  };
                                }

                                primaryEntries.sort(
                                  (left, right) => priority(
                                    left.value,
                                  ).compareTo(priority(right.value)),
                                );
                                final identicalEntries = candidates
                                    .asMap()
                                    .entries
                                    .where(
                                      (entry) =>
                                          entry.value.status ==
                                          PasteSongCandidateStatus.existing,
                                    )
                                    .toList();
                                final visibleEntries = [
                                  ...primaryEntries,
                                  if (showIdenticalCandidates)
                                    ...identicalEntries,
                                ];

                                return ListView.separated(
                                  itemCount:
                                      visibleEntries.length +
                                      (identicalEntries.isEmpty ? 0 : 1),
                                  separatorBuilder: (context, index) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    if (index == primaryEntries.length &&
                                        identicalEntries.isNotEmpty) {
                                      return ListTile(
                                        key: const ValueKey(
                                          'identical-candidates-toggle',
                                        ),
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          '동일함 ${identicalEntries.length}곡',
                                          style: const TextStyle(
                                            color: tdmTextSub,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        trailing: TextButton(
                                          onPressed: () {
                                            refreshDialog(() {
                                              showIdenticalCandidates =
                                                  !showIdenticalCandidates;
                                            });
                                          },
                                          child: Text(
                                            showIdenticalCandidates
                                                ? '접기'
                                                : '열기',
                                          ),
                                        ),
                                        onTap: () {
                                          refreshDialog(() {
                                            showIdenticalCandidates =
                                                !showIdenticalCandidates;
                                          });
                                        },
                                      );
                                    }

                                    final adjustedIndex =
                                        identicalEntries.isNotEmpty &&
                                            index > primaryEntries.length
                                        ? index - 1
                                        : index;
                                    final entry = visibleEntries[adjustedIndex];
                                    final candidateIndex = entry.key;
                                    final candidate = entry.value;
                                    final song = candidate.song;
                                    final canInclude =
                                        candidate.status ==
                                            PasteSongCandidateStatus.newSong ||
                                        candidate.status ==
                                            PasteSongCandidateStatus
                                                .updateAvailable;
                                    final isIncluded =
                                        switch (candidate.status) {
                                          PasteSongCandidateStatus.newSong =>
                                            !excludedIndexes.contains(
                                              candidateIndex,
                                            ),
                                          PasteSongCandidateStatus
                                              .updateAvailable =>
                                            selectedUpdateIndexes.contains(
                                              candidateIndex,
                                            ),
                                          _ => false,
                                        };
                                    final colorScheme = Theme.of(
                                      context,
                                    ).colorScheme;

                                    return ListTile(
                                      key: ValueKey(
                                        'paste-result-${candidate.sourceLine}-$candidateIndex-${song?.artist ?? ''}-${song?.title ?? ''}-${candidate.status.name}',
                                      ),
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      onTap:
                                          candidate.status ==
                                              PasteSongCandidateStatus
                                                  .updateAvailable
                                          ? () => showUpdateDetails(candidate)
                                          : () => editCandidateTitle(
                                              candidateIndex,
                                              candidate,
                                            ),
                                      leading: Checkbox(
                                        value: isIncluded,
                                        onChanged: canInclude
                                            ? (value) {
                                                refreshDialog(() {
                                                  if (value ?? false) {
                                                    if (candidate.status ==
                                                        PasteSongCandidateStatus
                                                            .newSong) {
                                                      excludedIndexes.remove(
                                                        candidateIndex,
                                                      );
                                                    } else {
                                                      selectedUpdateIndexes.add(
                                                        candidateIndex,
                                                      );
                                                    }
                                                  } else {
                                                    if (candidate.status ==
                                                        PasteSongCandidateStatus
                                                            .newSong) {
                                                      excludedIndexes.add(
                                                        candidateIndex,
                                                      );
                                                    } else {
                                                      selectedUpdateIndexes
                                                          .remove(
                                                            candidateIndex,
                                                          );
                                                    }
                                                  }
                                                });
                                              }
                                            : null,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      title: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          song == null
                                              ? candidate.sourceLine
                                              : '${song.artist} - ${song.title}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      subtitle:
                                          candidate.status ==
                                              PasteSongCandidateStatus
                                                  .updateAvailable
                                          ? Text(
                                              '갱신 가능 정보 : '
                                              '${candidate.changes.map((change) => change.field).join(', ')}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: tdmTextSub,
                                                fontSize: 11,
                                              ),
                                            )
                                          : candidate.changes.isEmpty
                                          ? candidate.status ==
                                                    PasteSongCandidateStatus
                                                        .existing
                                                ? const Text(
                                                    '변경 없음',
                                                    style: TextStyle(
                                                      color: tdmTextSub,
                                                      fontSize: 11,
                                                    ),
                                                  )
                                                : null
                                          : null,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip:
                                                '\uACE1\uBA85 \uC218\uC815',
                                            onPressed: () => editCandidateTitle(
                                              candidateIndex,
                                              candidate,
                                            ),
                                            icon: Icon(
                                              Icons.edit_outlined,
                                              size: 16,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            candidate.statusLabel,
                                            style: TextStyle(
                                              color: _pasteStatusColor(
                                                candidate.status,
                                                colorScheme,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selectedCandidateCount == 0
                            ? null
                            : () async {
                                if (!await confirmSelectedUpdates()) {
                                  return;
                                }
                                if (!analysisContext.mounted) {
                                  return;
                                }
                                final selectedCandidates = candidates
                                    .asMap()
                                    .entries
                                    .where((entry) {
                                      if (entry.value.status ==
                                          PasteSongCandidateStatus.newSong) {
                                        return !excludedIndexes.contains(
                                          entry.key,
                                        );
                                      }
                                      if (entry.value.status ==
                                          PasteSongCandidateStatus
                                              .updateAvailable) {
                                        return selectedUpdateIndexes.contains(
                                          entry.key,
                                        );
                                      }
                                      return false;
                                    })
                                    .map((entry) => entry.value)
                                    .toList();
                                final result = _applySelectedSongImports(
                                  selectedCandidates,
                                );
                                if (result.addedCount == 0 &&
                                    result.updatedCount == 0) {
                                  return;
                                }

                                onSongsAdded?.call();
                                FocusManager.instance.primaryFocus?.unfocus();
                                Navigator.of(analysisContext).pop();
                                _runAfterRouteSettled(() {
                                  _showRootSnackBar(
                                    '새 곡 ${result.addedCount}곡 추가, '
                                    '기존 곡 ${result.updatedCount}곡 업데이트, '
                                    '동일한 곡 $existingCount곡 건너뜀',
                                  );
                                });
                              },
                        child: const Text('선택한 항목 저장'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(analysisContext).pop();
                        },
                        child: const Text('\uB2EB\uAE30'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _disposeTextControllerAfterRoute(inferredArtistController);
    });
  }

  Color _pasteStatusColor(
    PasteSongCandidateStatus status,
    ColorScheme colorScheme,
  ) {
    switch (status) {
      case PasteSongCandidateStatus.newSong:
        return colorScheme.primary;
      case PasteSongCandidateStatus.updateAvailable:
        return updateAvailableColor;
      case PasteSongCandidateStatus.existing:
        return colorScheme.onSurfaceVariant;
      case PasteSongCandidateStatus.needsReview:
        return colorScheme.error;
    }
  }

  ({int addedCount, int updatedCount}) _applySelectedSongImports(
    List<PasteSongCandidate> candidates,
  ) {
    var addedCount = 0;
    var updatedCount = 0;
    setState(() {
      for (final candidate in candidates) {
        final incoming = candidate.song;
        if (incoming == null) {
          continue;
        }

        if (candidate.status == PasteSongCandidateStatus.newSong) {
          if (findMatchingSong(incoming, _songs) == null) {
            _songs.add(
              incoming.id.isEmpty
                  ? incoming.copyWith(id: createSongId())
                  : incoming,
            );
            addedCount++;
          }
          continue;
        }

        if (candidate.status != PasteSongCandidateStatus.updateAvailable) {
          continue;
        }

        final matchingSong = findMatchingSong(incoming, _songs);
        if (matchingSong == null) {
          continue;
        }
        final index = _songs.indexWhere(
          (song) => _sameStoredSong(song, matchingSong),
        );
        if (index == -1) {
          continue;
        }

        final originalSong = _songs[index];
        final updatedSong = mergeImportedSong(
          originalSong,
          incoming,
        ).copyWith(id: originalSong.id, isFavorite: originalSong.isFavorite);
        if (updatedSong.link == originalSong.link &&
            updatedSong.memo == originalSong.memo &&
            listEquals(updatedSong.tags, originalSong.tags)) {
          continue;
        }

        _songs[index] = updatedSong;
        _replaceSongInSets(originalSong, updatedSong);
        if (_selectedSong != null &&
            _isSameSongResult(_selectedSong!, originalSong)) {
          _selectedSong = updatedSong;
          _lastResultSong = updatedSong;
          _resetShareText(updatedSong);
        } else if (_lastResultSong != null &&
            _isSameSongResult(_lastResultSong!, originalSong)) {
          _lastResultSong = updatedSong;
        }
        updatedCount++;
      }
      _syncArtistFilterState();
    });

    if (addedCount == 0 && updatedCount == 0) {
      return (addedCount: 0, updatedCount: 0);
    }

    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();
    return (addedCount: addedCount, updatedCount: updatedCount);
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
          onOpenLinkOrSearch: _openSongLinkOrYoutube,
          onSubmit: (updatedSong) {
            _updateSong(song, updatedSong);
            onSongUpdated?.call();
          },
        );
      },
    );
  }

  void _showArtistSongsManagementMenu(
    String artist, {
    required BuildContext artistDialogContext,
    VoidCallback? onSongChanged,
  }) {
    showDialog<void>(
      context: context,
      builder: (menuContext) {
        return AlertDialog(
          title: const Text('\uAD00\uB9AC'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() => _exportArtistSongs(artist));
                },
                child: const Text('\uBAA9\uB85D \uB0B4\uBCF4\uB0B4\uAE30'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() {
                    _showDeleteArtistSongsDialog(
                      artist,
                      onDeleted: () {
                        if (artistDialogContext.mounted) {
                          Navigator.of(artistDialogContext).pop();
                        }
                        onSongChanged?.call();
                      },
                    );
                  });
                },
                child: const Text('\uBAA9\uB85D \uC0AD\uC81C'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(menuContext).pop(),
                child: const Text('\uB2EB\uAE30'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _songListSortDropdown({
    required Key key,
    required SongListSortMode value,
    required ValueChanged<SongListSortMode?> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92, minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tdmCardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tdmBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SongListSortMode>(
          key: key,
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, color: tdmPrimaryDark),
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Colors.white,
          style: const TextStyle(
            color: tdmTextMain,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          items: const [
            DropdownMenuItem(value: SongListSortMode.added, child: Text('등록')),
            DropdownMenuItem(value: SongListSortMode.title, child: Text('이름')),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _showArtistSongsDialog(String artist, {VoidCallback? onSongChanged}) {
    var songSortMode = SongListSortMode.added;
    final searchController = TextEditingController();
    final songListScrollController = ScrollController();
    var isArtistDialogClosed = false;
    var showFavoritesOnly = false;

    void resetSongListScroll() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isArtistDialogClosed || !songListScrollController.hasClients) {
          return;
        }
        songListScrollController.jumpTo(0);
      });
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final allArtistSongs = _songs
                .where((song) => song.artist == artist)
                .toList();
            final normalizedArtistSongQuery = searchController.text
                .trim()
                .toLowerCase();
            final songs = allArtistSongs.where((song) {
              if (showFavoritesOnly && !_isSongFavorite(song)) {
                return false;
              }
              if (normalizedArtistSongQuery.isEmpty) {
                return true;
              }

              final titleMatches = song.title.toLowerCase().contains(
                normalizedArtistSongQuery,
              );
              final memoMatches = song.memo.toLowerCase().contains(
                normalizedArtistSongQuery,
              );
              final tagsMatches = song.tags.any(
                (tag) => tag.toLowerCase().contains(normalizedArtistSongQuery),
              );

              final matches = titleMatches || memoMatches || tagsMatches;
              return matches;
            }).toList();
            if (songSortMode == SongListSortMode.title) {
              songs.sort(
                (a, b) =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
              );
            }
            final availableDialogHeight =
                MediaQuery.sizeOf(dialogContext).height -
                MediaQuery.viewInsetsOf(dialogContext).bottom;
            final contentMaxHeight = max(240.0, availableDialogHeight - 260);
            final artistSongsCanScroll =
                songs.length * 52 > max(0, contentMaxHeight - 136);

            return AlertDialog(
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              buttonPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _showArtistSongsManagementMenu(
                      artist,
                      artistDialogContext: dialogContext,
                      onSongChanged: onSongChanged,
                    ),
                    child: const Text('\uAD00\uB9AC', maxLines: 1),
                  ),
                ],
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: contentMaxHeight),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        normalizedArtistSongQuery.isEmpty
                            ? '\uCD1D ${allArtistSongs.length}\uACE1'
                            : '\uCD1D ${allArtistSongs.length}\uACE1 \u00B7 \uAC80\uC0C9 \uACB0\uACFC ${songs.length}\uACE1',
                        style: const TextStyle(
                          color: tdmTextSub,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText:
                              '\uACE1\uBA85, \uBA54\uBAA8, \uD0DC\uADF8 \uAC80\uC0C9',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.search,
                        onChanged: (_) {
                          refreshDialog(() {});
                          resetSongListScroll();
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: _favoriteFilterToggle(
                              value: showFavoritesOnly,
                              onChanged: (selected) {
                                refreshDialog(() {
                                  showFavoritesOnly = selected;
                                });
                                resetSongListScroll();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Spacer(),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: _songListSortDropdown(
                                key: const ValueKey('artist-song-sort'),
                                value: songSortMode,
                                onChanged: (mode) {
                                  if (mode == null) {
                                    return;
                                  }
                                  refreshDialog(() {
                                    songSortMode = mode;
                                  });
                                  resetSongListScroll();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (songs.isEmpty)
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  showFavoritesOnly &&
                                          normalizedArtistSongQuery.isEmpty
                                      ? '\uC990\uACA8\uCC3E\uAE30\uD55C \uACE1\uC774 \uC5C6\uC5B4\uC694.'
                                      : '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC5B4\uC694.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: tdmTextSub,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: Scrollbar(
                            controller: songListScrollController,
                            thumbVisibility: artistSongsCanScroll,
                            child: ListView.separated(
                              controller: songListScrollController,
                              padding: EdgeInsets.only(
                                right: artistSongsCanScroll ? 8 : 0,
                              ),
                              itemCount: songs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 10),
                              itemBuilder: (context, index) {
                                final song = songs[index];

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        child: _favoriteSongIconButton(
                                          song,
                                          onChanged: () {
                                            if (dialogContext.mounted) {
                                              refreshDialog(() {});
                                            }
                                            onSongChanged?.call();
                                          },
                                        ),
                                      ),
                                      Expanded(
                                        child: InkWell(
                                          key: ValueKey(
                                            'artist-song-card-${_songWidgetKey(song)}',
                                          ),
                                          hoverColor: tdmHoverColor,
                                          splashColor: tdmHoverColor,
                                          highlightColor: Colors.transparent,
                                          onTap: () => _showSongActionCard(
                                            song,
                                            onSongChanged: () {
                                              if (dialogContext.mounted) {
                                                refreshDialog(() {});
                                              }
                                              onSongChanged?.call();
                                            },
                                            onDeleted: () {
                                              if (allArtistSongs.length == 1 &&
                                                  dialogContext.mounted) {
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              } else if (dialogContext
                                                  .mounted) {
                                                refreshDialog(() {});
                                              }
                                              onSongChanged?.call();
                                            },
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
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
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _songRecommendationButton(song),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                Align(
                  alignment: Alignment.center,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('\uB2EB\uAE30', maxLines: 1),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      isArtistDialogClosed = true;
      _disposeTextControllerAfterRoute(searchController);
      songListScrollController.dispose();
    });
  }

  void _showAllSongsDialog({
    VoidCallback? onSongsChanged,
    bool allowDeleteSelectedSongs = true,
  }) {
    final selectedSongs = <Song>{};
    final searchController = TextEditingController();
    final allSongsScrollController = ScrollController();
    var isAllSongsDialogClosed = false;
    var showFavoritesOnly = false;
    var songSortMode = SongListSortMode.added;

    void resetAllSongsScroll() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isAllSongsDialogClosed || !allSongsScrollController.hasClients) {
          return;
        }
        allSongsScrollController.jumpTo(0);
      });
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final songs = List<Song>.of(_songs);
            final query = searchController.text;
            final visibleSongs = songs
                .where(
                  (song) =>
                      (!showFavoritesOnly || _isSongFavorite(song)) &&
                      _matchesSongSearch(song, query),
                )
                .toList();
            if (songSortMode == SongListSortMode.title) {
              visibleSongs.sort(
                (a, b) =>
                    a.title.toLowerCase().compareTo(b.title.toLowerCase()),
              );
            }
            final selectedCount = selectedSongs.length;
            final setLimitReached = _songSets.length >= maxSongSetCount;
            final selectedVisibleSongs = visibleSongs
                .where(selectedSongs.contains)
                .toList();
            final bool? visibleSelectionValue = visibleSongs.isEmpty
                ? false
                : selectedVisibleSongs.length == visibleSongs.length
                ? true
                : selectedVisibleSongs.isEmpty
                ? false
                : null;
            final allSongsContentMaxHeight = max(
              220.0,
              MediaQuery.sizeOf(dialogContext).height -
                  MediaQuery.viewInsetsOf(dialogContext).bottom -
                  190,
            );
            final allSongsCanScroll =
                visibleSongs.length * 58 >
                max(0, allSongsContentMaxHeight - 190);

            return AlertDialog(
              title: const Text('\uC804\uCCB4\uACE1'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: allSongsContentMaxHeight,
                ),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '\uCD1D ${songs.length}\uACE1 \u00B7 \uC120\uD0DD $selectedCount\uACE1',
                      ),
                      if (setLimitReached) ...[
                        const SizedBox(height: 4),
                        Text(
                          '\uC138\uD2B8\uB294 \uCD5C\uB300 $maxSongSetCount\uAC1C\uAE4C\uC9C0 \uC800\uC7A5\uD560 \uC218 \uC788\uC5B4\uC694.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText:
                              '\uAC00\uC218\uBA85, \uACE1\uBA85, \uBA54\uBAA8, \uD0DC\uADF8 \uAC80\uC0C9',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          refreshDialog(() {});
                          resetAllSongsScroll();
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Tooltip(
                              message: visibleSelectionValue == true
                                  ? '\uC804\uCCB4\uC120\uD0DD \uD574\uC81C'
                                  : visibleSelectionValue == null
                                  ? '\uC77C\uBD80 \uC120\uD0DD\uB428'
                                  : '\uC804\uCCB4\uC120\uD0DD',
                              child: Checkbox(
                                tristate: true,
                                value: visibleSelectionValue,
                                onChanged: visibleSongs.isEmpty
                                    ? null
                                    : (checked) {
                                        refreshDialog(() {
                                          if (visibleSelectionValue == true) {
                                            selectedSongs.removeAll(
                                              visibleSongs,
                                            );
                                          } else {
                                            selectedSongs.addAll(visibleSongs);
                                          }
                                        });
                                      },
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: _favoriteFilterToggle(
                              value: showFavoritesOnly,
                              onChanged: (selected) {
                                refreshDialog(() {
                                  showFavoritesOnly = selected;
                                });
                                resetAllSongsScroll();
                              },
                            ),
                          ),
                          const Spacer(),
                          _songListSortDropdown(
                            key: const ValueKey('all-song-sort'),
                            value: songSortMode,
                            onChanged: (mode) {
                              if (mode == null) {
                                return;
                              }
                              refreshDialog(() {
                                songSortMode = mode;
                              });
                              resetAllSongsScroll();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (songs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            '\uC544\uC9C1 \uC800\uC7A5\uB41C \uACE1\uC774 \uC5C6\uC5B4\uC694.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else if (visibleSongs.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            showFavoritesOnly && query.trim().isEmpty
                                ? '\uC990\uACA8\uCC3E\uAE30\uD55C \uACE1\uC774 \uC5C6\uC5B4\uC694.'
                                : '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC5B4\uC694.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Flexible(
                          child: Scrollbar(
                            controller: allSongsScrollController,
                            thumbVisibility: allSongsCanScroll,
                            child: ListView.separated(
                              controller: allSongsScrollController,
                              padding: EdgeInsets.only(
                                right: allSongsCanScroll ? 8 : 0,
                              ),
                              shrinkWrap: true,
                              itemCount: visibleSongs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 8),
                              itemBuilder: (context, index) {
                                final song = visibleSongs[index];
                                final checked = selectedSongs.contains(song);

                                return Padding(
                                  key: ValueKey(
                                    'all-songs-${_songWidgetKey(song)}-$index',
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 48,
                                        child: Checkbox(
                                          value: checked,
                                          onChanged: (value) {
                                            refreshDialog(() {
                                              if (value ?? false) {
                                                selectedSongs.add(song);
                                              } else {
                                                selectedSongs.remove(song);
                                              }
                                            });
                                          },
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 48,
                                        child: _favoriteSongIconButton(
                                          song,
                                          onChanged: () {
                                            refreshDialog(() {});
                                            if (showFavoritesOnly) {
                                              resetAllSongsScroll();
                                            }
                                          },
                                        ),
                                      ),
                                      Expanded(
                                        child: InkWell(
                                          key: ValueKey(
                                            'all-song-card-${_songWidgetKey(song)}',
                                          ),
                                          hoverColor: tdmHoverColor,
                                          splashColor: tdmHoverColor,
                                          highlightColor: Colors.transparent,
                                          onTap: () => _showSongActionCard(
                                            song,
                                            onSongChanged: () {
                                              refreshDialog(() {});
                                              if (showFavoritesOnly) {
                                                resetAllSongsScroll();
                                              }
                                              onSongsChanged?.call();
                                            },
                                            onSongUpdated: () {
                                              selectedSongs.remove(song);
                                              if (dialogContext.mounted) {
                                                refreshDialog(() {});
                                              }
                                              onSongsChanged?.call();
                                            },
                                            onDeleted: () {
                                              selectedSongs.remove(song);
                                              if (dialogContext.mounted) {
                                                refreshDialog(() {});
                                              }
                                              onSongsChanged?.call();
                                            },
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Text(
                                              '${song.artist} - ${song.title}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                      _songRecommendationButton(song),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: selectedSongs.isEmpty
                          ? null
                          : () => _showSelectedSongsPreviewDialog(
                              selectedSongs.toList(),
                              setLimitReached: setLimitReached,
                              allowDeleteSelectedSongs:
                                  allowDeleteSelectedSongs,
                              onSetSaved: () {
                                refreshDialog(selectedSongs.clear);
                                onSongsChanged?.call();
                              },
                              onDeleted: () {
                                refreshDialog(selectedSongs.clear);
                                onSongsChanged?.call();
                              },
                            ),
                      child: const Text(
                        '\uC120\uD0DD\uACE1 \uBCF4\uAE30',
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton(
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(dialogContext).pop();
                        },
                        child: const Text('\uB2EB\uAE30', maxLines: 1),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      isAllSongsDialogClosed = true;
      _disposeTextControllerAfterRoute(searchController);
      allSongsScrollController.dispose();
    });
  }

  List<Song> _allSongsForOverview() {
    final songs = List<Song>.of(_songs);
    songs.sort((a, b) {
      final artistCompare = a.artist.toLowerCase().compareTo(
        b.artist.toLowerCase(),
      );
      if (artistCompare != 0) {
        return artistCompare;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return songs;
  }

  bool _matchesSongSearch(Song song, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    final searchableText = <String>[
      song.artist,
      song.title,
      song.memo,
      ...song.tags,
    ].join(' ').toLowerCase();

    return searchableText.contains(normalizedQuery);
  }

  String _buildSelectedSongsText(
    List<Song> songs, {
    String title = '선택한 곡 목록',
  }) {
    final lines = <String>['🎧 $title', ''];
    for (var index = 0; index < songs.length; index++) {
      final song = songs[index];
      lines.add('${index + 1}. ${song.artist} - ${song.title}');
    }
    lines.addAll(['', '#오늘의한곡 #TDM']);

    return lines.join('\n');
  }

  void _showSelectedSongsPreviewDialog(
    List<Song> songs, {
    required bool setLimitReached,
    bool allowDeleteSelectedSongs = true,
    VoidCallback? onSetSaved,
    VoidCallback? onDeleted,
  }) {
    if (songs.isEmpty) {
      _showRootSnackBar('\uACE1\uC744 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694.');
      return;
    }

    final text = _buildSelectedSongsText(songs);
    final selectedSongsPreviewScrollController = ScrollController();

    void saveSelectedSongs(BuildContext previewContext) {
      _showSaveSongSetDialog(
        songs,
        onSaved: () {
          if (previewContext.mounted) {
            Navigator.of(previewContext).pop();
          }
          onSetSaved?.call();
          _showRootSnackBar(
            '\uC138\uD2B8\uB97C \uC800\uC7A5\uD588\uC5B4\uC694.',
          );
        },
      );
    }

    showDialog<void>(
      context: context,
      builder: (previewContext) {
        final previewContentMaxHeight =
            MediaQuery.sizeOf(previewContext).height * 0.5;
        final selectedSongsPreviewCanScroll =
            text.split('\n').length * 20 >
            max(0, previewContentMaxHeight - (setLimitReached ? 84 : 56));

        return AlertDialog(
          title: const Text('\uC120\uD0DD\uACE1 \uBCF4\uAE30'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: previewContentMaxHeight),
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '\uC120\uD0DD\uD55C \uACE1 ${songs.length}\uAC1C',
                    style: const TextStyle(
                      color: tdmTextSub,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (setLimitReached) ...[
                    const SizedBox(height: 6),
                    Text(
                      '\uC138\uD2B8\uB294 \uCD5C\uB300 $maxSongSetCount\uAC1C\uAE4C\uC9C0 \uC800\uC7A5\uD560 \uC218 \uC788\uC5B4\uC694.',
                      style: TextStyle(
                        color: tdmTextSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Flexible(
                    child: Scrollbar(
                      controller: selectedSongsPreviewScrollController,
                      thumbVisibility: selectedSongsPreviewCanScroll,
                      child: SingleChildScrollView(
                        controller: selectedSongsPreviewScrollController,
                        padding: EdgeInsets.only(
                          right: selectedSongsPreviewCanScroll ? 8 : 0,
                        ),
                        child: SelectableText(text),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allowDeleteSelectedSongs)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: setLimitReached
                              ? null
                              : () => saveSelectedSongs(previewContext),
                          child: const Text(
                            '\uC138\uD2B8 \uC800\uC7A5',
                            maxLines: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _showDeleteSelectedSongsDialog(
                            songs,
                            onDeleted: () {
                              _runAfterFrame(() {
                                if (previewContext.mounted) {
                                  Navigator.of(previewContext).pop();
                                }
                                onDeleted?.call();
                              });
                            },
                          ),
                          child: const Text(
                            '\uC120\uD0DD\uACE1 \uC0AD\uC81C',
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton(
                    onPressed: setLimitReached
                        ? null
                        : () => saveSelectedSongs(previewContext),
                    child: const Text('\uC138\uD2B8 \uC800\uC7A5', maxLines: 1),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    _showRootSnackBar(
                      '\uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC\uD588\uC5B4\uC694.',
                    );
                  },
                  child: const Text(
                    '\uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC',
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(previewContext).pop(),
                    child: const Text('\uB2EB\uAE30', maxLines: 1),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ).whenComplete(selectedSongsPreviewScrollController.dispose);
  }

  void _showSaveSongSetDialog(List<Song> songs, {VoidCallback? onSaved}) {
    if (songs.isEmpty) {
      _showRootSnackBar('세트로 저장할 곡을 선택해 주세요.');
      return;
    }

    if (_songSets.length >= maxSongSetCount) {
      _showRootSnackBar(
        '\uC138\uD2B8\uB294 \uCD5C\uB300 $maxSongSetCount\uAC1C\uAE4C\uC9C0 \uB9CC\uB4E4 \uC218 \uC788\uC5B4\uC694. \uAE30\uC874 \uC138\uD2B8\uB97C \uC0AD\uC81C\uD558\uAC70\uB098 \uC218\uC815\uD574 \uC8FC\uC138\uC694.',
      );
      return;
    }

    final nameController = TextEditingController();
    var errorText = '';

    showDialog<void>(
      context: context,
      builder: (setContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            return AlertDialog(
              title: const Text('세트 저장'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('선택한 ${songs.length}곡으로 새 세트를 만들어요.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '세트 이름',
                      errorText: errorText.isEmpty ? null : errorText,
                    ),
                    onChanged: (_) {
                      if (errorText.isNotEmpty) {
                        refreshDialog(() {
                          errorText = '';
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(setContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      refreshDialog(() {
                        errorText = '세트 이름을 입력해 주세요.';
                      });
                      return;
                    }
                    if (_hasSongSetNamed(name)) {
                      refreshDialog(() {
                        errorText = '같은 이름의 세트가 이미 있어요. 다른 이름을 입력해 주세요.';
                      });
                      return;
                    }

                    setState(() {
                      _songSets.add(
                        SongSet(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          name: name,
                          songs: List<Song>.of(songs),
                        ),
                      );
                    });
                    _saveSongSets();
                    Navigator.of(setContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) {
                        return;
                      }
                      onSaved?.call();
                      _showRootSnackBar('‘$name’ 세트를 저장했어요.');
                    });
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameController.dispose();
      });
    });
  }

  SongSet? _songSetById(String setId) {
    for (final songSet in _songSets) {
      if (songSet.id == setId) {
        return songSet;
      }
    }
    return null;
  }

  String _buildSongSetText(SongSet songSet) {
    return _buildSelectedSongsText(songSet.songs, title: songSet.name);
  }

  String _buildSongSetExportText(SongSet songSet) {
    final buffer = StringBuffer()
      ..writeln('[세트]')
      ..writeln('세트명: ${_exportSingleLine(songSet.name)}')
      ..writeln('곡 수: ${songSet.songs.length}곡')
      ..writeln()
      ..writeln('[곡]');

    for (var index = 0; index < songSet.songs.length; index++) {
      final song = songSet.songs[index];
      final tags = visibleSongTags(song.tags).join(',');

      buffer
        ..writeln()
        ..writeln(
          '${index + 1}. ${_exportSingleLine(song.artist)} - ${_exportSingleLine(song.title)}',
        );

      if (song.memo.trim().isNotEmpty) {
        buffer.writeln('   메모: ${_exportSingleLine(song.memo)}');
      }
      if (tags.trim().isNotEmpty) {
        buffer.writeln('   태그: ${_exportSingleLine(tags)}');
      }
      if (song.link.trim().isNotEmpty) {
        buffer.writeln('   링크: ${_exportSingleLine(song.link)}');
      }
    }

    return buffer.toString();
  }

  String _buildAllSongSetsExportText() {
    final buffer = StringBuffer()
      ..writeln('[오늘의 한 곡 세트 백업]')
      ..writeln('세트 수: ${_songSets.length}개');

    for (final songSet in _songSets) {
      buffer
        ..writeln()
        ..writeln('====================')
        ..writeln()
        ..write(_buildSongSetExportText(songSet));
    }

    return buffer.toString();
  }

  Future<void> _saveTextExportFile({
    required String fileBaseName,
    required String text,
    required String successMessage,
  }) async {
    try {
      final savedPath = await FileSaver.instance.saveAs(
        name: fileBaseName,
        bytes: Uint8List.fromList(utf8.encode(text)),
        fileExtension: 'txt',
        mimeType: MimeType.text,
      );

      if (savedPath == null || savedPath.trim().isEmpty) {
        _showRootSnackBar('파일 저장에 실패했습니다.');
        return;
      }

      _showRootSnackBar(successMessage);
    } catch (_) {
      _showRootSnackBar('파일 저장에 실패했습니다.');
    }
  }

  Future<void> _exportSongSet(SongSet songSet) async {
    final timestamp = _exportTimestamp();
    final safeSetName = _safeFileNamePart(songSet.name);
    await _saveTextExportFile(
      fileBaseName: 'tdm_set_${safeSetName}_$timestamp',
      text: _buildSongSetExportText(songSet),
      successMessage: '세트 리스트를 내보냈어요.',
    );
  }

  Future<void> _exportAllSongSets() async {
    if (_songSets.isEmpty) {
      _showRootSnackBar('내보낼 세트가 없어요.');
      return;
    }

    await _saveTextExportFile(
      fileBaseName: buildSetsExportFileBaseName(DateTime.now()),
      text: _buildAllSongSetsExportText(),
      successMessage: '전체 세트 리스트를 내보냈어요.',
    );
  }

  Future<void> _importSongSets({VoidCallback? onImported}) async {
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
        _showRootSnackBar(
          '\uC138\uD2B8\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC5B4\uC694.',
        );
        return;
      }

      final importedText = utf8.decode(bytes, allowMalformed: true);
      final importResult = _parseSongSetImport(importedText);
      if (importResult.drafts.isEmpty) {
        _showRootSnackBar(
          '\uBD88\uB7EC\uC62C \uC138\uD2B8\uB97C \uCC3E\uC9C0 \uBABB\uD588\uC5B4\uC694.',
        );
        return;
      }

      _showSongSetImportPreviewDialog(importResult, onImported: onImported);
    } catch (_) {
      _showRootSnackBar(
        '\uC138\uD2B8\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC5B4\uC694.',
      );
    }
  }

  SongSetImportResult _parseSongSetImport(String text) {
    final songByKey = {
      for (final song in _songs) _songDuplicateKey(song): song,
    };
    final drafts = <SongSetImportDraft>[];
    var currentName = '';
    final currentSongs = <Song>[];
    var currentMissingCount = 0;
    var totalMissingCount = 0;
    var emptySetCount = 0;

    void flushCurrentSet() {
      final name = currentName.trim();
      if (name.isEmpty && currentSongs.isEmpty && currentMissingCount == 0) {
        return;
      }
      if (name.isEmpty || currentSongs.isEmpty) {
        emptySetCount++;
      } else {
        drafts.add(
          SongSetImportDraft(
            name: name,
            songs: List<Song>.of(currentSongs),
            missingSongCount: currentMissingCount,
          ),
        );
      }
      currentName = '';
      currentSongs.clear();
      currentMissingCount = 0;
    }

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line == '====================') {
        continue;
      }

      if (line == '[세트]') {
        flushCurrentSet();
        continue;
      }

      if (line.startsWith('세트명:')) {
        currentName = line.substring('세트명:'.length).trim();
        continue;
      }

      final match = RegExp(r'^\d+\.\s*(.+?)\s+-\s+(.+)$').firstMatch(line);
      if (match == null) {
        continue;
      }

      final artist = match.group(1)?.trim() ?? '';
      final title = match.group(2)?.trim() ?? '';
      if (artist.isEmpty || title.isEmpty) {
        continue;
      }

      final matchedSong =
          songByKey[_songDuplicateKey(
            Song(artist: artist, title: title, tags: const []),
          )];
      if (matchedSong == null) {
        currentMissingCount++;
        totalMissingCount++;
      } else {
        currentSongs.add(matchedSong);
      }
    }

    flushCurrentSet();

    return SongSetImportResult(
      drafts: drafts,
      missingSongCount: totalMissingCount,
      emptySetCount: emptySetCount,
    );
  }

  String _uniqueImportedSongSetName(String baseName, Set<String> usedNames) {
    final trimmedBaseName = baseName.trim().isEmpty
        ? '불러온 세트'
        : baseName.trim();
    var candidate = trimmedBaseName;
    var suffix = 2;

    while (usedNames.contains(candidate.toLowerCase())) {
      candidate = '$trimmedBaseName ($suffix)';
      suffix++;
    }

    usedNames.add(candidate.toLowerCase());
    return candidate;
  }

  void _showSongSetImportPreviewDialog(
    SongSetImportResult importResult, {
    VoidCallback? onImported,
  }) {
    final availableSlots = max(0, maxSongSetCount - _songSets.length);
    final importableDrafts = importResult.drafts.take(availableSlots).toList();
    final limitExcludedCount = max(
      0,
      importResult.drafts.length - availableSlots,
    );

    showDialog<void>(
      context: context,
      builder: (previewContext) {
        return AlertDialog(
          title: const Text('\uC138\uD2B8 \uBD88\uB7EC\uC624\uAE30'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: max(
                220.0,
                MediaQuery.sizeOf(previewContext).height -
                    MediaQuery.viewInsetsOf(previewContext).bottom -
                    220,
              ),
            ),
            child: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '\uBD88\uB7EC\uC62C \uC138\uD2B8 ${importableDrafts.length}\uAC1C',
                    ),
                    if (importResult.missingSongCount > 0)
                      Text(
                        '\uC6D0\uBCF8 \uC800\uC7A5\uC18C\uC5D0 \uC5C6\uC5B4 \uC81C\uC678\uB41C \uACE1 ${importResult.missingSongCount}\uACE1',
                        style: const TextStyle(color: tdmTextSub, fontSize: 12),
                      ),
                    if (limitExcludedCount > 0)
                      Text(
                        '\uC800\uC7A5 \uD55C\uB3C4\uB97C \uCD08\uACFC\uD574 \uC81C\uC678\uB41C \uC138\uD2B8 $limitExcludedCount\uAC1C',
                        style: const TextStyle(color: tdmTextSub, fontSize: 12),
                      ),
                    if (importResult.emptySetCount > 0)
                      Text(
                        '\uACE1\uC744 \uCC3E\uC744 \uC218 \uC5C6\uC5B4 \uC81C\uC678\uB41C \uC138\uD2B8 ${importResult.emptySetCount}\uAC1C',
                        style: const TextStyle(color: tdmTextSub, fontSize: 12),
                      ),
                    const SizedBox(height: 12),
                    if (importableDrafts.isEmpty)
                      const Text(
                        '\uBD88\uB7EC\uC62C \uC138\uD2B8\uAC00 \uC5C6\uC5B4\uC694.',
                        textAlign: TextAlign.center,
                      )
                    else
                      ...importableDrafts.map(
                        (draft) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${draft.name} · ${draft.songs.length}\uACE1',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(previewContext).pop(),
              child: const Text('\uCDE8\uC18C'),
            ),
            FilledButton(
              onPressed: importableDrafts.isEmpty
                  ? null
                  : () {
                      final usedNames = _songSets
                          .map((set) => set.name.trim().toLowerCase())
                          .toSet();
                      final now = DateTime.now().microsecondsSinceEpoch;
                      final setsToAdd = <SongSet>[];

                      for (
                        var index = 0;
                        index < importableDrafts.length;
                        index++
                      ) {
                        final draft = importableDrafts[index];
                        setsToAdd.add(
                          SongSet(
                            id: 'imported_${now}_$index',
                            name: _uniqueImportedSongSetName(
                              draft.name,
                              usedNames,
                            ),
                            songs: draft.songs,
                          ),
                        );
                      }

                      setState(() {
                        _songSets = [..._songSets, ...setsToAdd];
                      });
                      _saveSongSets();
                      Navigator.of(previewContext).pop();
                      _runAfterFrame(() {
                        onImported?.call();
                        _showRootSnackBar(
                          '\uC138\uD2B8 ${setsToAdd.length}\uAC1C\uB97C \uBD88\uB7EC\uC654\uC5B4\uC694.',
                        );
                      });
                    },
              child: const Text('\uBD88\uB7EC\uC624\uAE30'),
            ),
          ],
        );
      },
    );
  }

  void _showSongSetDetailDialog(String setId, {VoidCallback? onChanged}) {
    final songSetDetailScrollController = ScrollController();
    var detailSortMode = SongSetDetailSortMode.added;

    showDialog<void>(
      context: context,
      builder: (detailContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final songSet = _songSetById(setId);
            if (songSet == null) {
              return const AlertDialog(content: Text('세트를 찾을 수 없어요.'));
            }

            final visibleSongs = List<Song>.of(songSet.songs);
            switch (detailSortMode) {
              case SongSetDetailSortMode.added:
                break;
              case SongSetDetailSortMode.titleAscending:
                visibleSongs.sort(
                  (a, b) =>
                      a.title.toLowerCase().compareTo(b.title.toLowerCase()),
                );
              case SongSetDetailSortMode.titleDescending:
                visibleSongs.sort(
                  (a, b) =>
                      b.title.toLowerCase().compareTo(a.title.toLowerCase()),
                );
            }
            final songSetContentMaxHeight =
                MediaQuery.sizeOf(detailContext).height * 0.55;
            final songSetSongsCanScroll =
                visibleSongs.length * 46 > max(0, songSetContentMaxHeight - 34);

            return AlertDialog(
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      songSet.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _showSongSetManagementMenu(
                      songSet,
                      onRenamed: () {
                        _runAfterFrame(() {
                          refreshDialog(() {});
                          onChanged?.call();
                        });
                      },
                      onSongsAdded: () {
                        if (detailContext.mounted) {
                          refreshDialog(() {});
                        }
                        onChanged?.call();
                      },
                      onDeleted: () {
                        _runAfterFrame(() {
                          Navigator.of(detailContext).pop();
                          onChanged?.call();
                        });
                      },
                    ),
                    child: const Text('관리', maxLines: 1),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: songSetContentMaxHeight),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('${songSet.songs.length}곡')),
                          DropdownButton<SongSetDetailSortMode>(
                            key: const ValueKey('song-set-detail-sort'),
                            value: detailSortMode,
                            isDense: true,
                            items: const [
                              DropdownMenuItem(
                                value: SongSetDetailSortMode.added,
                                child: Text('등록'),
                              ),
                              DropdownMenuItem(
                                value: SongSetDetailSortMode.titleAscending,
                                child: Text('이름 오름'),
                              ),
                              DropdownMenuItem(
                                value: SongSetDetailSortMode.titleDescending,
                                child: Text('이름 내림'),
                              ),
                            ],
                            onChanged: (mode) {
                              if (mode == null) {
                                return;
                              }
                              refreshDialog(() {
                                detailSortMode = mode;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (songSet.songs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            '이 세트에 담긴 곡이 없어요.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Flexible(
                          child: Scrollbar(
                            controller: songSetDetailScrollController,
                            thumbVisibility: songSetSongsCanScroll,
                            child: ListView.separated(
                              controller: songSetDetailScrollController,
                              padding: EdgeInsets.only(
                                right: songSetSongsCanScroll ? 8 : 0,
                              ),
                              shrinkWrap: true,
                              itemCount: visibleSongs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 8),
                              itemBuilder: (context, index) {
                                final song = visibleSongs[index];
                                return Row(
                                  children: [
                                    _favoriteSongIconButton(
                                      song,
                                      onChanged: () {
                                        if (detailContext.mounted) {
                                          refreshDialog(() {});
                                        }
                                        onChanged?.call();
                                      },
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        key: ValueKey(
                                          'set-song-card-${_songWidgetKey(song)}',
                                        ),
                                        hoverColor: tdmHoverColor,
                                        splashColor: tdmHoverColor,
                                        highlightColor: Colors.transparent,
                                        onTap: () => _showSongActionCard(
                                          song,
                                          sourceSetName: songSet.name,
                                          removeFromSet: songSet,
                                          onSongChanged: () {
                                            if (detailContext.mounted) {
                                              refreshDialog(() {});
                                            }
                                            onChanged?.call();
                                          },
                                          onSongUpdated: () {
                                            if (detailContext.mounted) {
                                              refreshDialog(() {});
                                            }
                                            onChanged?.call();
                                          },
                                          onRemovedFromSet: () {
                                            if (detailContext.mounted) {
                                              refreshDialog(() {});
                                            }
                                            onChanged?.call();
                                          },
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: Text(
                                            '${index + 1}. ${song.artist} - ${song.title}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                    _songRecommendationButton(
                                      song,
                                      sourceSetName: songSet.name,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: songSet.songs.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: _buildSongSetText(songSet)),
                              );
                              _showRootSnackBar('클립보드에 복사했어요.');
                            },
                      child: const Text('클립보드에 복사', maxLines: 1),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(detailContext).pop(),
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
    ).whenComplete(songSetDetailScrollController.dispose);
  }

  void _showSongSetManagementMenu(
    SongSet songSet, {
    VoidCallback? onRenamed,
    VoidCallback? onSongsAdded,
    VoidCallback? onDeleted,
  }) {
    showDialog<void>(
      context: context,
      builder: (menuContext) {
        return AlertDialog(
          title: const Text('\uC138\uD2B8 \uAD00\uB9AC'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() {
                    _showAddSongsToSetDialog(
                      songSet,
                      onSongsAdded: onSongsAdded,
                    );
                  });
                },
                child: const Text('\uACE1 \uCD94\uAC00'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() {
                    _showRenameSongSetDialog(songSet, onRenamed: onRenamed);
                  });
                },
                child: const Text('\uC138\uD2B8\uBA85 \uC218\uC815'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() {
                    _exportSongSet(songSet);
                  });
                },
                child: const Text('\uC138\uD2B8 \uB0B4\uBCF4\uB0B4\uAE30'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(menuContext).pop();
                  _runAfterFrame(() {
                    _showDeleteSongSetDialog(songSet, onDeleted: onDeleted);
                  });
                },
                child: const Text('\uC138\uD2B8 \uC0AD\uC81C'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(menuContext).pop(),
                child: const Text('\uB2EB\uAE30'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddSongsToSetDialog(SongSet songSet, {VoidCallback? onSongsAdded}) {
    final selectedSongs = <Song>{};
    final searchController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (addContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final currentSet = _songSetById(songSet.id) ?? songSet;
            final currentIds = currentSet.songs
                .map((song) => song.id)
                .where((id) => id.isNotEmpty)
                .toSet();
            final songs = _allSongsForOverview();
            final visibleSongs = songs
                .where(
                  (song) => _matchesSongSearch(song, searchController.text),
                )
                .toList();

            return AlertDialog(
              title: const Text('\uACE1 \uCD94\uAC00'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: max(
                    220.0,
                    MediaQuery.sizeOf(addContext).height -
                        MediaQuery.viewInsetsOf(addContext).bottom -
                        190,
                  ),
                ),
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText:
                              '\uAC00\uC218\uBA85, \uACE1\uBA85, \uBA54\uBAA8, \uD0DC\uADF8 \uAC80\uC0C9',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => refreshDialog(() {}),
                      ),
                      const SizedBox(height: 8),
                      if (songs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            '\uC544\uC9C1 \uC800\uC7A5\uB41C \uACE1\uC774 \uC5C6\uC5B4\uC694.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else if (visibleSongs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text(
                            '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC5B4\uC694.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: visibleSongs.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 8),
                            itemBuilder: (context, index) {
                              final song = visibleSongs[index];
                              final alreadyInSet = currentIds.contains(song.id);
                              final checked = selectedSongs.contains(song);

                              return CheckboxListTile(
                                key: ValueKey(
                                  'add-set-${_songWidgetKey(song)}-$index',
                                ),
                                dense: true,
                                value: alreadyInSet ? false : checked,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                onChanged: alreadyInSet
                                    ? null
                                    : (value) {
                                        refreshDialog(() {
                                          if (value ?? false) {
                                            selectedSongs.add(song);
                                          } else {
                                            selectedSongs.remove(song);
                                          }
                                        });
                                      },
                                title: Text(
                                  '${song.artist} - ${song.title}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: alreadyInSet
                                    ? const Text('\uC774\uBBF8 \uC788\uC74C')
                                    : null,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(addContext).pop();
                  },
                  child: const Text('\uCDE8\uC18C'),
                ),
                FilledButton(
                  onPressed: selectedSongs.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _songSets = _songSets
                                .map(
                                  (set) => set.id == currentSet.id
                                      ? set.copyWith(
                                          songs: [
                                            ...set.songs,
                                            ...selectedSongs,
                                          ],
                                        )
                                      : set,
                                )
                                .toList();
                          });
                          _saveSongSets();
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.of(addContext).pop();
                          _runAfterRouteSettled(() {
                            onSongsAdded?.call();
                            _showRootSnackBar(
                              '\uC120\uD0DD\uD55C \uACE1\uC744 \uC138\uD2B8\uC5D0 \uCD94\uAC00\uD588\uC5B4\uC694.',
                            );
                          });
                        },
                  child: const Text('\uCD94\uAC00'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      _disposeTextControllerAfterRoute(searchController);
    });
  }

  void _showRemoveSingleSongFromSetDialog(
    SongSet songSet,
    Song song, {
    VoidCallback? onRemoved,
  }) {
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('곡 제외'),
          content: const Text('이 곡을 세트에서 제외할까요?\n원본 노래 저장소에서는 삭제되지 않아요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _songSets = _songSets
                      .map(
                        (set) => set.id == songSet.id
                            ? set.copyWith(
                                songs: set.songs
                                    .where(
                                      (setSong) =>
                                          !_sameStoredSong(setSong, song),
                                    )
                                    .toList(),
                              )
                            : set,
                      )
                      .toList();
                });
                _saveSongSets();
                Navigator.of(confirmContext).pop();
                _runAfterFrame(() {
                  onRemoved?.call();
                  _showRootSnackBar('곡을 세트에서 제외했어요.');
                });
              },
              child: const Text('제외'),
            ),
          ],
        );
      },
    );
  }

  void _showRenameSongSetDialog(SongSet songSet, {VoidCallback? onRenamed}) {
    final nameController = TextEditingController(text: songSet.name);
    var errorText = '';

    showDialog<void>(
      context: context,
      builder: (renameContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            return AlertDialog(
              title: const Text('이름 수정'),
              content: TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '세트 이름',
                  errorText: errorText.isEmpty ? null : errorText,
                ),
                onChanged: (_) {
                  if (errorText.isNotEmpty) {
                    refreshDialog(() {
                      errorText = '';
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(renameContext).pop(),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      refreshDialog(() {
                        errorText = '세트 이름을 입력해 주세요.';
                      });
                      return;
                    }
                    if (_hasSongSetNamed(name, exceptId: songSet.id)) {
                      refreshDialog(() {
                        errorText = '같은 이름의 세트가 이미 있어요. 다른 이름을 입력해 주세요.';
                      });
                      return;
                    }

                    setState(() {
                      _songSets = _songSets
                          .map(
                            (set) => set.id == songSet.id
                                ? set.copyWith(name: name)
                                : set,
                          )
                          .toList();
                      if (_resultSongSetName == songSet.name) {
                        _resultSongSetName = name;
                      }
                    });
                    _saveSongSets();
                    Navigator.of(renameContext).pop();
                    _runAfterFrame(() {
                      onRenamed?.call();
                      _showRootSnackBar('세트 이름을 수정했어요.');
                    });
                  },
                  child: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      _runAfterFrame(nameController.dispose);
    });
  }

  void _showDeleteSongSetDialog(SongSet songSet, {VoidCallback? onDeleted}) {
    showDialog<void>(
      context: context,
      builder: (deleteContext) {
        return AlertDialog(
          title: const Text('세트를 삭제할까요?'),
          content: Text('‘${songSet.name}’ 세트를 삭제합니다.\n곡 저장소의 원본 곡은 삭제되지 않아요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(deleteContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final wasSelectedSet = _selectedSongSetIds.contains(songSet.id);
                setState(() {
                  _songSets.removeWhere((set) => set.id == songSet.id);
                  _syncSelectedSongSets(showFallbackMessage: true);
                  if (_resultSongSetName == songSet.name) {
                    _resultSongSetName = null;
                  }
                });
                _saveSongSets();
                _saveRandomSelection();
                Navigator.of(deleteContext).pop();
                _runAfterFrame(() {
                  onDeleted?.call();
                  if (!wasSelectedSet || _randomMode == RandomMode.songSets) {
                    _showRootSnackBar('세트를 삭제했어요.');
                  }
                });
              },
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteSelectedSongsDialog(
    List<Song> songs, {
    VoidCallback? onDeleted,
  }) {
    if (songs.isEmpty) {
      _showRootSnackBar('삭제할 곡을 선택해 주세요.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('삭제'),
          content: Text(
            '선택한 ${songs.length}곡을 삭제할까요?\n'
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
                _deleteSelectedSongs(songs);
                onDeleted?.call();
              },
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
  }

  void _deleteSelectedSongs(List<Song> songs) {
    final songsToDelete = songs.toSet();
    if (songsToDelete.isEmpty) {
      _showRootSnackBar('삭제할 곡을 선택해 주세요.');
      return;
    }

    setState(() {
      _songs.removeWhere(songsToDelete.contains);
      _syncArtistFilterState();
      _syncSongSetsWithSongs();

      final selectedSong = _selectedSong;
      if (selectedSong != null && songsToDelete.contains(selectedSong)) {
        _selectedSong = null;
        _shareTextController.clear();
        _includeSongLink = true;
      }

      final lastResultSong = _lastResultSong;
      if (lastResultSong != null &&
          songsToDelete.any(
            (song) => _isSameSongResult(song, lastResultSong),
          )) {
        _lastResultSong = null;
      }

      if (_selectedSong == null) {
        _isSponsorPick = false;
      }
    });
    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();
    _showRootSnackBar('선택한 ${songsToDelete.length}곡을 삭제했어요.');
  }

  void _showDeleteSongDialog(Song song, {VoidCallback? onDeleted}) {
    showDialog<void>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: const Text('이 곡을 삭제할까요?'),
          content: Text(
            '${song.artist} - ${song.title}\n\n'
            '삭제하면 노래 저장소에서 완전히 삭제되며,\n'
            '이 곡이 포함된 세트에서도 함께 사라집니다.',
          ),
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
                          if (_selectedSong != null) ...[
                            SongResultCard(
                              song: _songWithCurrentFavorite(_selectedSong!),
                              sourceSetName: _resultSongSetName,
                              isFavorite: _isSongFavorite(_selectedSong!),
                              onFavoriteToggle: () =>
                                  _toggleSongFavorite(_selectedSong!),
                            ),
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
                            MainSponsorPanel(
                              ad: _mainAd,
                              onOpenLink: () =>
                                  _openSponsorLink(_mainAd.linkUrl),
                              onPickSponsorSong: _pickMainSponsorSong,
                            ),
                            const SizedBox(height: 16),
                            _PickSongButton(
                              label:
                                  '\uC624\uB298\uC758 \uD55C \uACE1 \uBF51\uAE30',
                              onPressed: _pickRandomSong,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _drawScopeLabel(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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

class SongSetTile extends StatelessWidget {
  final SongSet songSet;
  final String? searchMatchSummary;
  final bool isSelectedForRandom;
  final ValueChanged<bool> onRandomToggle;
  final VoidCallback onTap;

  const SongSetTile({
    super.key,
    required this.songSet,
    this.searchMatchSummary,
    required this.isSelectedForRandom,
    required this.onRandomToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelectedForRandom ? tdmCardBackground : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: isSelectedForRandom ? tdmPrimary : tdmBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: tdmHoverColor,
          splashColor: tdmHoverColor,
          highlightColor: Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        songSet.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${songSet.songs.length}\uACE1',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (searchMatchSummary != null &&
                          searchMatchSummary!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          searchMatchSummary!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: tdmTextSub,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  selected: isSelectedForRandom,
                  showCheckmark: true,
                  checkmarkColor: Colors.white,
                  label: const Text(
                    '\uB79C\uB364 \uC120\uD0DD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selectedColor: tdmPrimary,
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: isSelectedForRandom ? tdmPrimary : tdmBorder,
                  ),
                  labelStyle: TextStyle(
                    color: isSelectedForRandom ? Colors.white : tdmPrimaryDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (value) => onRandomToggle(value),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
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
  final bool isRandomEnabled;
  final ValueChanged<bool>? onRandomToggle;
  final VoidCallback onTap;

  const ArtistSongGroupTile({
    super.key,
    required this.artist,
    required this.songs,
    required this.isRandomEnabled,
    required this.onRandomToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final randomControlDisabled = onRandomToggle == null;
    final disabledTextColor = Colors.grey.shade500;
    final enabledTextColor = isRandomEnabled
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final cardColor = randomControlDisabled
        ? Colors.grey.shade100
        : isRandomEnabled
        ? colorScheme.surfaceContainerHigh
        : Colors.grey.shade100;
    final borderColor = randomControlDisabled
        ? Colors.grey.shade300
        : colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: tdmHoverColor,
          splashColor: tdmHoverColor,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Checkbox(
                  value: isRandomEnabled,
                  onChanged: onRandomToggle == null
                      ? null
                      : (value) => onRandomToggle!(value ?? false),
                  checkColor: randomControlDisabled
                      ? Colors.grey.shade500
                      : Colors.white,
                  fillColor: WidgetStateProperty.resolveWith((states) {
                    if (randomControlDisabled) {
                      return isRandomEnabled
                          ? Colors.grey.shade300
                          : Colors.grey.shade100;
                    }
                    if (states.contains(WidgetState.selected)) {
                      return tdmPrimary;
                    }
                    return null;
                  }),
                  side: BorderSide(
                    color: randomControlDisabled
                        ? Colors.grey.shade400
                        : colorScheme.outline,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artist,
                        style: TextStyle(
                          color: randomControlDisabled
                              ? disabledTextColor
                              : enabledTextColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${songs.length}곡',
                        style: TextStyle(
                          color: randomControlDisabled
                              ? Colors.grey.shade500
                              : colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: randomControlDisabled
                      ? Colors.grey.shade400
                      : colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsDialog extends StatefulWidget {
  final String initialDefaultMessage;
  final ValueChanged<String> onSave;
  final VoidCallback onContactEmail;
  final VoidCallback onOpenOfficialX;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onImportBackup;
  final VoidCallback onResetApp;

  const SettingsDialog({
    super.key,
    required this.initialDefaultMessage,
    required this.onSave,
    required this.onContactEmail,
    required this.onOpenOfficialX,
    required this.onExportBackup,
    required this.onImportBackup,
    required this.onResetApp,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _defaultMessageController;
  bool _isManagingData = false;

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

  Future<void> _runDataAction(Future<void> Function() action) async {
    if (_isManagingData) {
      return;
    }
    setState(() {
      _isManagingData = true;
    });
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() {
          _isManagingData = false;
        });
      }
    }
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
                hintText: '예: 오늘은 이 곡을 들어보세요.',
                border: OutlineInputBorder(),
              ),
            ),
            const Divider(height: 28),
            Text('문의 및 소식', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              '문의 todaydrawmusic@gmail.com',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onContactEmail,
              child: const Text('이메일로 문의하기'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onOpenOfficialX,
              child: const Text('X @todaydrawmusic'),
            ),
            const Divider(height: 28),
            Text('데이터 관리', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              '곡, 세트, 좋아요, 공유 문구와 앱 설정을 파일로 저장합니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isManagingData
                  ? null
                  : () => _runDataAction(widget.onExportBackup),
              child: const Text('앱 백업 내보내기'),
            ),
            const SizedBox(height: 8),
            Text(
              '백업 파일로 앱 데이터를 복원합니다. 현재 데이터는 바뀔 수 있습니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isManagingData
                  ? null
                  : () => _runDataAction(widget.onImportBackup),
              child: const Text('앱 백업 불러오기'),
            ),
            const SizedBox(height: 8),
            Text(
              '모든 곡, 세트, 좋아요와 앱 설정을 삭제합니다.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isManagingData ? null : widget.onResetApp,
              child: const Text('앱 초기화'),
            ),
            const Divider(height: 28),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('앱 버전', style: TextStyle(fontWeight: FontWeight.w700)),
                Flexible(
                  child: Text(
                    appDisplayVersion,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('저장')),
          ],
        ),
      ],
    );
  }
}

class HelpIconButton extends StatelessWidget {
  final String tooltip;
  final String title;
  final String message;

  const HelpIconButton({
    super.key,
    this.tooltip = '\uB3C4\uC6C0\uB9D0',
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.help_outline),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('\uB2EB\uAE30'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

List<String> normalizeTagInput(String text) {
  final result = <String>[];
  final seen = <String>{};
  for (final rawTag in text.split(RegExp(r'\s+'))) {
    final trimmed = rawTag.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final tag = trimmed.startsWith('#') ? trimmed : '#$trimmed';
    if (seen.add(tag.toLowerCase())) {
      result.add(tag);
      if (result.length == maxSongTagCount) {
        break;
      }
    }
  }
  return result;
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
    final hasTrailingSpace = RegExp(r'\s$').hasMatch(original);
    final formattedTags = normalizeTagInput(original);
    final formatted =
        '${formattedTags.join(' ')}${hasTrailingSpace ? ' ' : ''}';

    if (formatted == original) {
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _isFormatting = true;
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormatting = false;
    if (mounted) {
      setState(() {});
    }
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
      decoration: InputDecoration(
        labelText: '해시태그',
        border: const OutlineInputBorder(),
        counterText:
            '${normalizeTagInput(widget.controller.text).length}/$maxSongTagCount개',
      ),
    );
  }
}

class AddSongDialog extends StatefulWidget {
  final List<String> artistNames;
  final List<Song> existingSongs;
  final ValueChanged<Song> onSubmit;
  final Future<void> Function(Song song)? onOpenLinkOrSearch;
  final Song? initialSong;

  const AddSongDialog({
    super.key,
    required this.artistNames,
    required this.existingSongs,
    required this.onSubmit,
    this.onOpenLinkOrSearch,
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
      id: widget.initialSong?.id ?? '',
      artist: artist,
      title: title,
      tags: tags,
      memo: normalizeSongMemo(_memoController.text),
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
      final initialSong = widget.initialSong;
      if (identical(existingSong, initialSong) ||
          (initialSong != null &&
              initialSong.id.isNotEmpty &&
              existingSong.id == initialSong.id)) {
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

  Song _currentDraftSong() {
    final initialSong = widget.initialSong;
    return Song(
      id: initialSong?.id ?? '',
      artist: _artistName.trim().isNotEmpty
          ? _artistName.trim()
          : initialSong?.artist ?? '',
      title: _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : initialSong?.title ?? '',
      tags: normalizeTagInput(_tagsController.text),
      memo: normalizeSongMemo(_memoController.text),
      link: _linkController.text.trim(),
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
                maxLength: maxSongMemoLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(maxSongMemoLength),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '메모',
                  border: const OutlineInputBorder(),
                  counterText:
                      '${_memoController.text.characters.length}/$maxSongMemoLength자',
                ),
              ),
              const SizedBox(height: 12),
              HashTagTextField(controller: _tagsController),
              const SizedBox(height: 12),
              TextField(
                controller: _linkController,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '링크',
                  border: const OutlineInputBorder(),
                  suffixIcon: widget.onOpenLinkOrSearch != null
                      ? IconButton(
                          tooltip: _linkController.text.trim().isNotEmpty
                              ? '링크 열기'
                              : '링크 검색',
                          onPressed: () =>
                              widget.onOpenLinkOrSearch!(_currentDraftSong()),
                          icon: Icon(
                            _linkController.text.trim().isNotEmpty
                                ? Icons.link
                                : Icons.search,
                          ),
                        )
                      : null,
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

class MainSponsorPanel extends StatelessWidget {
  final MainSponsorAd ad;
  final VoidCallback onOpenLink;
  final VoidCallback onPickSponsorSong;

  const MainSponsorPanel({
    super.key,
    required this.ad,
    required this.onOpenLink,
    required this.onPickSponsorSong,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasLink = ad.linkUrl.trim().isNotEmpty;
    final hasMessage = ad.message.trim().isNotEmpty;
    final song = ad.song;
    final songLabel = song == null ? '' : '${song.artist} - ${song.title}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: hasLink,
            label: hasMessage
                ? ad.message
                : '\uBA54\uC778 \uC804\uAD11\uD310 \uC774\uBBF8\uC9C0',
            child: Material(
              color: colorScheme.surface,
              child: InkWell(
                onTap: hasLink ? onOpenLink : null,
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: _SponsorAdImage(
                    imageUrl: ad.imageUrl,
                    fallbackAssetPath: ad.fallbackAsset,
                  ),
                ),
              ),
            ),
          ),
          if (hasMessage || songLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '\uC120\uCC29\uC21C \uC601\uC5C5\uACE1',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (songLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                songLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (hasMessage) ...[
              const SizedBox(height: 6),
              Text(
                ad.message,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onPickSponsorSong,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('추천곡 뽑기', maxLines: 1),
          ),
        ],
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
        child: AspectRatio(
          aspectRatio: 6 / 1,
          child: Material(
            color: colorScheme.surfaceContainerHigh,
            child: InkWell(
              onTap: hasLink ? onTap : null,
              child: _SponsorAdImage(
                imageUrl: ad.imageUrl,
                fallbackAssetPath: fallbackBottomAdAssetPath,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SponsorAdImage extends StatelessWidget {
  final String imageUrl;
  final String fallbackAssetPath;

  const _SponsorAdImage({
    required this.imageUrl,
    required this.fallbackAssetPath,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _FallbackSponsorAdImage(assetPath: fallbackAssetPath);
    }

    return Image.network(
      imageUrl.trim(),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('SponsorAd image load error: ${imageUrl.trim()} / $error');
        return _FallbackSponsorAdImage(assetPath: fallbackAssetPath);
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return _FallbackSponsorAdImage(assetPath: fallbackAssetPath);
      },
    );
  }
}

class _FallbackSponsorAdImage extends StatelessWidget {
  final String assetPath;

  const _FallbackSponsorAdImage({required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        if (assetPath == fallbackBottomAdAssetPath) {
          return const SizedBox.shrink();
        }

        debugPrint('SponsorAd fallback asset load error: $assetPath / $error');
        if (assetPath == fallbackMainAdAssetPath) {
          return const _MainSponsorImagePlaceholder();
        }

        return Image.asset(fallbackBottomAdAssetPath, fit: BoxFit.contain);
      },
    );
  }
}

class _MainSponsorImagePlaceholder extends StatelessWidget {
  const _MainSponsorImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
      child: Center(
        child: Text(
          'MAIN AD TEST',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class SongResultCard extends StatelessWidget {
  final Song? song;
  final String? sourceSetName;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const SongResultCard({
    super.key,
    required this.song,
    this.sourceSetName,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

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
          if (sourceSetName != null && sourceSetName!.trim().isNotEmpty) ...[
            Text(
              '\u2018${sourceSetName!.trim()}\u2019 \uC138\uD2B8',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  song!.artist,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: isFavorite
                    ? '\uC990\uACA8\uCC3E\uAE30 \uD574\uC81C'
                    : '\uC990\uACA8\uCC3E\uAE30 \uCD94\uAC00',
                onPressed: onFavoriteToggle,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: isFavorite
                      ? const Color(0xFFF2B84B)
                      : colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
                ),
              ),
            ],
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
              normalizeSongMemo(song!.memo),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (visibleSongTags(song!.tags).isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              visibleSongTags(song!.tags).take(maxSongTagCount).join(' '),
              key: const ValueKey('result-song-tags'),
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
