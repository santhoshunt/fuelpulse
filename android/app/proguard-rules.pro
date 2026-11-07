# google_mlkit_text_recognition refers to every script's recogniser, but
# FuelPulse bundles only the Latin one. Without these, R8 stops the release
# build on the missing Chinese, Devanagari, Japanese and Korean classes.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# ML Kit builds its component registry by creating each registrar named in
# the manifest through its no-argument constructor, by reflection. R8 full
# mode keeps the class names but deletes those constructors, so the registry
# stays empty and the first scan fails with a NullPointerException
# (SharedPrefManager is null in v2.1.1).
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
