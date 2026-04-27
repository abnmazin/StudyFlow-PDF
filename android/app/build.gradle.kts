plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.studyflowpdf"
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
        applicationId = "com.example.studyflowpdf"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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

flutter {
    source = "../.."
}

// WORKAROUND: Inject missing namespace into isar_flutter_libs to satisfy AGP 8.x
gradle.projectsEvaluated {
    project.rootProject.subprojects {
        if (name == "isar_flutter_libs") {
            val extension = extensions.findByName("android")
            if (extension != null) {
                val namespaceMethod = extension.javaClass.methods.find { it.name == "namespace" }
                if (namespaceMethod != null) {
                    namespaceMethod.invoke(extension, "dev.isar.isar_flutter_libs")
                    println("Applied namespace to isar_flutter_libs successfully")
                }
            }
        }
    }
}