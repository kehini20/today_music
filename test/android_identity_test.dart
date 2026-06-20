import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android identity and release signing policy stay fixed', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final strings = File(
      'android/app/src/main/res/values/strings.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/todaydrawmusic/app/MainActivity.kt',
    ).readAsStringSync();

    expect(gradle, contains('namespace = "com.todaydrawmusic.app"'));
    expect(gradle, contains('applicationId = "com.todaydrawmusic.app"'));
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('signingConfigs.findByName("release")'));
    expect(gradle, contains('"proguard-rules.pro"'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(manifest, contains('android:label="@string/app_name"'));
    expect(strings, contains('<string name="app_name">오늘의 한 곡</string>'));
    expect(activity, contains('package com.todaydrawmusic.app'));
    expect(
      File(
        'android/app/src/main/kotlin/com/example/today_music/MainActivity.kt',
      ).existsSync(),
      isFalse,
    );
  });

  test('release R8 rules only suppress absent optional OCR scripts', () {
    final rules = File('android/app/proguard-rules.pro').readAsStringSync();

    expect(
      rules,
      contains(
        '-dontwarn com.google.mlkit.vision.text.chinese.'
        r'ChineseTextRecognizerOptions$Builder',
      ),
    );
    expect(
      rules,
      contains(
        '-dontwarn com.google.mlkit.vision.text.devanagari.'
        r'DevanagariTextRecognizerOptions$Builder',
      ),
    );
    expect(rules, isNot(contains('-dontwarn com.google.mlkit.**')));
    expect(rules, isNot(contains('-keep class com.google.mlkit.**')));
    expect(rules, isNot(contains('com.google.mlkit.vision.text.korean')));
    expect(rules, isNot(contains('com.google.mlkit.vision.text.japanese')));
    expect(
      rules,
      contains(
        '-keep class '
        'com.google.mlkit.common.internal.CommonComponentRegistrar { *; }',
      ),
    );
    expect(
      rules,
      contains(
        '-keep class '
        'com.google.mlkit.common.sdkinternal.SharedPrefManager { *; }',
      ),
    );
    expect(
      rules,
      contains(
        '-keep class '
        'com.google.mlkit.vision.text.internal.TextRegistrar { *; }',
      ),
    );
    expect(
      rules,
      contains('-keep class com.google.mlkit.vision.text.internal.zzo { *; }'),
    );
    expect(
      rules,
      contains('-keep class com.google.mlkit.vision.text.internal.zzp { *; }'),
    );
    expect(
      rules,
      contains(
        '-keep class '
        'com.google.android.gms.internal.mlkit_vision_common.zzmr { *; }',
      ),
    );
    expect(
      rules,
      contains(
        '-keep class '
        'com.google.android.gms.internal.mlkit_vision_common.zzmj { *; }',
      ),
    );
    expect(
      RegExp(r'^-keep class ', multiLine: true).allMatches(rules).length,
      7,
    );
  });

  test('release signing secrets remain ignored', () {
    final rootIgnore = File('.gitignore').readAsStringSync();
    final androidIgnore = File('android/.gitignore').readAsStringSync();

    expect('$rootIgnore\n$androidIgnore', contains('key.properties'));
    expect('$rootIgnore\n$androidIgnore', contains('**/*.jks'));
    expect('$rootIgnore\n$androidIgnore', contains('**/*.keystore'));
    expect(File('android/key.properties.example').existsSync(), isTrue);
  });
}
