import 'dart:convert';
import 'dart:math';

import 'song.dart';

enum PasteSongCandidateStatus { newSong, existing, needsReview }

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
        return '\uC0C8 \uACE1';
      case PasteSongCandidateStatus.existing:
        return '\uC774\uBBF8 \uC788\uC74C';
      case PasteSongCandidateStatus.needsReview:
        return '\uD655\uC778 \uD544\uC694';
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
  final List<PasteSongCandidate> candidates;

  const PasteSongAnalysis({
    required this.inferredArtist,
    required this.drafts,
    required this.candidates,
  });
}

class _ExplicitSetlistHeader {
  final int index;
  final String artist;

  const _ExplicitSetlistHeader({required this.index, required this.artist});
}

enum _PasteTableSection { none, number, name, album, ended }

const String _kSetlist = '\uC14B\uB9AC\uC2A4\uD2B8';
const String _kConcert = '\uACF5\uC5F0';
const String _kConcertKo = '\uCF58\uC11C\uD2B8';
const String _kLiveKo = '\uB77C\uC774\uBE0C';
const String _kEncoreSong = '\uC575\uCF5C\uACE1';
const String _kTodaySongs = '\uC624\uB298 \uB4E4\uC740 \uB178\uB798';
const String _kEncore = '\uC575\uCF5C';

PasteSongAnalysis parsePastedSongText({
  required String text,
  required List<Song> existingSongs,
  Iterable<Song> knownSongs = const [],
}) {
  final parser = _PasteSongParser(
    existingSongs: existingSongs,
    knownSongs: knownSongs,
  );
  return parser.parse(text);
}

List<PasteSongCandidate> buildPasteSongCandidates({
  required List<PasteSongDraft> drafts,
  required String inferredArtist,
  required List<Song> existingSongs,
}) {
  return _PasteSongParser(
    existingSongs: existingSongs,
    knownSongs: const [],
  ).buildCandidates(drafts, inferredArtist);
}

class _PasteSongParser {
  final List<Song> existingSongs;
  final Iterable<Song> knownSongs;

  const _PasteSongParser({
    required this.existingSongs,
    required this.knownSongs,
  });

  PasteSongAnalysis parse(String text) {
    final originalLines = _mergeNumberOnlyLines(
      const LineSplitter().convert(text),
    );
    final isStructuredTable = _isStructuredTable(originalLines);
    final explicitSetlistHeader = _findExplicitSetlistHeader(originalLines);
    final concertArtistHeader =
        explicitSetlistHeader == null && !isStructuredTable
        ? _findConcertArtistHeader(originalLines)
        : null;
    final tableLogoArtist = isStructuredTable
        ? _artistFromStructuredTableEvidence(originalLines)
        : '';
    final inferredArtist =
        explicitSetlistHeader?.artist ??
        (tableLogoArtist.isNotEmpty ? tableLogoArtist : null) ??
        concertArtistHeader?.artist ??
        _inferPastedArtist(text);
    var contentStartIndex = 0;
    if (explicitSetlistHeader != null) {
      contentStartIndex = explicitSetlistHeader.index + 1;
    } else if (concertArtistHeader != null) {
      final followingSetlistIndex = _findFollowingSetlistMarkerIndex(
        originalLines,
        concertArtistHeader.index + 1,
      );
      contentStartIndex =
          (followingSetlistIndex ?? concertArtistHeader.index) + 1;
    }
    final linesAfterHeader = originalLines.skip(contentStartIndex).toList();
    final mergedLines = _filterStructuredTableLines(linesAfterHeader);
    final stripOcrNumberNoise = _hasRepeatedOcrNumberNoise(mergedLines);
    final drafts = <PasteSongDraft>[];
    var lineIndex = 0;

    for (final rawLine in mergedLines) {
      final rawTrimmedLine = rawLine.trim();
      if (rawTrimmedLine.isEmpty) {
        lineIndex++;
        continue;
      }

      final hasListNumber = _hasExplicitListNumber(rawTrimmedLine);
      if (_isPastedMetaLine(
        rawTrimmedLine,
        inferredArtist,
        lineIndex,
        totalLineCount: mergedLines.length,
        isNumberedSongLine: hasListNumber,
        isStructuredTableSongLine: isStructuredTable,
      )) {
        lineIndex++;
        continue;
      }

      final isNumberedArtistTitleLine = _isHashNumberedArtistTitleLine(
        rawTrimmedLine,
      );
      final cleanedLine = _cleanPastedSongLine(
        rawLine,
        stripOcrNumberNoise: stripOcrNumberNoise,
      );
      if (cleanedLine.isEmpty) {
        lineIndex++;
        continue;
      }

      if (_isPastedMetaLine(
        cleanedLine,
        inferredArtist,
        lineIndex,
        totalLineCount: mergedLines.length,
        isNumberedSongLine: hasListNumber,
        isStructuredTableSongLine: isStructuredTable,
      )) {
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

    final candidates = buildCandidates(drafts, inferredArtist);
    return PasteSongAnalysis(
      inferredArtist: inferredArtist,
      drafts: drafts,
      candidates: candidates,
    );
  }

  List<PasteSongCandidate> buildCandidates(
    List<PasteSongDraft> drafts,
    String inferredArtist,
  ) {
    final candidates = <PasteSongCandidate>[];
    final existingKeys = existingSongs.map(_songDuplicateKey).toSet();
    final existingNormalizedKeys = existingSongs
        .map(_pasteSongDuplicateKey)
        .toSet();
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

  String _inferPastedArtist(String text) {
    final lines = const LineSplitter()
        .convert(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !_isTdmSharedListMetaLine(line))
        .toList();
    final explicitHeader = _findExplicitSetlistHeader(lines);
    if (explicitHeader != null) {
      return explicitHeader.artist;
    }

    final isStructuredTable = _isStructuredTable(lines);
    if (isStructuredTable) {
      final tableLogoArtist = _artistFromStructuredTableEvidence(lines);
      if (tableLogoArtist.isNotEmpty) {
        return tableLogoArtist;
      }
      return '';
    }

    if (!isStructuredTable) {
      for (final line in lines) {
        final concertArtist = _artistFromConcertKeywordHeader(line);
        if (concertArtist.isNotEmpty) {
          return concertArtist;
        }
      }
    }

    final logoArtist = _artistFromTrailingLogo(lines);
    if (logoArtist.isNotEmpty) {
      return logoArtist;
    }

    final topLines = lines.take(5).toList();

    for (final line in topLines) {
      final setlistArtist = _artistFromSetlistHeader(line);
      if (setlistArtist.isNotEmpty) {
        return setlistArtist;
      }
    }

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

    if (lines.any(_isStandaloneSetlistLine)) {
      return '';
    }

    return '';
  }

  _ExplicitSetlistHeader? _findExplicitSetlistHeader(List<String> lines) {
    for (var index = 0; index < lines.length; index++) {
      final artist = _artistFromSetlistHeader(lines[index]);
      if (artist.isNotEmpty) {
        return _ExplicitSetlistHeader(index: index, artist: artist);
      }
    }
    return null;
  }

  _ExplicitSetlistHeader? _findConcertArtistHeader(List<String> lines) {
    for (var index = 0; index < lines.length; index++) {
      final artist = _artistFromConcertKeywordHeader(lines[index]);
      if (artist.isNotEmpty) {
        return _ExplicitSetlistHeader(index: index, artist: artist);
      }
    }
    return null;
  }

  int? _findFollowingSetlistMarkerIndex(List<String> lines, int startIndex) {
    for (var index = startIndex; index < lines.length; index++) {
      if (_containsSetlistMarker(lines[index])) {
        return index;
      }
    }
    return null;
  }

  bool _containsSetlistMarker(String line) {
    return RegExp(
      r'(?:\uC14B\uB9AC\uC2A4\uD2B8|set\s*list)',
      caseSensitive: false,
    ).hasMatch(line);
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

  String _cleanPastedSongLine(
    String rawLine, {
    bool stripOcrNumberNoise = false,
  }) {
    var line = rawLine.trim().replaceAll(RegExp(r'\s+'), ' ');
    line = line.replaceFirst(RegExp(r'^#\d+\s+(?=.*\s(?:-|–|—|/)\s)'), '');
    line = line.replaceFirst(RegExp(r'^[+\-*•]\s*'), '');
    line = line.replaceFirst(RegExp(r'^\d+\s*(?:[.)\uFF0E]\s*|[-:]\s*)'), '');
    line = line.replaceFirst(RegExp(r'^[①-⑳]\s*'), '');
    if (stripOcrNumberNoise && !_looksLikeNumericSongTitle(line)) {
      line = line.replaceFirst(RegExp(r'^(?:[O0@]|\d{1,2})\s+(?=\S)'), '');
    }
    line = _stripPerformanceSuffix(line);
    line = _unwrapWholeLineParentheses(line);
    line = line.replaceFirst(RegExp(r'^[+\-*•]\s*'), '');
    return line
        .replaceAll(RegExp(r'''["“”‘’]'''), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeNumericSongTitle(String value) {
    return RegExp(
      r'^\d+\s*(?:\uBD84|\uC2DC\uAC04|\uC6D4|days?\b|years?\b)',
      caseSensitive: false,
    ).hasMatch(value.trim());
  }

  bool _isHashNumberedArtistTitleLine(String line) {
    return RegExp(r'^#\d+\s+.+\s(?:-|–|—|/)\s.+$').hasMatch(line.trim());
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
      '\uC14B\uB9AC\uC2A4\uD2B8',
      '\uBC84\uC2A4\uD0B9',
      '\uACF5\uC5F0',
      '\uCF58\uC11C\uD2B8',
      '\uB77C\uC774\uBE0C',
      '\uD398\uC2A4\uD2F0\uBC8C',
      'festival',
      '\uC601\uD654\uC81C',
      '\uBE44\uB514\uC624',
      '\uBB34\uC8FC\uC0B0\uACE8\uC601\uD654\uC81C',
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

    final decoratedHeaderArtist = _artistFromDecoratedEventHeader(line);
    if (decoratedHeaderArtist.isNotEmpty) {
      return decoratedHeaderArtist;
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

  String _artistFromDecoratedEventHeader(String line) {
    final cleaned = _cleanArtistCandidate(line);
    if (!_looksLikeEventHeader(cleaned)) {
      return '';
    }

    return _cleanDecoratedEventArtistCandidate(cleaned);
  }

  String _artistFromConcertKeywordHeader(String line) {
    final cleaned = _cleanArtistCandidate(line);
    final knownArtist = _knownArtistContainedIn(cleaned);
    if (knownArtist.isNotEmpty && _containsConcertArtistMarker(cleaned)) {
      return knownArtist;
    }

    final withoutSetlist = cleaned
        .replaceAll(RegExp('$_kSetlist|setlist', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final upper = withoutSetlist.toUpperCase();
    const englishKeywords = [
      'SNIPPET CONCERT',
      'BUSKING CONCERT',
      'ARENA TOUR',
      'HALL TOUR',
      'SHOWCASE',
      'TOUR',
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

      final before = _cleanDecoratedEventArtistCandidate(
        withoutSetlist.substring(0, index),
      );
      if (_looksLikeArtistCandidate(before)) {
        return before;
      }

      if (keyword == 'LIVE') {
        continue;
      }

      final after = _cleanDecoratedEventArtistCandidate(
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

    for (final keyword in [
      _kConcert,
      _kConcertKo,
      _kLiveKo,
      '\uD398\uC2A4\uD2F0\uBC8C',
    ]) {
      final index = withoutSetlist.indexOf(keyword);
      if (index < 0) {
        continue;
      }
      if (keyword == '\uD398\uC2A4\uD2F0\uBC8C' && knownArtist.isEmpty) {
        continue;
      }

      final before = _cleanDecoratedEventArtistCandidate(
        withoutSetlist.substring(0, index),
      );
      if (_looksLikeArtistCandidate(before)) {
        return before;
      }

      final after = _cleanDecoratedEventArtistCandidate(
        withoutSetlist.substring(index + keyword.length),
      );
      if (_looksLikeArtistCandidate(after)) {
        return after;
      }
    }

    return '';
  }

  bool _containsConcertArtistMarker(String value) {
    final lower = value.toLowerCase();
    return lower.contains('concert') ||
        lower.contains('live') ||
        lower.contains('tour') ||
        lower.contains('showcase') ||
        value.contains(_kConcert) ||
        value.contains(_kConcertKo) ||
        value.contains(_kLiveKo);
  }

  String _knownArtistContainedIn(String value) {
    final lowerValue = value.toLowerCase();
    final artists =
        {
            ...existingSongs.map((song) => song.artist),
            ...knownSongs.map((song) => song.artist),
          }.where((artist) => artist.trim().length >= 2).toList()
          ..sort((left, right) => right.length.compareTo(left.length));

    for (final artist in artists) {
      if (lowerValue.contains(artist.trim().toLowerCase())) {
        return artist.trim();
      }
    }
    return '';
  }

  String _cleanDecoratedEventArtistCandidate(String value) {
    var candidate = _cleanArtistCandidate(value);
    candidate = candidate
        .replaceAll(RegExp(r'\b\d{4}\b'), ' ')
        .replaceAll(RegExp(r'\bday\s*\d+\b', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(r'\bin\s+(?:seoul|tokyo|busan)\b', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(?:ocr|test|live|tour|concert|festival|fest|showcase|arena|hall|stage|busan|seoul|tokyo)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'(?:\uC18C\uADF9\uC7A5|\uACF5\uC5F0\uC7A5|\uCCB4\uC721\uAD00)',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[_\-–—:/,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return _looksLikeDecoratedEventArtistCandidate(candidate) ? candidate : '';
  }

  bool _looksLikeDecoratedEventArtistCandidate(String value) {
    final candidate = value.trim();
    if (!_looksLikeArtistCandidate(candidate) ||
        _containsInstitutionOrEventOnlyKeyword(candidate) ||
        _isWeekdayOrPerformanceRound(candidate)) {
      return false;
    }

    final normalized = candidate.toLowerCase().replaceAll(
      RegExp(r'[\s._\-]+'),
      '',
    );
    const blocked = {
      'awesome',
      'music',
      'tdm',
      'tdmmusic',
      'todaymusic',
      'todaydrawmusic',
    };
    if (blocked.contains(normalized)) {
      return false;
    }

    if (candidate.split(RegExp(r'\s+')).length > 2) {
      return false;
    }

    return RegExp(r'[A-Za-z가-힣ぁ-んァ-ヶ一-龯々]').hasMatch(candidate);
  }

  String _artistFromTrailingLogo(List<String> lines) {
    final meaningful = lines
        .asMap()
        .entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList();
    if (meaningful.isEmpty) {
      return '';
    }

    final tail = meaningful.skip(max(0, meaningful.length - 6)).toList();
    final logoCandidates = tail
        .map((entry) => _cleanArtistCandidate(entry.value))
        .where(_looksLikeLogoArtistToken)
        .toList();

    for (var index = 0; index < logoCandidates.length - 1; index++) {
      final first = _normalizeLogoToken(logoCandidates[index]);
      final second = _normalizeLogoToken(logoCandidates[index + 1]);
      if (first.length >= 2 &&
          second.length >= 4 &&
          (second.startsWith(first) || first.startsWith(second))) {
        return logoCandidates[index + 1];
      }
    }

    for (final candidate in logoCandidates.reversed) {
      final knownArtist = _knownArtistContainedIn(candidate);
      if (knownArtist.isNotEmpty &&
          _normalizeLogoToken(candidate).length >= 4) {
        return knownArtist;
      }

      final normalized = _normalizeLogoToken(candidate);
      if (normalized.length >= 3 &&
          lines.any(
            (line) =>
                _normalizeLogoToken(line).startsWith(normalized) &&
                _normalizeLogoToken(line).length > normalized.length,
          )) {
        return candidate;
      }
    }

    final allLogoCandidates = meaningful
        .map((entry) => _cleanArtistCandidate(entry.value))
        .where(_looksLikeLogoArtistToken)
        .toList();
    for (final candidate in allLogoCandidates.reversed) {
      final normalized = _normalizeLogoToken(candidate);
      if (normalized.length < 3 || normalized.length > 8) {
        continue;
      }
      final hasSupportingBrand = lines.any((line) {
        final lineToken = _normalizeLogoToken(
          line.replaceFirst(RegExp(r'^\s*\d{4}\s*'), ''),
        );
        return lineToken.length > normalized.length &&
            lineToken.startsWith(normalized) &&
            lineToken.length <= normalized.length + 8;
      });
      if (hasSupportingBrand) {
        return candidate;
      }
    }

    return '';
  }

  String _artistFromStructuredTableEvidence(List<String> lines) {
    final outsideLines = <String>[];
    final possibleLogoLines = <String>[];
    var section = _PasteTableSection.none;
    var hasEnteredTable = false;

    for (final line in lines) {
      final trimmed = line.trim();
      final header = trimmed.toLowerCase();
      if (header == 'num') {
        hasEnteredTable = true;
        section = _PasteTableSection.number;
        continue;
      }
      if (header == 'name') {
        hasEnteredTable = true;
        section = _PasteTableSection.name;
        continue;
      }
      if (header == 'album') {
        hasEnteredTable = true;
        section = _PasteTableSection.album;
        continue;
      }
      if (header == 'end' || header.startsWith('total')) {
        section = _PasteTableSection.ended;
        continue;
      }

      if (!hasEnteredTable || section == _PasteTableSection.none) {
        outsideLines.add(line);
        continue;
      }

      if (section == _PasteTableSection.number &&
          RegExp(r'^\d{4}\s+\S').hasMatch(trimmed)) {
        outsideLines.add(line);
        continue;
      }

      if (int.tryParse(trimmed) == null &&
          _looksLikeLogoArtistToken(_cleanArtistCandidate(trimmed))) {
        possibleLogoLines.add(line);
      }
      if (section == _PasteTableSection.ended &&
          !_isDateOrStructuredInfoLine(trimmed) &&
          !_isStandalonePerformanceMetaLine(trimmed)) {
        outsideLines.add(line);
      }
    }

    for (final line in outsideLines) {
      final artist = _artistFromConcertKeywordHeader(line);
      if (artist.isNotEmpty) {
        return artist;
      }
    }

    final brandSupported = _artistFromBrandSupportedLogo(
      outsideLines,
      possibleLogoLines,
    );
    if (brandSupported.isNotEmpty) {
      return brandSupported;
    }

    return _artistFromTrailingLogo(outsideLines);
  }

  String _artistFromBrandSupportedLogo(
    List<String> brandLines,
    List<String> logoLines,
  ) {
    for (final line in logoLines.reversed) {
      final candidate = _cleanArtistCandidate(line);
      final normalized = _normalizeLogoToken(candidate);
      if (normalized.length < 2 || normalized.length > 8) {
        continue;
      }
      final hasSupportingBrand = brandLines.any((brandLine) {
        final brand = _normalizeLogoToken(
          brandLine.replaceFirst(RegExp(r'^\s*\d{4}\s*'), ''),
        );
        return brand.length > normalized.length &&
            brand.startsWith(normalized) &&
            brand.length <= normalized.length + 8;
      });
      if (hasSupportingBrand) {
        return candidate;
      }
    }
    return '';
  }

  bool _looksLikeLogoArtistToken(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty ||
        candidate.contains(RegExp(r'\s')) ||
        candidate.length > 20 ||
        _containsInstitutionOrEventOnlyKeyword(candidate) ||
        _isStandalonePerformanceMetaLine(candidate)) {
      return false;
    }
    return RegExp(r'^[A-Za-z가-힣][A-Za-z0-9가-힣._-]*$').hasMatch(candidate);
  }

  String _normalizeLogoToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9가-힣]'), '');
  }

  bool _isPastedMetaLine(
    String line,
    String inferredArtist,
    int lineIndex, {
    int? totalLineCount,
    bool isNumberedSongLine = false,
    bool isStructuredTableSongLine = false,
  }) {
    if (RegExp(r'^[=\-–—_\s]+$').hasMatch(line)) {
      return true;
    }

    if (_isTdmSharedListMetaLine(line)) {
      return true;
    }

    if (_isDateOrStructuredInfoLine(line) ||
        _isTableOrReceiptHeader(line) ||
        _isNarrativeNoiseLine(line)) {
      return true;
    }

    if (!isNumberedSongLine && _isStandalonePerformanceMetaLine(line)) {
      return true;
    }

    if (_isSocialAccountMetaLine(line, lineIndex, totalLineCount)) {
      return true;
    }

    if (_isTrailingArtistLogoLine(
      line,
      inferredArtist,
      lineIndex,
      totalLineCount,
    )) {
      return true;
    }

    if (!isNumberedSongLine &&
        (_containsInstitutionOrEventOnlyKeyword(line) ||
            RegExp(r'^\d{1,3}$').hasMatch(line.trim()))) {
      return true;
    }

    if (_isNoisyOcrMetaFragment(line)) {
      return true;
    }

    if (isStructuredTableSongLine) {
      return false;
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

  bool _hasExplicitListNumber(String line) {
    return RegExp(r'^\s*\d{1,3}\s*(?:[.)．]\s*|[-:]\s*)').hasMatch(line);
  }

  bool _isStandaloneSetlistLine(String line) {
    final normalized = line.trim().toLowerCase().replaceAll(
      RegExp(r'[\s._\-\[\]<>《》]+'),
      '',
    );
    return normalized == 'setlist' || normalized == _kSetlist;
  }

  bool _isStandalonePerformanceMetaLine(String line) {
    final normalized = line.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return normalized == 'mc' ||
        normalized == 'm.c.' ||
        normalized == 'stage' ||
        normalized == 'plaintext' ||
        normalized == 'openingvcr' ||
        normalized == 'opningvcr' ||
        normalized == 'ment' ||
        normalized == 'bandtime' ||
        normalized == 'dancertime' ||
        normalized == 're-encore' ||
        normalized == 'reencore' ||
        normalized == 'onandon' ||
        normalized == 'on:andon' ||
        normalized == 'ai\uB85C\uC0DD\uC131\uD55C\uCF58\uD150\uCE20' ||
        normalized == 'a\uB85C\uC0DD\uC131\uD55C\uCF58\uD150\uCE20' ||
        RegExp(r'^\uC575\uCF5C\d*$').hasMatch(normalized) ||
        RegExp(r'^encore\d*$').hasMatch(normalized);
  }

  bool _isDateOrStructuredInfoLine(String line) {
    final trimmed = line.trim();
    final lower = trimmed.toLowerCase();
    if (RegExp(
      r'^\d{4}\s*[./-]\s*\d{1,2}\s*[./-]\s*\d{1,2}(?:\s*[.]|\s*.*)?$',
    ).hasMatch(trimmed)) {
      return true;
    }
    if (RegExp(
      r'^\d{4}\s*[.]\s*\d{1,2}\s*[.]\s*\d{1,2}\s*[.]?\s*-\s*\d{4}',
    ).hasMatch(trimmed)) {
      return true;
    }
    return RegExp(
      r'^(?:date|address|total|end)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  bool _isTableOrReceiptHeader(String line) {
    final normalized = line.trim().toLowerCase();
    return {'num', 'date', 'address', 'total', 'end'}.contains(normalized);
  }

  bool _isNarrativeNoiseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.length < 45) {
      return false;
    }
    final punctuationCount = RegExp(r'[.!?。！？]').allMatches(trimmed).length;
    final koreanSentenceEnding = RegExp(
      r'(?:\uC694|\uB2E4|\uC2B5\uB2C8\uB2E4|\uD574\uC694)[.!?]?$',
    ).hasMatch(trimmed);
    return punctuationCount >= 2 || koreanSentenceEnding;
  }

  bool _hasRepeatedOcrNumberNoise(List<String> lines) {
    var matches = 0;
    for (final line in lines) {
      if (RegExp(r'^(?:[O0@]|\d{1,2})\s+\S').hasMatch(line.trim())) {
        matches++;
      }
    }
    return matches >= 2;
  }

  List<String> _filterStructuredTableLines(List<String> lines) {
    if (!_isStructuredTable(lines)) {
      return lines;
    }

    final filtered = <String>[];
    var section = _PasteTableSection.none;
    final sectionNumbers = <int>[];
    var expectedSongCount = 0;
    var collectedSongCount = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      final header = trimmed.toLowerCase();
      if (header == 'num') {
        section = _PasteTableSection.number;
        sectionNumbers.clear();
        expectedSongCount = 0;
        collectedSongCount = 0;
        continue;
      }
      if (header == 'name') {
        section = _PasteTableSection.name;
        expectedSongCount = _expectedSongCountFromNumbers(sectionNumbers);
        collectedSongCount = 0;
        continue;
      }
      if (header == 'album') {
        section = _PasteTableSection.album;
        continue;
      }
      if (header == 'end' || header.startsWith('total')) {
        section = _PasteTableSection.ended;
        continue;
      }

      if (section == _PasteTableSection.number) {
        final number = int.tryParse(trimmed);
        if (number != null && number > 0 && number <= 200) {
          sectionNumbers.add(number);
        }
        continue;
      }

      if (section == _PasteTableSection.name) {
        if (_isStandalonePerformanceMetaLine(trimmed) ||
            _isDateOrStructuredInfoLine(trimmed) ||
            _isNarrativeNoiseLine(trimmed)) {
          continue;
        }
        if (_isParentheticalEnglishSubtitle(trimmed) &&
            filtered.isNotEmpty &&
            _looksLikeEnglishTitleAbbreviation(filtered.last) &&
            _isNaturalAbbreviationExpansion(filtered.last, trimmed)) {
          filtered[filtered.length - 1] =
              '${_normalizeEnglishTitleAbbreviation(filtered.last)} $trimmed';
        } else {
          filtered.add(
            _looksLikeEnglishTitleAbbreviation(trimmed)
                ? _normalizeEnglishTitleAbbreviation(trimmed)
                : line,
          );
          collectedSongCount++;
          if (expectedSongCount > 0 &&
              collectedSongCount >= expectedSongCount) {
            section = _PasteTableSection.ended;
          }
        }
      }
    }
    return filtered;
  }

  bool _isStructuredTable(List<String> lines) {
    final normalized = lines.map((line) => line.trim().toLowerCase()).toList();
    return normalized.contains('num') &&
        normalized.contains('name') &&
        normalized.contains('album');
  }

  int _expectedSongCountFromNumbers(List<int> numbers) {
    if (numbers.length < 5) {
      return 0;
    }
    final minimum = numbers.reduce(min);
    final maximum = numbers.reduce(max);
    final rangeCount = maximum - minimum + 1;
    return max(numbers.length, rangeCount);
  }

  bool _looksLikeEnglishTitleAbbreviation(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^(?:[A-Za-z0]\.){2,}[A-Za-z0]?$').hasMatch(compact) ||
        RegExp(r'^[A-Za-z](?:&[A-Za-z])+$').hasMatch(compact);
  }

  String _normalizeEnglishTitleAbbreviation(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^(?:[A-Za-z0]\.){2,}[A-Za-z0]?$').hasMatch(compact)
        ? compact.replaceAll('0', 'O')
        : value.trim();
  }

  bool _isParentheticalEnglishSubtitle(String value) {
    final match = RegExp(r'^\(([^()]+)\)$').firstMatch(value.trim());
    if (match == null) {
      return false;
    }
    final subtitle = match.group(1) ?? '';
    return RegExp(r'[A-Za-z]').hasMatch(subtitle) &&
        !RegExp(r'[가-힣ぁ-んァ-ヶ一-龯々]').hasMatch(subtitle);
  }

  bool _isNaturalAbbreviationExpansion(
    String abbreviation,
    String parentheticalSubtitle,
  ) {
    final abbreviationLetters = abbreviation
        .replaceAll(RegExp(r'[^A-Za-z]'), '')
        .toLowerCase();
    final subtitle = parentheticalSubtitle
        .replaceFirst(RegExp(r'^\('), '')
        .replaceFirst(RegExp(r'\)$'), '');
    final wordInitials = RegExp(r"[A-Za-z]+")
        .allMatches(subtitle)
        .map((match) => match.group(0)![0].toLowerCase())
        .join();
    return abbreviationLetters.length >= 2 &&
        abbreviationLetters == wordInitials;
  }

  bool _isSocialAccountMetaLine(
    String line,
    int lineIndex,
    int? totalLineCount,
  ) {
    final trimmed = line.trim();
    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^@[A-Za-z0-9._-]+$').hasMatch(trimmed)) {
      return true;
    }

    if (totalLineCount == null || totalLineCount <= 0) {
      return false;
    }

    final isNearEnd = lineIndex >= totalLineCount - 3;
    if (!isNearEnd ||
        !RegExp(r'^[O0][A-Za-z0-9._-]{3,24}$').hasMatch(compact)) {
      return false;
    }

    final lower = compact.toLowerCase();
    const accountSuffixes = ['note', 'official', 'update', 'fan', 'archive'];
    if (!accountSuffixes.any(lower.endsWith)) {
      return false;
    }

    final knownArtists = _knownArtistNamesForPaste();
    return !_matchesKnownArtist(compact, knownArtists);
  }

  bool _isTrailingArtistLogoLine(
    String line,
    String inferredArtist,
    int lineIndex,
    int? totalLineCount,
  ) {
    if (inferredArtist.trim().isEmpty ||
        totalLineCount == null ||
        lineIndex < totalLineCount - 4) {
      return false;
    }
    final lineToken = _normalizeLogoToken(line);
    final artistToken = _normalizeLogoToken(inferredArtist);
    return lineToken.length >= 2 &&
        (lineToken == artistToken ||
            artistToken.startsWith(lineToken) ||
            lineToken.startsWith(artistToken));
  }

  bool _looksLikePerformerCredit(String value) {
    final performer = value.trim();
    if (performer.isEmpty || performer.length > 24 || performer.contains(' ')) {
      return false;
    }

    if (performer == '\uC548\uC608\uC740') {
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

  bool _isTdmSharedListMetaLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return true;
    }

    if (trimmed.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') == 'plain text') {
      return true;
    }

    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty &&
        tokens.every((token) => token.startsWith('#') && token.length > 1)) {
      return true;
    }

    final cleaned = _cleanArtistCandidate(
      trimmed,
    ).toLowerCase().replaceAll(RegExp(r"[\s'’.\[\]ㅋ♪]+"), '');
    return {
      '\uC120\uD0DD\uD55C\uACE1\uBAA9\uB85D',
      '\uC120\uD0DD\uACE1\uBAA9\uB85D',
      '\uC624\uB298\uC758\uD55C\uACE1',
      '\uC624\uB298\uC758\uC14B\uB9AC\uC2A4\uD2B8',
      '\uC624\uB298\uC758\uC14B\uB9AC\uC2A4\uD2B8\uB2E4\uC2DC\uB4E3\uAE30',
      'todayssetlist',
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
        lowerValue.contains('tour') ||
        lowerValue.contains('arena') ||
        lowerValue.contains('hall') ||
        lowerValue.contains('showcase') ||
        lowerValue.contains('fest') ||
        lowerValue.contains('busking') ||
        value.contains(_kSetlist) ||
        value.contains(_kConcert) ||
        value.contains(_kConcertKo) ||
        value.contains(_kLiveKo) ||
        value.contains('\uBC84\uC2A4\uD0B9') ||
        value.contains('\uC601\uD654\uC81C') ||
        value.contains('\uD398\uC2A4\uD2F0\uBC8C') ||
        value.contains('\uBC15\uB78C\uD68C') ||
        value.contains('\uCD95\uC81C') ||
        value.contains('\uD53C\uD06C\uB2C9') ||
        value.contains('\uBB38\uD654\uD589\uC0AC');
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
        value.contains('\uC601\uD654\uC81C') ||
        value.contains('\uD398\uC2A4\uD2F0\uBC8C') ||
        value.contains('\uBC15\uB78C\uD68C') ||
        value.contains('\uCD95\uC81C') ||
        value.contains('\uD53C\uD06C\uB2C9') ||
        value.contains('\uBB38\uD654\uD589\uC0AC') ||
        value.contains('\uBD80\uC0B0') ||
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

  List<String> _mergeNumberOnlyLines(List<String> lines) {
    final merged = <String>[];
    for (var index = 0; index < lines.length; index++) {
      final current = lines[index];
      final trimmed = current.trim();
      if (_isStandaloneListNumberLine(trimmed)) {
        var nextIndex = index + 1;
        String? nextLine;
        while (nextIndex < lines.length) {
          final candidate = lines[nextIndex].trim();
          if (candidate.isNotEmpty) {
            nextLine = candidate;
            break;
          }
          nextIndex++;
        }
        if (nextLine != null &&
            !_hasExplicitListNumber(nextLine) &&
            !_isPastedMetaLine(nextLine, '', nextIndex)) {
          merged.add('$trimmed $nextLine');
          index = nextIndex;
        }
        continue;
      }
      merged.add(current);
    }
    return merged;
  }

  bool _isStandaloneListNumberLine(String line) {
    return RegExp(r'^\d+\s*[.)．:]$').hasMatch(line.trim());
  }

  String _artistFromSetlistHeader(String line) {
    if (_isTdmSharedListMetaLine(line) || _isStandaloneSetlistLine(line)) {
      return '';
    }
    final match = RegExp(
      r'(.+?)\s+(?:셋리스트|set\s*list)(?:\s*[^A-Za-z가-힣]*)?$',
      caseSensitive: false,
    ).firstMatch(line.trim());
    if (match == null) {
      return '';
    }
    final prefix = (match.group(1) ?? '')
        .replaceAll(
          RegExp(r'''<|>|\[|\]|《|》|["“”'‘’][^"“”'‘’]*["“”'‘’]'''),
          ' ',
        )
        .replaceAll(RegExp(r'\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b'), ' ')
        .replaceAll(RegExp(r'\b\d{4}\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final knownArtist = _knownArtistContainedIn(prefix);
    if (knownArtist.isNotEmpty) {
      return knownArtist;
    }

    if (_isWeekdayOrPerformanceRound(prefix) ||
        _containsInstitutionOrEventOnlyKeyword(prefix)) {
      final eventMarker = RegExp(
        r'(?:대축제|축제|페스티벌|festival|fest|박람회|concert|콘서트|공연)',
        caseSensitive: false,
      ).allMatches(prefix).toList();
      if (eventMarker.isEmpty) {
        return '';
      }
      final suffix = _cleanArtistCandidate(
        prefix.substring(eventMarker.last.end),
      );
      return _looksLikeStrongArtistName(suffix) ? suffix : '';
    }

    final candidate = _cleanArtistCandidate(prefix);
    return _looksLikeStrongArtistName(candidate) ? candidate : '';
  }

  bool _looksLikeStrongArtistName(String value) {
    final candidate = value.trim();
    return _looksLikeArtistCandidate(candidate) &&
        !_containsInstitutionOrEventOnlyKeyword(candidate) &&
        !_isWeekdayOrPerformanceRound(candidate) &&
        !RegExp(r'^\d+$').hasMatch(candidate);
  }

  bool _isWeekdayOrPerformanceRound(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    return {
          '\uC6D4\uC694\uC77C',
          '\uD654\uC694\uC77C',
          '\uC218\uC694\uC77C',
          '\uBAA9\uC694\uC77C',
          '\uAE08\uC694\uC77C',
          '\uD1A0\uC694\uC77C',
          '\uC77C\uC694\uC77C',
        }.contains(normalized) ||
        RegExp(r'^day\d+$').hasMatch(normalized);
  }

  bool _containsInstitutionOrEventOnlyKeyword(String value) {
    final lower = value.toLowerCase();
    return value.contains('\uB300\uD559\uAD50') ||
        value.contains('\uB300\uD559') ||
        value.contains('\uD559\uAD50') ||
        value.contains('\uACE0\uB4F1\uD559\uAD50') ||
        value.contains('\uBB38\uD654\uBE44\uCD95\uAE30\uC9C0') ||
        value.contains('\uCCB4\uC721\uAD00') ||
        value.contains('\uACF5\uC5F0\uC7A5') ||
        value.contains('\uC704\uC6D0\uD68C') ||
        value.contains('\uBC15\uB78C\uD68C') ||
        value.contains('\uB300\uCD95\uC81C') ||
        value.contains('\uCD95\uC81C') ||
        value.contains('\uD398\uC2A4\uD2F0\uBC8C') ||
        value.contains('\uD53C\uD06C\uB2C9') ||
        lower.contains('festival') ||
        lower.contains('fest') ||
        lower.contains('stage');
  }

  String _stripPerformanceSuffix(String value) {
    return value
        .replaceFirst(
          RegExp(r'\s*-\s*(?:앵콜\d*|한번 더|encore\d*)\s*$', caseSensitive: false),
          '',
        )
        .trim();
  }

  String _unwrapWholeLineParentheses(String value) {
    final trimmed = value.trim();
    final match = RegExp(r'^\(([^()]+)\)$').firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    return (match.group(1) ?? '').trim();
  }

  bool _isNoisyOcrMetaFragment(String line) {
    final candidate = line.trim();
    if (RegExp(r'^(?:[A-Za-z]\.){2,}[A-Za-z]?$').hasMatch(candidate)) {
      return false;
    }
    if (RegExp(r'^\d+\)$').hasMatch(candidate)) {
      return true;
    }
    if (candidate.contains(RegExp(r'\s')) ||
        candidate.contains('(') ||
        candidate.contains(')')) {
      return false;
    }
    return _hasHighSymbolRatio(candidate) && candidate.length <= 12;
  }

  bool _hasHighSymbolRatio(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) {
      return true;
    }
    final symbols = compact
        .replaceAll(RegExp(r'[A-Za-z0-9가-힣ぁ-んァ-ヶ一-龯々ー]'), '')
        .length;
    return symbols / compact.length >= 0.35;
  }

  Set<String> _knownArtistNamesForPaste() {
    return {
      ...existingSongs.map((song) => song.artist),
      ...knownSongs.map((song) => song.artist),
      'N.Flying',
      'ONEWE',
      'Xdinary Heroes',
      'Touched',
    }.map((artist) => artist.trim().toLowerCase()).toSet();
  }

  bool _matchesKnownArtist(String value, Set<String> knownArtists) {
    return knownArtists.contains(value.trim().toLowerCase());
  }

  String _songDuplicateKey(Song song) {
    return '${song.artist.trim().toLowerCase()}\n'
        '${song.title.trim().toLowerCase()}';
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
}

List<String?> buildOcrTitleAlternatives({
  required String primaryText,
  required String alternateText,
}) {
  final parser = _PasteSongParser(
    existingSongs: const [],
    knownSongs: const [],
  );
  final primaryCandidates = _extractOcrTitleCandidates(parser, primaryText);
  final alternateCandidates = _extractOcrTitleCandidates(parser, alternateText);
  final alternateByNumber = <int, _OcrTitleCandidate>{};
  for (final candidate in alternateCandidates) {
    final number = candidate.number;
    if (number != null && candidate.title.trim().isNotEmpty) {
      alternateByNumber.putIfAbsent(number, () => candidate);
    }
  }

  return List<String?>.generate(primaryCandidates.length, (index) {
    final primary = primaryCandidates[index];
    final primaryNumber = primary.number;
    if (primaryNumber != null) {
      return alternateByNumber[primaryNumber]?.title;
    }

    if (index >= alternateCandidates.length) {
      return null;
    }

    final alternate = alternateCandidates[index];
    if (alternate.number != null) {
      return null;
    }

    return alternate.title.trim().isEmpty ? null : alternate.title;
  });
}

List<_OcrTitleCandidate> _extractOcrTitleCandidates(
  _PasteSongParser parser,
  String text,
) {
  final inferredArtist = parser._inferPastedArtist(text);
  final candidates = <_OcrTitleCandidate>[];
  final mergedLines = parser._mergeNumberOnlyLines(
    const LineSplitter().convert(text),
  );
  var lineIndex = 0;

  for (final rawLine in mergedLines) {
    final rawTrimmedLine = rawLine.trim();
    if (rawTrimmedLine.isEmpty) {
      lineIndex++;
      continue;
    }

    final hasListNumber = parser._hasExplicitListNumber(rawTrimmedLine);
    if (parser._isPastedMetaLine(
      rawTrimmedLine,
      inferredArtist,
      lineIndex,
      totalLineCount: mergedLines.length,
      isNumberedSongLine: hasListNumber,
    )) {
      lineIndex++;
      continue;
    }

    final number = _extractOcrListNumber(rawTrimmedLine);
    final isNumberedArtistTitleLine = parser._isHashNumberedArtistTitleLine(
      rawTrimmedLine,
    );
    final cleanedLine = parser._cleanPastedSongLine(rawLine);
    if (cleanedLine.isEmpty) {
      lineIndex++;
      continue;
    }

    if (parser._isPastedMetaLine(
      cleanedLine,
      inferredArtist,
      lineIndex,
      totalLineCount: mergedLines.length,
      isNumberedSongLine: hasListNumber,
    )) {
      lineIndex++;
      continue;
    }

    final parsedSong = parser._parsePastedSongLine(
      cleanedLine,
      hasInferredArtist: inferredArtist.trim().isNotEmpty,
      forceArtistTitleOrder: isNumberedArtistTitleLine,
    );
    final title =
        parsedSong?.title ??
        parser._parseTitleOnlyPastedLine(
          cleanedLine,
          allowSeparators: inferredArtist.trim().isNotEmpty,
        );

    if (title != null && title.trim().isNotEmpty) {
      candidates.add(_OcrTitleCandidate(number: number, title: title.trim()));
    }
    lineIndex++;
  }

  return candidates;
}

int? _extractOcrListNumber(String line) {
  final match = RegExp(
    r'^\s*(\d{1,3})\s*(?:[.)．]\s*|[-:]\s*)',
  ).firstMatch(line);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1) ?? '');
}

class _OcrTitleCandidate {
  final int? number;
  final String title;

  const _OcrTitleCandidate({required this.number, required this.title});
}
