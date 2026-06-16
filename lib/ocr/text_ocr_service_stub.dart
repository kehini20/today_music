import 'ocr_recognition.dart';

class OcrUnsupportedException implements Exception {
  const OcrUnsupportedException();
}

class TextOcrService {
  const TextOcrService();

  bool get isSupported => false;

  Future<OcrRecognitionResult> recognizeText(
    String imagePath, {
    OcrRecognitionMode mode = OcrRecognitionMode.auto,
  }) {
    throw const OcrUnsupportedException();
  }
}
