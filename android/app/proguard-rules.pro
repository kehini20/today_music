# google_mlkit_text_recognition exposes optional script options from its
# Android bridge. TDM only bundles Korean and Japanese recognizers, so R8 may
# safely ignore the absent Chinese and Devanagari option classes.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions

# ML Kit discovers this registrar from AndroidManifest metadata. Its component
# list must retain the SharedPrefManager component used by vision-common.
-keep class com.google.mlkit.common.internal.CommonComponentRegistrar { *; }
-keep class com.google.mlkit.common.sdkinternal.SharedPrefManager { *; }
-keep class com.google.mlkit.vision.text.internal.TextRegistrar { *; }
-keep class com.google.mlkit.vision.text.internal.zzo { *; }
-keep class com.google.mlkit.vision.text.internal.zzp { *; }

# R8 can merge this ML Kit vision factory with unrelated create() factories.
# The merged release code can pass a null SharedPrefManager to zzmj while
# InputImage is being converted for the platform channel.
-keep class com.google.android.gms.internal.mlkit_vision_common.zzmr { *; }

# Keep the telemetry constructor called by zzmr intact as well.
-keep class com.google.android.gms.internal.mlkit_vision_common.zzmj { *; }
