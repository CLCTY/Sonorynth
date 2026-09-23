import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPath = System.getenv("SONORYNTH_SIGNING_PROPERTIES")
val releaseSigning = Properties()
if (!signingPath.isNullOrBlank()) {
    file(signingPath).inputStream().use { releaseSigning.load(it) }
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach {
        require(!releaseSigning.getProperty(it).isNullOrBlank()) { "Missing release signing field: $it" }
    }
}

android {
    namespace = "app.melodyflow.player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.melodyflow.player"
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
            signingConfig = if (!signingPath.isNullOrBlank()) signingConfigs.getByName("release") else null
        }
    }
}

flutter { source = "../.." }
