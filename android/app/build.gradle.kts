import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val isReleaseBuildRequested =
    gradle.startParameter.taskNames.any { taskName ->
        taskName.contains("release", ignoreCase = true)
    }

if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

fun requiredKeystoreProperty(name: String): String {
    return keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException(
            "Missing '$name' in android/key.properties. " +
                "Copy android/key.properties.example and provide the local release signing values.",
        )
}

if (isReleaseBuildRequested && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Release signing is not configured. " +
            "Create android/key.properties from android/key.properties.example. " +
            "The release build will not fall back to the debug keystore.",
    )
}

if (isReleaseBuildRequested) {
    val releaseStoreFile =
        rootProject.file(requiredKeystoreProperty("storeFile"))
    requiredKeystoreProperty("storePassword")
    requiredKeystoreProperty("keyAlias")
    requiredKeystoreProperty("keyPassword")
    if (!releaseStoreFile.isFile) {
        throw GradleException(
            "Release keystore was not found at '${releaseStoreFile.absolutePath}'. " +
                "Check 'storeFile' in android/key.properties.",
        )
    }
}

android {
    namespace = "com.todaydrawmusic.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.todaydrawmusic.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile =
                    keystoreProperties.getProperty("storeFile")
                        ?.takeIf { it.isNotBlank() }
                        ?.let(rootProject::file)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}
