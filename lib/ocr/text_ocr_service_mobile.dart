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
      if (kDebugMode) {
        debugPrint('Korean OCR failed: $error\n$stackTrace');
      }
    }

    try {
      japaneseText = await _recognizeWithScript(
        imagePath,
        TextRecognitionScript.japanese,
      );
    } catch (error, stackTrace) {
      japaneseError = error;
      if (kDebugMode) {
        debugPrint('Japanese OCR failed: $error\n$stackTrace');
      }
    }

    if (koreanText.trim().isEmpty && japaneseText.trim().isEmpty) {
      if (koreanError != null) {
        throw koreanError;
      }
      if (japaneseError != null) {
        throw japaneseError;
      }
    }

    return buildAutoOcrRecognitionResult(
      koreanText: koreanText,
      japaneseText: japaneseText,
    );
  }

  Future<String> _recognizeWithScript(
    String imagePath,
    TextRecognitionScript script,
  ) async {
    final recognizer = TextRecognizer(script: script);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(image);
      return _normalizeRecognizedText(recognizedText.text);
    } finally {
      await recognizer.close();
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
