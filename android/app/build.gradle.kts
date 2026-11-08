import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
fun signingValue(environmentName: String, propertyName: String): String? =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst {
            val requiredValues = mapOf(
                "ANDROID_KEYSTORE_PATH / storeFile" to signingValue("ANDROID_KEYSTORE_PATH", "storeFile"),
                "ANDROID_KEYSTORE_PASSWORD / storePassword" to signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword"),
                "ANDROID_KEY_ALIAS / keyAlias" to signingValue("ANDROID_KEY_ALIAS", "keyAlias"),
                "ANDROID_KEY_PASSWORD / keyPassword" to signingValue("ANDROID_KEY_PASSWORD", "keyPassword"),
            )
            val missing = requiredValues.filterValues { it == null }.keys
            check(missing.isEmpty()) {
                "Release signing is required. Missing: ${missing.joinToString()}"
            }
            check(file(signingValue("ANDROID_KEYSTORE_PATH", "storeFile")!!).isFile) {
                "Release keystore file does not exist."
            }
        }
    }
}

android {
    namespace = "com.nonthachai.privatewebhub"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nonthachai.privatewebhub"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
            keyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
            storePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
            storeFile = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")?.let { file(it) }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
