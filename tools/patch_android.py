#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Жёсткая стабилизация Flutter-обёртки:
- settings.gradle.kts ПОЛНОСТЬЮ перезаписывается (AGP 8.3.2, Kotlin 1.9.24)
- gradle-wrapper -> Gradle 8.6
- app/build.gradle(.kts): Java 17 + desugaring + multidex + packaging + lint
- AndroidManifest: android:exported="true" + meta flutterEmbedding=2
"""

import sys, pathlib, re

AGP = "8.3.2"
KOTLIN = "1.9.24"
GRADLE = "8.6"
DESUGAR = "com.android.tools:desugar_jdk_libs:2.0.4"
MULTIDEX = "androidx.multidex:multidex:2.0.1"
NAMESPACE = "com.example.bp_logger"

def R(p): return p.read_text(encoding="utf-8", errors="ignore")
def W(p,s): p.parent.mkdir(parents=True, exist_ok=True); p.write_text(s, encoding="utf-8")

def force_settings_kts(app: pathlib.Path):
    f = app / "android/settings.gradle.kts"
    content = f"""pluginManagement {{
    val flutterSdkPath =
        run {{
            val properties = java.util.Properties()
            file("local.properties").inputStream().use {{ properties.load(it) }}
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) {{ "flutter.sdk not set in local.properties" }}
            flutterSdkPath
        }}

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {{
        google()
        mavenCentral()
        gradlePluginPortal()
    }}
}}

plugins {{
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "{AGP}" apply false
    id("org.jetbrains.kotlin.android") version "{KOTLIN}" apply false
}}

include(":app")
"""
    W(f, content)

def set_wrapper(app: pathlib.Path):
    prop = app/"android/gradle/wrapper/gradle-wrapper.properties"
    base = (
        "distributionBase=GRADLE_USER_HOME\n"
        "distributionPath=wrapper/dists\n"
        f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE}-bin.zip\n"
        "zipStoreBase=GRADLE_USER_HOME\n"
        "zipStorePath=wrapper/dists\n"
    )
    if prop.exists():
        t = R(prop)
        t = re.sub(r"distributionUrl=.*",
                   f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE}-bin.zip", t)
        W(prop, t)
    else:
        W(prop, base)

def patch_manifest(app: pathlib.Path):
    mf = app/"android/app/src/main/AndroidManifest.xml"
    if not mf.exists():
        W(mf, f"""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{NAMESPACE}">
  <application android:label="bp_logger" android:name="${{applicationName}}" android:icon="@mipmap/ic_launcher">
    <activity android:name=".MainActivity" android:exported="true" android:launchMode="singleTop"
      android:theme="@style/LaunchTheme"
      android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
      android:hardwareAccelerated="true" android:windowSoftInputMode="adjustResize">
      <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
    <meta-data android:name="flutterEmbedding" android:value="2" />
  </application>
</manifest>
"""); return
    t = R(mf)
    if "android:exported" not in t:
        t = re.sub(r"(<activity\b[^>]*>)", lambda m: m.group(1).replace(">", ' android:exported="true">', 1), t, 1)
    if 'android:name="flutterEmbedding"' not in t:
        t = t.replace("</application>", '    <meta-data android:name="flutterEmbedding" android:value="2" />\n  </application>')
    W(mf, t)

def patch_app_gradle(app: pathlib.Path):
    g = app/"android/app/build.gradle"
    k = app/"android/app/build.gradle.kts"
    def apply_groovy(txt: str) -> str:
        if "namespace" not in txt:
            txt = re.sub(r"android\s*\{", f'android {{\n    namespace "{NAMESPACE}"', txt, 1)
        if "applicationId" not in txt:
            txt = re.sub(r"defaultConfig\s*\{", f'defaultConfig {{\n        applicationId "{NAMESPACE}"', txt, 1)
        # compileOptions + desugaring
        if "compileOptions" in txt:
            txt = re.sub(r"compileOptions\s*\{[\s\S]*?\}",
                         """compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""", txt, 1)
        else:
            txt = re.sub(r"android\s*\{", """android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""", txt, 1)
        # kotlinOptions
        if "kotlinOptions" in txt:
            txt = re.sub(r'kotlinOptions\s*\{[\s\S]*?\}', 'kotlinOptions {\n        jvmTarget = "17"\n    }', txt, 1)
        else:
            txt = re.sub(r"android\s*\{", """android {
    kotlinOptions { jvmTarget = "17" }""", txt, 1)
        # multidex
        if "multiDexEnabled true" not in txt:
            txt = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled true", txt, 1)
        # lint
        if "lintOptions" in txt:
            txt = re.sub(r"lintOptions\s*\{[\s\S]*?\}", "lintOptions {\n        abortOnError false\n        checkReleaseBuilds false\n    }", txt, 1)
        else:
            txt = re.sub(r"android\s*\{", "android {\n    lintOptions { abortOnError false; checkReleaseBuilds false }", txt, 1)
        # packaging
        if "packagingOptions" in txt:
            txt = re.sub(r"packagingOptions\s*\{[\s\S]*?\}",
                         """packagingOptions {
        resources { excludes += ["META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES"] }
    }""", txt, 1)
        else:
            txt = re.sub(r"android\s*\{", """android {
    packagingOptions { resources { excludes += ["META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES"] } }""", txt, 1)
        # deps
        if "coreLibraryDesugaring" not in txt:
            txt = re.sub(r"dependencies\s*\{", f"""dependencies {{
    coreLibraryDesugaring "{DESUGAR}" """, txt, 1)
        if "androidx.multidex:multidex" not in txt:
            txt = re.sub(r"dependencies\s*\{", f"""dependencies {{
    implementation "{MULTIDEX}" """, txt, 1)
        return txt

    def apply_kts(txt: str) -> str:
        if "namespace" not in txt:
            txt = re.sub(r"android\s*\{", f'android {{\n    namespace = "{NAMESPACE}"', txt, 1)
        if "applicationId" not in txt:
            txt = re.sub(r"defaultConfig\s*\{", f'defaultConfig {{\n        applicationId = "{NAMESPACE}"', txt, 1)
        if "compileOptions" in txt:
            txt = re.sub(r"compileOptions\s*\{[\s\S]*?\}",
                         """compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""", txt, 1)
        else:
            txt = re.sub(r"android\s*\{", """android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""", txt, 1)
        if "kotlinOptions" in txt:
            txt = re.sub(r'kotlinOptions\s*\{[\s\S]*?\}', 'kotlinOptions {\n        jvmTarget = "17"\n    }', txt, 1)
        else:
            txt = re.sub(r"android\s*\{", """android {
    kotlinOptions { jvmTarget = "17" }""", txt, 1)
        if "multiDexEnabled" not in txt:
            txt = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled = true", txt, 1)
        if re.search(r"\blint\s*\{", txt):
            txt = re.sub(r"lint\s*\{[\s\S]*?\}", "lint {\n        abortOnError = false\n        checkReleaseBuilds = false\n    }", txt, 1)
        else:
            txt = re.sub(r"android\s*\{", "android {\n    lint { abortOnError = false; checkReleaseBuilds = false }", txt, 1)
        if re.search(r"\bpackaging\s*\{", txt):
            txt = re.sub(r"packaging\s*\{[\s\S]*?\}",
                         """packaging {
        resources { excludes += setOf("META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES") }
    }""", txt, 1)
        else:
            txt = re.sub(r"android\s*\{", """android {
    packaging { resources { excludes += setOf("META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES") } }""", txt, 1)
        if "coreLibraryDesugaring(" not in txt:
            txt = re.sub(r"dependencies\s*\{", f"""dependencies {{
    coreLibraryDesugaring("{DESUGAR}") """, txt, 1)
        if "androidx.multidex:multidex" not in txt:
            txt = re.sub(r"dependencies\s*\{", f"""dependencies {{
    implementation("{MULTIDEX}") """, txt, 1)
        return txt

    if k.exists():
        W(k, apply_kts(R(k))); return
    if g.exists():
        W(g, apply_groovy(R(g))); return
    # если внезапно нет — создаём KTS-вариант
    W(k, apply_kts("""plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android { compileSdk = 34; defaultConfig {} } dependencies {}"""))

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/patch_android.py app_dir", file=sys.stderr); sys.exit(1)
    app = pathlib.Path(sys.argv[1]).resolve()
    # 1) settings.gradle.kts — ПОЛНАЯ замена (пин версий)
    force_settings_kts(app)
    # 2) gradle wrapper -> 8.6
    set_wrapper(app)
    # 3) Manifest
    patch_manifest(app)
    # 4) app/build.gradle(.kts)
    patch_app_gradle(app)
    print(f"✅ settings.gradle.kts pinned to AGP {AGP}, Kotlin {KOTLIN}; wrapper {GRADLE}; app/manifest patched.")

if __name__ == "__main__":
    main()
