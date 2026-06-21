import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:today_music/main.dart';

void main() {
  test('display version matches the pubspec release version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('version: 0.7.2+11'));
    expect(appSemanticVersion, '0.7.2');
    expect(appDisplayVersion, 'Alpha 0.7.2');
  });
}
