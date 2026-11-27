plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// CI passes -PbuildNumber=<run number>, so every build is a newer version than the last.
val buildNumber = (findProperty("buildNumber") as String?)?.toIntOrNull() ?: 1
// Release signing key from CI secrets. Same key every build = new APKs install over old ones and keep data.
val keystore = System.getenv("PB_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
val sharedAssets = layout.buildDirectory.dir("generated/shared").get().asFile

android {
    namespace = "com.usbrowser.pb"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.usbrowser.pb"
        minSdk = 26
        targetSdk = 35
        versionCode = buildNumber
        versionName = "1.0.$buildNumber"
    }

    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = keystore
                storePassword = System.getenv("PB_KEYSTORE_PASSWORD")
                keyAlias = "pb"
                keyPassword = System.getenv("PB_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName(if (keystore != null) "release" else "debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    lint { checkReleaseBuilds = false }

    // spoof.js, youtube.js and blocklist.json are shared with the iOS app.
    sourceSets["main"].assets.srcDir(sharedAssets)
}

val copyShared = tasks.register<Copy>("copyShared") {
    from(rootDir.resolve("../Sources")) { include("spoof.js", "youtube.js", "blocklist.json") }
    into(sharedAssets)
}
tasks.named("preBuild") { dependsOn(copyShared) }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303") // real org.json for unit tests (Android's is a stub there)
}
