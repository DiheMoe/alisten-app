import java.net.URI
import java.util.Base64
import java.util.Properties

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android Gradle 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

// Flutter 以 Gradle 属性 `dart-defines` 传入全部 --dart-define：逗号分隔，
// 每项是 base64 编码的 KEY=VALUE。
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines")?.toString() ?: "")
        .split(',')
        .filter { it.isNotBlank() }
        .mapNotNull { entry ->
            runCatching { String(Base64.getDecoder().decode(entry), Charsets.UTF_8) }
                .getOrNull()
                ?.split('=', limit = 2)
                ?.takeIf { it.size == 2 }
                ?.let { it[0] to it[1] }
        }
        .toMap()

val defaultLinkHost = "livehouse.dihe.moe"

// java.net.URI 解析不了 Dart 接受的部分源（如主机名含下划线），此时返回 null
// 而不抛异常，以免调试构建和 IDE 同步失败。
fun hostOf(origin: String): String? =
    runCatching { URI(origin).host }
        .getOrNull()
        ?.removeSurrounding("[", "]")
        ?.lowercase()
        ?.takeIf { it.isNotEmpty() }

val apiUrl: String? = dartDefines["ALISTEN_API_URL"]?.trim()?.takeIf { it.isNotEmpty() }

// 解析规则与 Dart 的 BuildEnvironment.fromEnvironment 一致，但只取主机名、不带
// 端口。Android 匹配 intent-filter 主机名时区分大小写，因此统一转小写。
val resolvedLinkHost: String? =
    dartDefines["ALISTEN_LINK_HOST"]?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        ?: apiUrl?.let { hostOf(it) }
        ?: if (apiUrl == null) defaultLinkHost else null

val verifyReleaseLinkHost by tasks.registering {
    val host = resolvedLinkHost
    doLast {
        if (host == null) {
            throw GradleException(
                "Release builds need a real App Links host, but the host of ALISTEN_API_URL " +
                    "cannot be read. Pass --dart-define=ALISTEN_LINK_HOST=<host>."
            )
        }
        if (host == "localhost") {
            throw GradleException(
                "Release builds need a real App Links host, but it resolved to 'localhost'. " +
                    "Pass --dart-define=ALISTEN_LINK_HOST=<host> or an HTTPS " +
                    "--dart-define=ALISTEN_API_URL=<origin>."
            )
        }
    }
}

android {
    namespace = "moe.dihe.alisten"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "moe.dihe.alisten"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["linkHost"] = resolvedLinkHost ?: defaultLinkHost
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = keyProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyReleaseLinkHost)
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
