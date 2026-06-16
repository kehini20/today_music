import 'dart:convert';

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
    final inferredArtist = _inferPastedArtist(text);
    final drafts = <PasteSongDraft>[];
    var lineIndex = 0;

    for (final rawLine in _mergeNumberOnlyLines(
      const LineSplitter().convert(text),
    )) {
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

    return '';
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

  String _cleanPastedSongLine(String rawLine) {
    var line = rawLine.trim().replaceAll(RegExp(r'\s+'), ' ');
    line = line.replaceFirst(RegExp(r'^#\d+\s+(?=.*\s(?:-|–|—|/)\s)'), '');
    line = line.replaceFirst(RegExp(r'^[+\-*•]\s*'), '');
    line = line.replaceFirst(RegExp(r'^\d+\s*(?:[.)\uFF0E]\s*|[-:]\s*)'), '');
    line = _stripPerformanceSuffix(line);
    line = _unwrapWholeLineParentheses(line);
    line = line.replaceFirst(RegExp(r'^[+\-*•]\s*'), '');
    return line
        .replaceAll(RegExp(r'''["“”‘’]'''), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

      final before = _cleanDecoratedEventArtistCandidate(
        withoutSetlist.substring(0, index),
      );
      if (_looksLikeArtistCandidate(before)) {
        return before;
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
        .replaceAll(RegExp(r'[_\-–—:/,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return _looksLikeDecoratedEventArtistCandidate(candidate) ? candidate : '';
  }

  bool _looksLikeDecoratedEventArtistCandidate(String value) {
    final candidate = value.trim();
    if (!_looksLikeArtistCandidate(candidate)) {
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

  bool _isPastedMetaLine(String line, String inferredArtist, int lineIndex) {
    if (RegExp(r'^[=\-–—_\s]+$').hasMatch(line)) {
      return true;
    }

    if (_isTdmSharedListMetaLine(line)) {
      return true;
    }

    if (_isEncoreOrPerformanceMetaLine(line) || _isNoisyOcrMetaFragment(line)) {
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
        value.contains('\uD398\uC2A4\uD2F0\uBC8C');
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
        if (nextLine != null && !_isPastedMetaLine(nextLine, '', nextIndex)) {
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
    final match = RegExp(
      r'^(?:\d{4}[./-]\d{1,2}[./-]\d{1,2}\s+)?(.+?)\s+(?:셋리스트|setlist)$',
      caseSensitive: false,
    ).firstMatch(line.trim());
    if (match == null) {
      return '';
    }
    final candidate = _cleanArtistCandidate(match.group(1) ?? '');
    return _looksLikeArtistCandidate(candidate) ? candidate : '';
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

  bool _isEncoreOrPerformanceMetaLine(String line) {
    final normalized = line.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return normalized == 'mc' ||
        normalized == 'm.c.' ||
        RegExp(r'^앵콜\d*$').hasMatch(normalized) ||
        RegExp(r'^encore\d*$').hasMatch(normalized);
  }

  bool _isNoisyOcrMetaFragment(String line) {
    final candidate = line.trim();
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
  var lineIndex = 0;

  for (final rawLine in parser._mergeNumberOnlyLines(
    const LineSplitter().convert(text),
  )) {
    final rawTrimmedLine = rawLine.trim();
    if (rawTrimmedLine.isEmpty) {
      lineIndex++;
      continue;
    }

    if (parser._isPastedMetaLine(rawTrimmedLine, inferredArtist, lineIndex)) {
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

    if (parser._isPastedMetaLine(cleanedLine, inferredArtist, lineIndex)) {
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
