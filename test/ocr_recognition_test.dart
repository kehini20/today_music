import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/ocr/text_ocr_service.dart';

void main() {
  group('automatic OCR result packaging', () {
    test('uses korean text by default when both results exist', () {
      final result = buildAutoOcrRecognitionResult(
        koreanText: '1. 환절기\n2. Endless Summer',
        japaneseText: '1. きらめく季節\n2. Endless Summer',
      );

      expect(result.selectedSource, OcrRecognitionMode.korean);
      expect(result.selectedText, contains('환절기'));
      expect(result.koreanText, contains('환절기'));
      expect(result.japaneseText, contains('きらめく季節'));
    });

    test('falls back to japanese text when korean result is empty', () {
      final result = buildAutoOcrRecognitionResult(
        koreanText: '',
        japaneseText: '1. きらめく季節\n2. Marionette Wire',
      );

      expect(result.selectedSource, OcrRecognitionMode.japanese);
      expect(result.selectedText, contains('きらめく季節'));
    });

    test('returns empty selected text when both results are empty', () {
      final result = buildAutoOcrRecognitionResult(
        koreanText: '',
        japaneseText: '',
      );

      expect(result.selectedText, isEmpty);
      expect(result.hasAnyText, isFalse);
    });
  });

  group('OCR result score helper', () {
    test(
      'scores structured text above symbol-heavy text for future review',
      () {
        final symbolScore = scoreRecognizedText('%%##@@\n###');
        final structuredScore = scoreRecognizedText(
          '1. Blue Moon\n2. 4242\n3. Rooftop',
        );

        expect(structuredScore, greaterThan(symbolScore));
      },
    );
  });
}
