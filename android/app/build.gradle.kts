import java.util.Properties

// リリース署名の鍵は android/key.properties に置く（.gitignore 済み）。
// 手元に鍵がない環境では null のままにして、デバッグ鍵にフォールバックする。
val keystoreProperties = Properties().takeIf { props ->
    rootProject.file("key.properties").let { f ->
        if (f.exists()) { f.inputStream().use(props::load); true } else false
    }
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "yun.app.chain_puzzle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "yun.app.chain_puzzle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties != null) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // key.properties があれば本番鍵、なければデバッグ鍵。
            // デバッグ鍵で署名した成果物は Play Store には提出できない。
            signingConfig = signingConfigs.getByName(
                if (keystoreProperties != null) "release" else "debug"
            )
        }
    }
}

flutter {
    source = "../.."
}
