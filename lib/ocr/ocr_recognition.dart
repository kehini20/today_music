enum OcrRecognitionMode { auto, korean, japanese }

extension OcrRecognitionModeLabel on OcrRecognitionMode {
  String get storageValue => name;

  String get label {
    switch (this) {
      case OcrRecognitionMode.auto:
        return '\uC790\uB3D9';
      case OcrRecognitionMode.korean:
        return '\uD55C\uAD6D\uC5B4';
      case OcrRecognitionMode.japanese:
        return '\uC77C\uBCF8\uC5B4';
    }
  }

  static OcrRecognitionMode fromStorageValue(String? value) {
    for (final mode in OcrRecognitionMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    return OcrRecognitionMode.auto;
  }
}

class OcrRecognitionResult {
  final OcrRecognitionMode requestedMode;
  final OcrRecognitionMode selectedSource;
  final String selectedText;
  final String koreanText;
  final String japaneseText;

  const OcrRecognitionResult({
    required this.requestedMode,
    required this.selectedSource,
    required this.selectedText,
    this.koreanText = '',
    this.japaneseText = '',
  });

  bool get hasAnyText => selectedText.trim().isNotEmpty;
  bool get hasMultipleResults =>
      koreanText.trim().isNotEmpty && japaneseText.trim().isNotEmpty;

  String textForSource(OcrRecognitionMode source) {
    switch (source) {
      case OcrRecognitionMode.korean:
        return koreanText;
      case OcrRecognitionMode.japanese:
        return japaneseText;
      case OcrRecognitionMode.auto:
        return selectedText;
    }
  }
}

OcrRecognitionResult buildAutoOcrRecognitionResult({
  required String koreanText,
  required String japaneseText,
}) {
  final normalizedKoreanText = koreanText.trim();
  final normalizedJapaneseText = japaneseText.trim();
  final selectedSource = normalizedKoreanText.isNotEmpty
      ? OcrRecognitionMode.korean
      : OcrRecognitionMode.japanese;
  final selectedText = selectedSource == OcrRecognitionMode.korean
      ? normalizedKoreanText
      : normalizedJapaneseText;

  return OcrRecognitionResult(
    requestedMode: OcrRecognitionMode.auto,
    selectedSource: selectedSource,
    selectedText: selectedText,
    koreanText: normalizedKoreanText,
    japaneseText: normalizedJapaneseText,
  );
}

int scoreRecognizedText(String text) {
  final normalized = text.trim();
  if (normalized.isEmpty) {
    return 0;
  }

  final lines = normalized
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final characterCount = normalized.replaceAll(RegExp(r'\s+'), '').length;
  final listNumberCount = lines
      .where((line) => RegExp(r'^\d{1,2}\s*[.)\uFF0E:-]').hasMatch(line))
      .length;
  final validCharacters = RegExp(
    r'[A-Za-z0-9\uAC00-\uD7A3\u3040-\u30FF\u3400-\u9FFF]',
  ).allMatches(normalized).length;
  final symbolCharacters = normalized
      .replaceAll(
        RegExp(r'[A-Za-z0-9\uAC00-\uD7A3\u3040-\u30FF\u3400-\u9FFF\s]'),
        '',
      )
      .length;

  final validRatio = characterCount == 0
      ? 0.0
      : validCharacters / characterCount;
  final symbolRatio = characterCount == 0
      ? 1.0
      : symbolCharacters / characterCount;

  return characterCount.clamp(0, 400) +
      (lines.length * 12) +
      (listNumberCount * 20) +
      (validRatio * 80).round() -
      (symbolRatio * 120).round();
}
