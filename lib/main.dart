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

const Color tdmPrimary = Color(0xFF12CDB3);
const Color tdmPrimaryDark = Color(0xFF0FAF9A);
const Color tdmSky = Color(0xFF87D3FF);
const Color tdmLime = Color(0xFFEBF195);
const Color tdmLimeText = Color(0xFFC9D94F);
const Color tdmBackground = Color(0xFFF6FFFC);
const Color tdmCardBackground = Color(0xFFEFFFFB);
const Color tdmTextMain = Color(0xFF173A3A);
const Color tdmTextSub = Color(0xFF5F7474);
const Color tdmBorder = Color(0xFFB7E8E1);
const Color tdmLinkBlue = Color(0xFF3A8FC3);
const int maxSongSetCount = 30;

class SongStorage {
  static const String _songsKey = 'tdm_alpha_songs';
  static const String _songSetsKey = 'tdm_song_sets';
  static const String _randomModeKey = 'tdm_random_mode';
  static const String _selectedSongSetIdsKey = 'tdm_selected_song_set_ids';
  static const String _samplePromptCheckedKey = 'sample_prompt_checked';
  static const String _defaultShareMessageKey = 'tdm_default_share_message';
  static const String _disabledRandomArtistsKey = 'tdm_disabled_random_artists';

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

enum PasteSongCandidateStatus { newSong, existing, needsReview }

enum ArtistSortMode { added, name, songCount }

enum SongListSortMode { added, title }

enum SongStorageTab { songs, sets }

enum RandomMode { artistRandom, songSets }

class PasteSongCandidate {
  final String sourceLine;
  final Song? song;
  final PasteSongCandidateStatus status;

  const PasteSongCandidate({
    required this.sourceLine,
    required this.song,
    required this.status,
  });

  String get statusLabel {
    switch (status) {
      case PasteSongCandidateStatus.newSong:
        return '새 곡';
      case PasteSongCandidateStatus.existing:
        return '이미 있음';
      case PasteSongCandidateStatus.needsReview:
        return '확인 필요';
    }
  }
}

class PasteSongDraft {
  final String sourceLine;
  final String? artist;
  final String? title;
  final bool usesInferredArtist;
  final bool needsReview;

  const PasteSongDraft({
    required this.sourceLine,
    this.artist,
    this.title,
    this.usesInferredArtist = false,
    this.needsReview = false,
  });
}

class PasteSongAnalysis {
  final String inferredArtist;
  final List<PasteSongDraft> drafts;

  const PasteSongAnalysis({required this.inferredArtist, required this.drafts});
}

const String _kSetlist = '\uC14B\uB9AC\uC2A4\uD2B8';
const String _kConcert = '\uACF5\uC5F0';
const String _kConcertKo = '\uCF58\uC11C\uD2B8';
const String _kLiveKo = '\uB77C\uC774\uBE0C';
const String _kEncoreSong = '\uC575\uCF5C\uACE1';
const String _kTodaySongs = '\uC624\uB298 \uB4E4\uC740 \uB178\uB798';
const String _kEncore = '\uC575\uCF5C';

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
  ArtistSortMode _artistSortMode = ArtistSortMode.added;
  SongStorageTab _songStorageTab = SongStorageTab.songs;
  Set<String> _disabledRandomArtists = {};
  List<SongSet> _songSets = [];
  RandomMode _randomMode = RandomMode.artistRandom;
  List<String> _selectedSongSetIds = [];

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

    if (!mounted) {
      return;
    }

    setState(() {
      final loadedSongs = savedSongs ?? [];
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
      _selectedSong = null;
      _lastResultSong = null;
      _isSponsorPick = false;
      _resultSongSetName = null;
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
  }

  List<SongSet> _songSetsSyncedWithSongs(List<SongSet> sets, List<Song> songs) {
    final currentSongsByKey = {
      for (final song in songs) _songDuplicateKey(song): song,
    };

    return sets
        .map(
          (set) => set.copyWith(
            songs: set.songs
                .map((song) => currentSongsByKey[_songDuplicateKey(song)])
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
    final originalKey = _songDuplicateKey(originalSong);

    _songSets = _songSets
        .map(
          (set) => set.copyWith(
            songs: set.songs
                .map(
                  (song) => _songDuplicateKey(song) == originalKey
                      ? updatedSong
                      : song,
                )
                .toList(),
          ),
        )
        .toList();
  }

  void _toggleSongFavorite(Song song, {VoidCallback? onChanged}) {
    final songKey = _songDuplicateKey(song);
    Song? updatedSong;

    setState(() {
      final index = _songs.indexWhere(
        (storedSong) => _songDuplicateKey(storedSong) == songKey,
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
                        _songs = List<Song>.of(sampleSongs);
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

  Song _canonicalStoredSong(Song song) {
    for (final storedSong in _songs) {
      if (_isSameSongResult(storedSong, song)) {
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
      _showRootSnackBar('뽑기 후보가 없어요. 노래 저장소에서 랜덤 후보로 사용할 가수를 활성화해 주세요.');
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
      _showRootSnackBar('가수 랜덤으로 변경했어요.');
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
      return '현재 뽑기 범위: 선택된 가수 없음';
    }
    return '현재 뽑기 범위: 선택한 가수 ${activeArtists.length}팀';
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
                ? '모든 가수를 랜덤 후보에서 제외하면 오늘의 한 곡을 뽑을 수 없어요.\n'
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
        _syncArtistFilterState();
      });
      _saveSongs();
      _saveDisabledRandomArtists();
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

  Song? _storedSongMatching(Song song) {
    final key = _songDuplicateKey(song);
    for (final storedSong in _songs) {
      if (_songDuplicateKey(storedSong) == key) {
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
    return _songDuplicateKey(first) == _songDuplicateKey(second);
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
          onResetSongs: _showResetSongsDialog,
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
      _lastResultSong = null;
      _isSponsorPick = false;
      _resultSongSetName = null;
      _disabledRandomArtists.clear();
      _songSets.clear();
      _randomMode = RandomMode.artistRandom;
      _selectedSongSetIds.clear();
      _shareTextController.clear();
      _includeTodayTag = true;
      _includeSongLink = true;
    });
    SongStorage.setSamplePromptChecked(true);
    _saveSongs();
    _saveDisabledRandomArtists();
    _saveSongSets();
    _saveRandomSelection();
    _showRootSnackBar('저장된 곡 목록을 초기화했어요.');
  }

  void _addSong(Song song) {
    setState(() {
      _songs.add(song);
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
      final index = _songs.indexWhere((song) => identical(song, originalSong));

      if (index == -1) {
        return;
      }

      updatedSong = updatedSong.copyWith(isFavorite: _songs[index].isFavorite);
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
      _songs.remove(song);
      _syncArtistFilterState();
      _syncSongSetsWithSongs();
      if (_selectedSong == song) {
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
              case ArtistSortMode.added:
                break;
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
                          '총 ${_songs.length}곡 · 가수 ${groupedSongs.length}팀',
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
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SegmentedButton<ArtistSortMode>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: ArtistSortMode.added,
                                      label: Text('등록순'),
                                    ),
                                    ButtonSegment(
                                      value: ArtistSortMode.name,
                                      label: Text('이름순'),
                                    ),
                                    ButtonSegment(
                                      value: ArtistSortMode.songCount,
                                      label: Text('곡수순'),
                                    ),
                                  ],
                                  selected: {_artistSortMode},
                                  onSelectionChanged: (selection) {
                                    refreshSheet(() {
                                      _artistSortMode = selection.first;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () => _showAllSongsDialog(
                                onSongsChanged: () => refreshSheet(() {}),
                              ),
                              child: const Text('전체보기', maxLines: 1),
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
                              '세트 랜덤 사용 중에는 가수 랜덤 설정이 잠시 적용되지 않아요.\n'
                              '세트 선택을 모두 해제하면 다시 가수 랜덤을 사용할 수 있어요.',
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
    final songKey = _songDuplicateKey(song);
    return _songSets
        .where(
          (songSet) => songSet.songs.any(
            (setSong) => _songDuplicateKey(setSong) == songKey,
          ),
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
                    _runAfterFrame(_showResetSongsDialog);
                  },
                  child: const Text('전체 초기화'),
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
    String artistName = '';
    String? artistErrorText;
    String? titleErrorText;

    void disposeControllers() {
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
                memo: memoController.text.trim(),
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

            final dialogMedia = MediaQuery.of(dialogContext);
            final availableDialogHeight =
                dialogMedia.size.height - dialogMedia.viewInsets.bottom - 48;
            final maxDialogHeight = min(
              max(200.0, availableDialogHeight - 180),
              520.0,
            );

            return DefaultTabController(
              length: 2,
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
                      const TabBar(
                        tabs: [
                          Tab(text: '\uBD99\uC5EC\uB123\uAE30'),
                          Tab(text: '\uAC1C\uBCC4 \uACE1 \uCD94\uAC00'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TabBarView(
                          children: [
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
                                  OutlinedButton(
                                    onPressed: () {
                                      FocusManager.instance.primaryFocus
                                          ?.unfocus();
                                      final analysis = _analyzePastedSongs(
                                        pasteController.text,
                                      );
                                      _showPasteSongAnalysisDialog(
                                        analysis,
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
                                    decoration: const InputDecoration(
                                      labelText: '\uBA54\uBAA8',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  HashTagTextField(controller: tagsController),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: linkController,
                                    keyboardType: TextInputType.url,
                                    decoration: const InputDecoration(
                                      labelText: '\uB9C1\uD06C',
                                      border: OutlineInputBorder(),
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
    VoidCallback? onSongsAdded,
  }) {
    final inferredArtistController = TextEditingController(
      text: analysis.inferredArtist,
    );
    final excludedIndexes = <int>{};

    showDialog<void>(
      context: context,
      builder: (analysisContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final candidates = _buildPasteSongCandidates(
              analysis.drafts,
              inferredArtistController.text,
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
            final needsReviewCount = candidates
                .where(
                  (candidate) =>
                      candidate.status == PasteSongCandidateStatus.needsReview,
                )
                .length;
            final selectedNewSongCount = candidates
                .asMap()
                .entries
                .where(
                  (entry) =>
                      entry.value.status == PasteSongCandidateStatus.newSong &&
                      !excludedIndexes.contains(entry.key),
                )
                .length;
            final dialogMedia = MediaQuery.of(analysisContext);
            final maxDialogHeight = max(
              320.0,
              dialogMedia.size.height - dialogMedia.viewInsets.bottom - 120,
            );

            return AlertDialog(
              title: const Text('\uBD84\uC11D \uACB0\uACFC'),
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
                      controller: inferredArtistController,
                      decoration: const InputDecoration(
                        labelText: '\uCD94\uC815 \uAC00\uC218\uBA85',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => refreshDialog(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '\uC0C8 \uACE1 $newSongCount\uACE1 \u00B7 '
                      '\uC774\uBBF8 \uC788\uC74C $existingCount\uACE1 \u00B7 '
                      '\uD655\uC778 \uD544\uC694 $needsReviewCount\uACE1',
                      style: const TextStyle(
                        color: tdmTextSub,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
                          : ListView.separated(
                              itemCount: candidates.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final candidate = candidates[index];
                                final song = candidate.song;
                                final canInclude =
                                    candidate.status ==
                                    PasteSongCandidateStatus.newSong;
                                final isIncluded =
                                    canInclude &&
                                    !excludedIndexes.contains(index);
                                final colorScheme = Theme.of(
                                  context,
                                ).colorScheme;

                                return ListTile(
                                  key: ValueKey(
                                    'paste-result-${candidate.sourceLine}-$index-${song?.artist ?? ''}-${song?.title ?? ''}-${candidate.status.name}',
                                  ),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Checkbox(
                                    value: isIncluded,
                                    onChanged: canInclude
                                        ? (value) {
                                            refreshDialog(() {
                                              if (value ?? false) {
                                                excludedIndexes.remove(index);
                                              } else {
                                                excludedIndexes.add(index);
                                              }
                                            });
                                          }
                                        : null,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  title: Text(
                                    song == null
                                        ? candidate.sourceLine
                                        : '${song.artist} - ${song.title}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
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
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selectedNewSongCount == 0
                            ? null
                            : () {
                                final selectedCandidates = candidates
                                    .asMap()
                                    .entries
                                    .where(
                                      (entry) =>
                                          !excludedIndexes.contains(entry.key),
                                    )
                                    .map((entry) => entry.value)
                                    .toList();
                                final addedCount = _addPastedNewSongs(
                                  selectedCandidates,
                                  showSnackBar: false,
                                );
                                if (addedCount == 0) {
                                  return;
                                }

                                FocusManager.instance.primaryFocus?.unfocus();
                                Navigator.of(analysisContext).pop();
                                _runAfterRouteSettled(() {
                                  onSongsAdded?.call();
                                  _showRootSnackBar(
                                    '\uC120\uD0DD\uD55C \uACE1\uC744 \uCD94\uAC00\uD588\uC5B4\uC694.',
                                  );
                                });
                              },
                        child: const Text('\uC120\uD0DD\uACE1 \uCD94\uAC00'),
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
      case PasteSongCandidateStatus.existing:
        return colorScheme.onSurfaceVariant;
      case PasteSongCandidateStatus.needsReview:
        return colorScheme.error;
    }
  }

  int _addPastedNewSongs(
    List<PasteSongCandidate> candidates, {
    VoidCallback? onSongsAdded,
    bool showSnackBar = true,
  }) {
    final songsToAdd = candidates
        .where(
          (candidate) => candidate.status == PasteSongCandidateStatus.newSong,
        )
        .map((candidate) => candidate.song)
        .nonNulls
        .toList();
    final existingCount = candidates
        .where(
          (candidate) => candidate.status == PasteSongCandidateStatus.existing,
        )
        .length;

    if (songsToAdd.isEmpty) {
      if (showSnackBar) {
        _showRootSnackBar(
          '\uC0C8\uB85C \uCD94\uAC00\uD560 \uACE1\uC774 \uC5C6\uC5B4\uC694.',
        );
      }
      return 0;
    }

    setState(() {
      _songs.addAll(songsToAdd);
    });
    _saveSongs();
    onSongsAdded?.call();

    if (showSnackBar) {
      final message = existingCount == 0
          ? '\uC0C8 \uACE1 ${songsToAdd.length}\uAC1C\uB97C \uCD94\uAC00\uD588\uC5B4\uC694.'
          : '\uC0C8 \uACE1 ${songsToAdd.length}\uAC1C\uB97C \uCD94\uAC00\uD588\uC5B4\uC694. \uC774\uBBF8 \uC788\uB294 \uACE1 $existingCount\uAC1C\uB294 \uC81C\uC678\uD588\uC5B4\uC694.';
      _showRootSnackBar(message);
    }

    return songsToAdd.length;
  }

  PasteSongAnalysis _analyzePastedSongs(String text) {
    final inferredArtist = _inferPastedArtist(text);
    final drafts = <PasteSongDraft>[];
    var lineIndex = 0;

    for (final rawLine in const LineSplitter().convert(text)) {
      final rawTrimmedLine = rawLine.trim();
      if (rawTrimmedLine.isEmpty) {
        lineIndex++;
        continue;
      }

      if (_isPastedMetaLine(rawTrimmedLine, inferredArtist, lineIndex)) {
        lineIndex++;
        continue;
      }

      final isNumberedArtistTitleLine = _isHashNumberedArtistTitleLine(
        rawTrimmedLine,
      );
      final cleanedLine = _cleanPastedSongLine(rawLine);
      if (cleanedLine.isEmpty) {
        lineIndex++;
        continue;
      }

      if (_isPastedMetaLine(cleanedLine, inferredArtist, lineIndex)) {
        lineIndex++;
        continue;
      }

      final parsedSong = _parsePastedSongLine(
        cleanedLine,
        hasInferredArtist: inferredArtist.trim().isNotEmpty,
        forceArtistTitleOrder: isNumberedArtistTitleLine,
      );
      if (parsedSong != null) {
        drafts.add(
          PasteSongDraft(
            sourceLine: cleanedLine,
            artist: parsedSong.artist,
            title: parsedSong.title,
          ),
        );
        lineIndex++;
        continue;
      }

      final titleOnly = _parseTitleOnlyPastedLine(
        cleanedLine,
        allowSeparators: inferredArtist.trim().isNotEmpty,
      );
      drafts.add(
        PasteSongDraft(
          sourceLine: cleanedLine,
          title: titleOnly,
          usesInferredArtist: titleOnly != null,
          needsReview: titleOnly == null,
        ),
      );
      lineIndex++;
    }

    return PasteSongAnalysis(inferredArtist: inferredArtist, drafts: drafts);
  }

  List<PasteSongCandidate> _buildPasteSongCandidates(
    List<PasteSongDraft> drafts,
    String inferredArtist,
  ) {
    final candidates = <PasteSongCandidate>[];
    final existingKeys = _songs.map(_songDuplicateKey).toSet();
    final existingNormalizedKeys = _songs.map(_pasteSongDuplicateKey).toSet();
    final seenKeys = <String>{};
    final seenNormalizedKeys = <String>{};
    final normalizedInferredArtist = inferredArtist.trim();

    for (final draft in drafts) {
      final artist = draft.usesInferredArtist
          ? normalizedInferredArtist
          : draft.artist?.trim() ?? '';
      final title = draft.title?.trim() ?? '';
      if (draft.needsReview || artist.isEmpty || title.isEmpty) {
        candidates.add(
          PasteSongCandidate(
            sourceLine: draft.sourceLine,
            song: null,
            status: PasteSongCandidateStatus.needsReview,
          ),
        );
        continue;
      }

      final parsedSong = Song(artist: artist, title: title, tags: const []);
      final key = _songDuplicateKey(parsedSong);
      final normalizedKey = _pasteSongDuplicateKey(parsedSong);
      final isExactDuplicate =
          existingKeys.contains(key) || seenKeys.contains(key);
      final isSimilarDuplicate =
          existingNormalizedKeys.contains(normalizedKey) ||
          seenNormalizedKeys.contains(normalizedKey);
      final status = isExactDuplicate || isSimilarDuplicate
          ? PasteSongCandidateStatus.existing
          : PasteSongCandidateStatus.newSong;
      seenKeys.add(key);
      seenNormalizedKeys.add(normalizedKey);

      candidates.add(
        PasteSongCandidate(
          sourceLine: draft.sourceLine,
          song: parsedSong,
          status: status,
        ),
      );
    }

    return candidates;
  }

  String _pasteSongDuplicateKey(Song song) {
    return '${_normalizePasteCompareText(song.artist)}|${_normalizePasteTitle(song.title)}';
  }

  String _normalizePasteCompareText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'''[“”"'`´]'''), '');
  }

  String _normalizePasteTitle(String title) {
    return _normalizePasteCompareText(
      title
          .replaceAll(RegExp(r'\([^)]*\)|（[^）]*）|\[[^\]]*\]'), ' ')
          .replaceAll(RegExp(r'[~!@#$%^&*_+=|\\<>?;:,.·ㆍ]'), ' '),
    );
  }

  String _cleanPastedSongLine(String rawLine) {
    var line = rawLine.trim().replaceAll(RegExp(r'\s+'), ' ');
    line = line.replaceFirst(RegExp(r'^#\d+\s+(?=.*\s(?:-|–|—|/)\s)'), '');
    line = line.replaceFirst(RegExp(r'^[+\-*•]\s*'), '');
    line = line.replaceFirst(RegExp(r'^\d+(?:[\.\)]\s*|\s+)'), '');
    line = line.replaceFirst(RegExp(r'^[+\-*•]\s*'), '');
    return line
        .replaceAll(RegExp(r'''["“”‘’]'''), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isHashNumberedArtistTitleLine(String line) {
    return RegExp(r'^#\d+\s+.+\s(?:-|–|—|/)\s.+$').hasMatch(line.trim());
  }

  String _inferPastedArtist(String text) {
    final lines = const LineSplitter()
        .convert(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_isTdmSharedListMetaLine(line))
        .toList();
    final topLines = lines.take(5).toList();

    for (final line in topLines) {
      final bracketArtist = _artistFromBracketHeader(line);
      if (bracketArtist.isNotEmpty) {
        return bracketArtist;
      }
    }

    for (final line in topLines) {
      final quotedArtist = _artistFromCornerBrackets(line);
      if (quotedArtist.isNotEmpty) {
        return quotedArtist;
      }
    }

    for (final line in topLines) {
      final hashtagArtist = _artistFromHeaderHashtags(line);
      if (hashtagArtist.isNotEmpty) {
        return hashtagArtist;
      }
    }

    if (lines.isNotEmpty) {
      final lastHashtagArtist = _artistFromSingleHashtagLine(lines.last);
      if (lastHashtagArtist.isNotEmpty) {
        return lastHashtagArtist;
      }
    }

    for (final line in topLines) {
      final candidate = _cleanPastedHeaderArtist(line);
      if (candidate.isNotEmpty) {
        return candidate;
      }
    }

    return '';
  }

  String _artistFromBracketHeader(String line) {
    final match = RegExp(r'\[([^\]]+)\]').firstMatch(line);
    if (match == null) {
      return '';
    }

    final inner = match.group(1) ?? '';
    if (_containsHeaderKeyword(inner)) {
      return '';
    }

    final candidate = _cleanArtistCandidate(inner.split('/').first);
    return _looksLikeArtistCandidate(candidate) ? candidate : '';
  }

  bool _isBracketedSetlistHeader(String line) {
    final match = RegExp(r'\[([^\]]+)\]').firstMatch(line);
    if (match == null) {
      return false;
    }

    return _containsHeaderKeyword(match.group(1) ?? '');
  }

  String _artistFromCornerBrackets(String line) {
    final match = RegExp(r'《([^》]+)》').firstMatch(line);
    if (match == null) {
      return '';
    }

    final candidate = _cleanArtistCandidate(match.group(1) ?? '');
    return _looksLikeArtistCandidate(candidate) ? candidate : '';
  }

  String _artistFromHeaderHashtags(String line) {
    final matches = RegExp(r'#([^\s#]+)').allMatches(line).toList();
    if (matches.isEmpty) {
      return '';
    }

    final setlistIndex = line.toLowerCase().indexOf('setlist');
    final koreanSetlistIndex = line.indexOf(_kSetlist);
    final markerIndex = [setlistIndex, koreanSetlistIndex]
        .where((index) => index >= 0)
        .fold<int?>(null, (best, index) {
          if (best == null || index < best) {
            return index;
          }
          return best;
        });

    final candidates = matches
        .where((match) => markerIndex == null || match.start < markerIndex)
        .map((match) => match.group(1) ?? '')
        .where((tag) => !RegExp(r'^\d+$').hasMatch(tag))
        .where((tag) => !_isGenericArtistHashtag(tag))
        .toList();

    if (candidates.isEmpty) {
      return '';
    }

    final candidate = _cleanArtistCandidate(candidates.last);
    return _looksLikeArtistCandidate(candidate) ? candidate : '';
  }

  String _artistFromSingleHashtagLine(String line) {
    final match = RegExp(r'^#([^\s#]+)$').firstMatch(line.trim());
    if (match == null) {
      return '';
    }

    final tag = match.group(1) ?? '';
    if (RegExp(r'^\d+$').hasMatch(tag) || _isGenericArtistHashtag(tag)) {
      return '';
    }

    final candidate = _cleanArtistCandidate(tag);
    return _looksLikeArtistCandidate(candidate) ? candidate : '';
  }

  String _cleanArtistCandidate(String value) {
    return value
        .replaceAll(
          RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true),
          '',
        )
        .replaceAll(RegExp(r'[#\[\]《》]'), '')
        .replaceAll(RegExp(r'\b\d{6}\b|\b\d{8}\b'), ' ')
        .replaceAll(RegExp(r'\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isGenericArtistHashtag(String tag) {
    final normalized = tag.trim().replaceFirst('#', '').toLowerCase();
    return {
      'tdm',
      'todaydrawmusic',
      '\uC624\uB298\uC758\uD55C\uACE1',
      'setlist',
      '셋리스트',
      '버스킹',
      '공연',
      '콘서트',
      '라이브',
      '페스티벌',
      'festival',
      '영화제',
      '뷰민라',
      '무주산골영화제',
    }.contains(normalized);
  }

  String _cleanPastedHeaderArtist(String line) {
    if (_isBracketedSetlistHeader(line)) {
      return '';
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex >= 0) {
      final left = line.substring(0, colonIndex).trim();
      final right = _cleanArtistCandidate(line.substring(colonIndex + 1));
      if (_looksLikeEventHeader(left) && _looksLikeArtistCandidate(right)) {
        return right;
      }
    }

    final concertKeywordArtist = _artistFromConcertKeywordHeader(line);
    if (concertKeywordArtist.isNotEmpty) {
      return concertKeywordArtist;
    }

    final hasHeaderMarker =
        _containsDateLikeText(line) || _containsHeaderKeyword(line);

    if (!hasHeaderMarker) {
      return '';
    }

    final candidate = line
        .replaceAll(RegExp(r'\b\d{6}\b|\b\d{8}\b'), ' ')
        .replaceAll(RegExp(r'\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b'), ' ')
        .replaceAll(
          RegExp(
            '$_kSetlist|setlist|$_kConcert|$_kConcertKo|$_kLiveKo|live',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[_\-–—:/,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return _looksLikeArtistCandidate(candidate) ? candidate : '';
  }

  String _artistFromConcertKeywordHeader(String line) {
    final cleaned = _cleanArtistCandidate(line);
    final withoutSetlist = cleaned
        .replaceAll(RegExp('$_kSetlist|setlist', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final upper = withoutSetlist.toUpperCase();
    const englishKeywords = [
      'SNIPPET CONCERT',
      'BUSKING CONCERT',
      'CONCERT',
      'LIVE',
      'STAGE',
      'FESTIVAL',
      'SHOW',
    ];

    for (final keyword in englishKeywords) {
      final index = upper.indexOf(keyword);
      if (index < 0) {
        continue;
      }

      final before = _cleanArtistCandidate(withoutSetlist.substring(0, index));
      if (_looksLikeArtistCandidate(before)) {
        return before;
      }

      final after = _cleanArtistCandidate(
        withoutSetlist
            .substring(index + keyword.length)
            .replaceAll(
              RegExp(r'\bwith\s+friends\b', caseSensitive: false),
              '',
            ),
      );
      if (_looksLikeArtistCandidate(after)) {
        return after;
      }
    }

    for (final keyword in [_kConcert, _kConcertKo, _kLiveKo, '페스티벌']) {
      final index = withoutSetlist.indexOf(keyword);
      if (index < 0) {
        continue;
      }

      final before = _cleanArtistCandidate(withoutSetlist.substring(0, index));
      if (_looksLikeArtistCandidate(before)) {
        return before;
      }

      final after = _cleanArtistCandidate(
        withoutSetlist.substring(index + keyword.length),
      );
      if (_looksLikeArtistCandidate(after)) {
        return after;
      }
    }

    return '';
  }

  bool _isPastedMetaLine(String line, String inferredArtist, int lineIndex) {
    if (RegExp(r'^[=\-–—_\s]+$').hasMatch(line)) {
      return true;
    }

    if (_isTdmSharedListMetaLine(line)) {
      return true;
    }

    final emojiStrippedLine = _cleanArtistCandidate(line);
    final lowerLine = emojiStrippedLine.toLowerCase();
    if (lowerLine == 'setlist' || emojiStrippedLine == _kSetlist) {
      return true;
    }

    if (lineIndex <= 5 &&
        (_artistFromBracketHeader(line).isNotEmpty ||
            _isBracketedSetlistHeader(line))) {
      return true;
    }

    if (_artistFromSingleHashtagLine(line).isNotEmpty) {
      return true;
    }

    if (_containsDateLikeText(line) && _containsHeaderKeyword(line)) {
      return true;
    }

    if (lineIndex <= 5 &&
        (_looksLikeEventHeader(line) || _containsHeaderKeyword(line))) {
      return true;
    }

    if (lineIndex > 5) {
      return false;
    }

    final headerArtist = _cleanPastedHeaderArtist(line);
    if (headerArtist.isEmpty) {
      return false;
    }

    if (inferredArtist.trim().isEmpty) {
      return true;
    }

    return headerArtist.toLowerCase() == inferredArtist.trim().toLowerCase();
  }

  Song? _parsePastedSongLine(
    String line, {
    required bool hasInferredArtist,
    required bool forceArtistTitleOrder,
  }) {
    if (line.isEmpty || RegExp(r'^[=\-–—_\s]+$').hasMatch(line)) {
      return null;
    }

    final dashOrSlashMatch = RegExp(r'\s+(?:-|–|—|/)\s+').firstMatch(line);
    final commaMatch = dashOrSlashMatch == null
        ? RegExp(r'\s*,\s+').firstMatch(line)
        : null;
    final colonMatch = dashOrSlashMatch == null && commaMatch == null
        ? RegExp(r'\s*:\s+').firstMatch(line)
        : null;
    final separatorMatch = dashOrSlashMatch ?? commaMatch ?? colonMatch;
    if (separatorMatch == null) {
      return null;
    }

    final left = line.substring(0, separatorMatch.start).trim();
    final right = line.substring(separatorMatch.end).trim();
    if (left.isEmpty || right.isEmpty) {
      return null;
    }

    final knownArtists = _knownArtistNamesForPaste();
    final leftIsArtist = _matchesKnownArtist(left, knownArtists);
    final rightIsArtist = _matchesKnownArtist(right, knownArtists);
    final isColonSeparator = colonMatch != null;

    if (isColonSeparator && !leftIsArtist && !rightIsArtist) {
      return null;
    }

    if (hasInferredArtist && !leftIsArtist && !rightIsArtist) {
      return null;
    }

    final shouldReverse =
        !forceArtistTitleOrder && rightIsArtist && !leftIsArtist ||
        (!forceArtistTitleOrder &&
            !hasInferredArtist &&
            dashOrSlashMatch != null &&
            _looksLikePerformerCredit(right) &&
            !leftIsArtist &&
            !_looksLikeNumericArtistName(left));
    final artist = shouldReverse ? right : left;
    final title = shouldReverse ? left : right;

    if (artist.isEmpty || title.isEmpty) {
      return null;
    }

    return Song(artist: artist, title: title, tags: const []);
  }

  bool _looksLikePerformerCredit(String value) {
    final performer = value.trim();
    if (performer.isEmpty || performer.length > 24 || performer.contains(' ')) {
      return false;
    }

    if (performer == '듀엣') {
      return true;
    }

    final names = performer.split(RegExp(r'[&·]'));
    if (names.length > 1) {
      return names.every(_looksLikeKoreanPerformerName);
    }

    return _looksLikeKoreanPerformerName(performer);
  }

  bool _looksLikeKoreanPerformerName(String value) {
    final name = value.trim();
    return RegExp(r'^[가-힣]{3,4}$').hasMatch(name);
  }

  bool _looksLikeNumericArtistName(String value) {
    final candidate = value.trim();
    return RegExp(r'\d.*[A-Za-z가-힣]|[A-Za-z가-힣].*\d').hasMatch(candidate);
  }

  String? _parseTitleOnlyPastedLine(
    String line, {
    required bool allowSeparators,
  }) {
    if (line.isEmpty || RegExp(r'^[=\-–—_\s]+$').hasMatch(line)) {
      return null;
    }

    final lowerLine = line.toLowerCase();
    const blockedLines = {
      'setlist',
      _kEncoreSong,
      _kTodaySongs,
      _kEncore,
      'encore',
    };

    if (_isTdmSharedListMetaLine(line)) {
      return null;
    }

    if (blockedLines.contains(lowerLine) ||
        lowerLine.contains('setlist') ||
        line.contains(_kSetlist)) {
      return null;
    }

    if (!allowSeparators && RegExp(r'\s+(?:-|–|—|/|,)\s+').hasMatch(line)) {
      return null;
    }

    return line;
  }

  bool _isTdmSharedListMetaLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return true;
    }

    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty &&
        tokens.every((token) => token.startsWith('#') && token.length > 1)) {
      return true;
    }

    final cleaned = _cleanArtistCandidate(
      trimmed,
    ).toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return {
      '\uC120\uD0DD\uD55C\uACE1\uBAA9\uB85D',
      '\uC120\uD0DD\uACE1\uBAA9\uB85D',
      '\uC624\uB298\uC758\uD55C\uACE1',
      'tdm',
      'todaydrawmusic',
    }.contains(cleaned);
  }

  bool _containsDateLikeText(String value) {
    return RegExp(r'\b\d{6}\b|\b\d{8}\b').hasMatch(value) ||
        RegExp(r'\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b').hasMatch(value);
  }

  bool _containsHeaderKeyword(String value) {
    final lowerValue = value.toLowerCase();
    return lowerValue.contains('setlist') ||
        lowerValue.contains('live') ||
        lowerValue.contains('busking') ||
        value.contains(_kSetlist) ||
        value.contains(_kConcert) ||
        value.contains(_kConcertKo) ||
        value.contains(_kLiveKo) ||
        value.contains('버스킹') ||
        value.contains('영화제') ||
        value.contains('페스티벌');
  }

  bool _looksLikeEventHeader(String value) {
    final lowerValue = value.toLowerCase();
    return _containsDateLikeText(value) ||
        _containsHeaderKeyword(value) ||
        lowerValue.contains('stage') ||
        lowerValue.contains('festival') ||
        lowerValue.contains('concert') ||
        lowerValue.contains('road to') ||
        lowerValue.contains('busking') ||
        value.contains('영화제') ||
        value.contains('페스티벌') ||
        value.contains('부락') ||
        lowerValue.contains(' in ');
  }

  bool _looksLikeArtistCandidate(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || _isDateLikeValue(candidate)) {
      return false;
    }

    final lowerCandidate = candidate.toLowerCase();
    if (_containsHeaderKeyword(candidate) ||
        lowerCandidate.contains('stage') ||
        lowerCandidate.contains('festival') ||
        lowerCandidate.contains('concert')) {
      return false;
    }

    return candidate.length <= 30;
  }

  bool _isDateLikeValue(String value) {
    final compactValue = value.trim();
    return RegExp(r'^\d{6}$|^\d{8}$').hasMatch(compactValue) ||
        RegExp(r'^\d{4}[./-]\d{1,2}[./-]\d{1,2}$').hasMatch(compactValue) ||
        RegExp(r'^\d{4}\s+\d{1,2}\s+\d{1,2}$').hasMatch(compactValue);
  }

  Set<String> _knownArtistNamesForPaste() {
    return {
      ..._songs.map((song) => song.artist),
      ...sampleSongs.map((song) => song.artist),
      'N.Flying',
      '엔플라잉',
      'ONEWE',
      '원위',
      'Xdinary Heroes',
      '엑스디너리 히어로즈',
      'Touched',
      '터치드',
      '극동아시아타이거즈',
    }.map((artist) => artist.trim().toLowerCase()).toSet();
  }

  bool _matchesKnownArtist(String value, Set<String> knownArtists) {
    return knownArtists.contains(value.trim().toLowerCase());
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
            final compactButtonStyle = TextButton.styleFrom(
              minimumSize: const Size(40, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            );
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
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SegmentedButton<SongListSortMode>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: SongListSortMode.added,
                                      label: Text('\uCD94\uAC00\uC21C'),
                                    ),
                                    ButtonSegment(
                                      value: SongListSortMode.title,
                                      label: Text('\uACE1\uBA85\uC21C'),
                                    ),
                                  ],
                                  selected: {songSortMode},
                                  onSelectionChanged: (selection) {
                                    refreshDialog(() {
                                      songSortMode = selection.first;
                                    });
                                    resetSongListScroll();
                                  },
                                ),
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
                                final hasLink = _hasSongLink(song);

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
                                        onPressed: () =>
                                            _openSongLinkOrYoutube(song),
                                        style: compactButtonStyle,
                                        child: Text(
                                          _compactSongOpenButtonLabel(song),
                                          style: TextStyle(
                                            color: hasLink ? tdmLinkBlue : null,
                                            fontWeight: hasLink
                                                ? FontWeight.w800
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        tooltip:
                                            '\uC774 \uACE1 \uCD94\uCC9C\uD558\uAE30',
                                        onPressed: () =>
                                            _recommendSelectedSong(song),
                                        icon: const Icon(
                                          Icons.recommend_outlined,
                                          size: 18,
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: '\uAD00\uB9AC',
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _showEditSongDialog(
                                              song,
                                              onSongUpdated: () {
                                                if (dialogContext.mounted) {
                                                  refreshDialog(() {});
                                                }
                                                onSongChanged?.call();
                                              },
                                            );
                                          } else if (value == 'delete') {
                                            _showDeleteSongDialog(
                                              song,
                                              onDeleted: () {
                                                if (allArtistSongs.length ==
                                                        1 &&
                                                    dialogContext.mounted) {
                                                  Navigator.of(
                                                    dialogContext,
                                                  ).pop();
                                                }
                                                if (dialogContext.mounted) {
                                                  refreshDialog(() {});
                                                }
                                                onSongChanged?.call();
                                              },
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('\uC218\uC815'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('\uC0AD\uC81C'),
                                          ),
                                        ],
                                      ),
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
            final songs = _allSongsForOverview();
            final query = searchController.text;
            final visibleSongs = songs
                .where(
                  (song) =>
                      (!showFavoritesOnly || _isSongFavorite(song)) &&
                      _matchesSongSearch(song, query),
                )
                .toList();
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
                                    'all-songs-${_songDuplicateKey(song)}-$index',
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
                                        child: Text(
                                          '${song.artist} - ${song.title}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip:
                                            '\uD3EC\uD568\uB41C \uC138\uD2B8 \uBCF4\uAE30',
                                        icon: const Icon(
                                          Icons.folder_copy_outlined,
                                        ),
                                        onPressed: () =>
                                            _showSongIncludedSetsDialog(song),
                                      ),
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
      fileBaseName: 'today_music_set_${safeSetName}_$timestamp',
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
      fileBaseName: 'today_music_sets_${_exportTimestamp()}',
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

    showDialog<void>(
      context: context,
      builder: (detailContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            final songSet = _songSetById(setId);
            if (songSet == null) {
              return const AlertDialog(content: Text('세트를 찾을 수 없어요.'));
            }

            final songSetContentMaxHeight =
                MediaQuery.sizeOf(detailContext).height * 0.55;
            final songSetSongsCanScroll =
                songSet.songs.length * 46 >
                max(0, songSetContentMaxHeight - 34);

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
                      Text('${songSet.songs.length}곡'),
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
                              itemCount: songSet.songs.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 8),
                              itemBuilder: (context, index) {
                                final song = songSet.songs[index];
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${index + 1}. ${song.artist} - ${song.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    _favoriteSongIconButton(
                                      song,
                                      onChanged: () {
                                        if (detailContext.mounted) {
                                          refreshDialog(() {});
                                        }
                                        onChanged?.call();
                                      },
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip:
                                          '\uC774 \uACE1 \uCD94\uCC9C\uD558\uAE30',
                                      onPressed: () => _recommendSelectedSong(
                                        song,
                                        sourceSetName: songSet.name,
                                      ),
                                      icon: const Icon(
                                        Icons.recommend_outlined,
                                        size: 18,
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: '세트에서 제외',
                                      onPressed: () =>
                                          _showRemoveSingleSongFromSetDialog(
                                            songSet,
                                            song,
                                            onRemoved: () {
                                              _runAfterFrame(() {
                                                refreshDialog(() {});
                                                onChanged?.call();
                                              });
                                            },
                                          ),
                                      icon: const Icon(Icons.close, size: 18),
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
            final currentKeys = currentSet.songs.map(_songDuplicateKey).toSet();
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
                              final alreadyInSet = currentKeys.contains(
                                _songDuplicateKey(song),
                              );
                              final checked = selectedSongs.contains(song);

                              return CheckboxListTile(
                                key: ValueKey(
                                  'add-set-${_songDuplicateKey(song)}-$index',
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
                final removeKey = _songDuplicateKey(song);
                setState(() {
                  _songSets = _songSets
                      .map(
                        (set) => set.id == songSet.id
                            ? set.copyWith(
                                songs: set.songs
                                    .where(
                                      (setSong) =>
                                          _songDuplicateKey(setSong) !=
                                          removeKey,
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
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: randomControlDisabled
              ? Colors.grey.shade100
              : isRandomEnabled
              ? colorScheme.surfaceContainerHigh
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: randomControlDisabled
                ? Colors.grey.shade300
                : colorScheme.outlineVariant,
          ),
        ),
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
    );
  }
}

class SettingsDialog extends StatefulWidget {
  final String initialDefaultMessage;
  final ValueChanged<String> onSave;
  final VoidCallback onContactEmail;
  final VoidCallback onOpenOfficialX;
  final VoidCallback onResetSongs;

  const SettingsDialog({
    super.key,
    required this.initialDefaultMessage,
    required this.onSave,
    required this.onContactEmail,
    required this.onOpenOfficialX,
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
            OutlinedButton(
              onPressed: widget.onResetSongs,
              child: const Text('전체 곡 초기화'),
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
