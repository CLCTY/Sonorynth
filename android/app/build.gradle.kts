import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val isPreviewBuild = System.getenv("SONORYNTH_PREVIEW_BUILD") == "true"
val signingPath = if (isPreviewBuild) null else System.getenv("SONORYNTH_SIGNING_PROPERTIES")
val releaseSigning = Properties()
if (!signingPath.isNullOrBlank()) {
    file(signingPath).inputStream().use { releaseSigning.load(it) }
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach {
        require(!releaseSigning.getProperty(it).isNullOrBlank()) { "Missing release signing field: $it" }
    }
}

android {
    namespace = "app.sonorynth.player"
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
        applicationId = "app.sonorynth.player"
        if (isPreviewBuild) applicationIdSuffix = ".preview"
        manifestPlaceholders["appLabel"] = if (isPreviewBuild) "Sonorynth 预览版" else "Sonorynth"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!signingPath.isNullOrBlank()) {
            create("release") {
                storeFile = file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        named("release") {
            signingConfig = when {
                isPreviewBuild -> signingConfigs.getByName("debug")
                !signingPath.isNullOrBlank() -> signingConfigs.getByName("release")
                else -> null
            }
        }
    }
}

flutter { source = "../.." }
