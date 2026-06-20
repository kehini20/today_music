import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_recognition.dart';

class OcrUnsupportedException implements Exception {
  const OcrUnsupportedException();
}

class TextOcrService {
  const TextOcrService();

  bool get isSupported => Platform.isAndroid;

  Future<OcrRecognitionResult> recognizeText(
    String imagePath, {
    OcrRecognitionMode mode = OcrRecognitionMode.auto,
  }) async {
    if (!isSupported) {
      throw const OcrUnsupportedException();
    }

    switch (mode) {
      case OcrRecognitionMode.korean:
        final text = await _recognizeWithScript(
          imagePath,
          TextRecognitionScript.korean,
        );
        return OcrRecognitionResult(
          requestedMode: mode,
          selectedSource: OcrRecognitionMode.korean,
          selectedText: text,
          koreanText: text,
        );
      case OcrRecognitionMode.japanese:
        final text = await _recognizeWithScript(
          imagePath,
          TextRecognitionScript.japanese,
        );
        return OcrRecognitionResult(
          requestedMode: mode,
          selectedSource: OcrRecognitionMode.japanese,
          selectedText: text,
          japaneseText: text,
        );
      case OcrRecognitionMode.auto:
        return _recognizeAutomatically(imagePath);
    }
  }

  Future<OcrRecognitionResult> _recognizeAutomatically(String imagePath) async {
    String koreanText = '';
    String japaneseText = '';
    Object? koreanError;
    Object? japaneseError;

    try {
      koreanText = await _recognizeWithScript(
        imagePath,
        TextRecognitionScript.korean,
      );
    } catch (error, stackTrace) {
      koreanError = error;
      _logOcr(
        'script-error',
        'script=korean error=${error.runtimeType}\n$stackTrace',
      );
    }

    try {
      japaneseText = await _recognizeWithScript(
        imagePath,
        TextRecognitionScript.japanese,
      );
    } catch (error, stackTrace) {
      japaneseError = error;
      _logOcr(
        'script-error',
        'script=japanese error=${error.runtimeType}\n$stackTrace',
      );
    }

    if (koreanText.trim().isEmpty && japaneseText.trim().isEmpty) {
      if (koreanError != null) {
        Error.throwWithStackTrace(koreanError, StackTrace.current);
      }
      if (japaneseError != null) {
        Error.throwWithStackTrace(japaneseError, StackTrace.current);
      }
    }

    _logOcr(
      'auto-complete',
      'koreanLength=${koreanText.length} '
          'japaneseLength=${japaneseText.length}',
    );
    return buildAutoOcrRecognitionResult(
      koreanText: koreanText,
      japaneseText: japaneseText,
    );
  }

  Future<String> _recognizeWithScript(
    String imagePath,
    TextRecognitionScript script,
  ) async {
    final file = File(imagePath);
    final fileExists = await file.exists();
    final fileSize = fileExists ? await file.length() : 0;
    _logOcr(
      'file-check',
      'script=${script.name} exists=$fileExists size=$fileSize',
    );
    if (!fileExists || fileSize == 0) {
      throw const OcrImageLoadException();
    }
    _logOcr('recognizer-create', 'script=${script.name}');
    final recognizer = TextRecognizer(script: script);
    try {
      _logOcr('input-image-create', 'script=${script.name}');
      final image = InputImage.fromFilePath(imagePath);
      _logOcr('process-start', 'script=${script.name}');
      final recognizedText = await recognizer.processImage(image);
      final rawText = recognizedText.text;
      _logOcr(
        'raw-result',
        'script=${script.name} length=${rawText.length} '
            'lines=${rawText.isEmpty ? 0 : rawText.split('\n').length} '
            'preview=${_safePreview(rawText)}',
      );
      final normalized = _normalizeRecognizedText(rawText);
      _logOcr(
        'process-complete',
        'script=${script.name} length=${normalized.length}',
      );
      return normalized;
    } catch (error, stackTrace) {
      _logOcr(
        'process-error',
        'script=${script.name} error=${error.runtimeType}\n$stackTrace',
      );
      rethrow;
    } finally {
      await recognizer.close();
      _logOcr('recognizer-close', 'script=${script.name}');
    }
  }

  String _normalizeRecognizedText(String text) {
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

void _logOcr(String stage, String details) {
  if (kDebugMode) {
    debugPrint('[TDM OCR] $stage $details');
  }
}

String _safePreview(String text) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return String.fromCharCodes(normalized.runes.take(120));
}
