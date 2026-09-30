import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local test releases use the debug key until the owner supplies this ignored
// file. Store passwords and keystores outside source control.
val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties().apply {
    if (releaseKeyFile.exists()) releaseKeyFile.inputStream().use { load(it) }
}

android {
    namespace = "com.framelab.framelab"
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
        applicationId = "com.framelab.framelab"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyFile.exists()) {
            create("release") {
                fun requiredKey(name: String): String =
                    requireNotNull(releaseKey.getProperty(name)) { "Missing $name in android/key.properties" }
                keyAlias = requiredKey("keyAlias")
                keyPassword = requiredKey("keyPassword")
                storeFile = rootProject.file(requiredKey("storeFile"))
                storePassword = requiredKey("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            // Optional emulator-only packaging. Normal builds keep all ABIs.
            System.getenv("FRAMELAB_TEST_ABI")?.let { testAbi ->
                require(testAbi in setOf("x86_64", "arm64-v8a", "armeabi-v7a"))
                ndk.abiFilters.clear()
                ndk.abiFilters.add(testAbi)
            }
        }
        release {
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName(
                if (releaseKeyFile.exists()) "release" else "debug"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.30.0")
}
