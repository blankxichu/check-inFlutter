plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "checkin.com"
    compileSdk = flutter.compileSdkVersion
    // Align with Firebase plugins requirements
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Application ID must match google-services.json package_name
        applicationId = "checkin.com"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
    // Firebase requires minSdk 23+
    minSdk = Math.max(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Para el primer build de release, desactiva minify/shrinker para evitar problemas de ofuscación/recorte
            isMinifyEnabled = false
            isShrinkResources = false
            // Si activas minify más adelante, añade tus reglas en proguard-rules.pro
            // Habilita upload de mapping en release si habilitas minify/shrinker en el futuro
            firebaseCrashlytics {
                mappingFileUploadEnabled = true
            }
        }
        debug {
            // En debug puedes habilitar envíos de crash para pruebas
            firebaseCrashlytics {
                mappingFileUploadEnabled = false
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BoM (si añades analytics en el futuro, mantén la BoM aquí)
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
