plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.tap_screen_tap"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.tap_screen_tap"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}

flutter {
    source = "../.."
}

// GeneratedPluginRegistrant is overwritten by `flutter pub get`; re-apply clicker plugin for the overlay engine.
val generatedRegistrant =
    file("src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java")

tasks.register("ensureClickerPluginRegistrant") {
    doLast {
        if (!generatedRegistrant.exists()) return@doLast
        var text = generatedRegistrant.readText()
        if (text.contains("ClickerFlutterPlugin")) return@doLast
        val insertion = """
    try {
      flutterEngine.getPlugins().add(new com.example.tap_screen_tap.ClickerFlutterPlugin());
    } catch (Exception e) {
      Log.e(TAG, "Error registering plugin clicker, com.example.tap_screen_tap.ClickerFlutterPlugin", e);
    }
"""
        val anchor = "  }\n}"
        val index = text.lastIndexOf(anchor)
        if (index < 0) return@doLast
        text = text.substring(0, index) + insertion + text.substring(index)
        generatedRegistrant.writeText(text)
    }
}

tasks.named("preBuild").configure {
    dependsOn("ensureClickerPluginRegistrant")
}
