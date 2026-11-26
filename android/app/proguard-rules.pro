-dontwarn javax.lang.model.element.Modifier

# Feder: ML Kit Handschrift-Erkennung nicht wegoptimieren
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.internal.mlkit_vision_digital_ink.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_**
