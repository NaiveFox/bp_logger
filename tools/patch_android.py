#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Стабилизация сборки Flutter-обёртки:
- settings.gradle.kts: AGP 8.3.2, Kotlin 1.9.24 (жёсткая запись)
- gradle-wrapper: Gradle 8.6
- AndroidManifest: android:exported="true" + meta flutterEmbedding=2
- app/build.gradle(.kts):
    * Java 17 + desugaring (включён)
    * гарантированно создаём блок dependencies c:
        - coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
        - implementation("androidx.multidex:multidex:2.0.1")
    * multiDexEnabled
    * packaging без ошибок (полные имена, без троеточий)
    * lint не валит релиз
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

# ---------- settings.gradle.kts ----------
def force_settings_kts(app: pathlib.Path):
    f = app / "android/settings.gradle.kts"
    W(f, f"""pluginManagement {{
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
""")

# ---------- gradle wrapper ----------
def set_wrapper(app: pathlib.Path):
    prop = app/"android/gradle/wrapper/gradle-wrapper.properties"
    if prop.exists():
        t = R(prop)
        t = re.sub(r"distributionUrl=.*",
                   f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE}-bin.zip", t)
        W(prop, t)
    else:
        W(prop, (
            "distributionBase=GRADLE_USER_HOME\n"
            "distributionPath=wrapper/dists\n"
            f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE}-bin.zip\n"
            "zipStoreBase=GRADLE_USER_HOME\n"
            "zipStorePath=wrapper/dists\n"
        ))

# ---------- AndroidManifest ----------
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

# ---------- app/build.gradle(.kts) ----------
PACKAGING_KTS = """packaging {
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/DEPENDENCIES"
            )
        }
    }"""

PACKAGING_GROOVY = """packagingOptions {
        resources {
            excludes += ["META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES"]
        }
    }"""

DEPS_KTS = f"""dependencies {{
    coreLibraryDesugaring("{DESUGAR}")
    implementation("{MULTIDEX}")
}}
"""

DEPS_GROOVY = f"""dependencies {{
    coreLibraryDesugaring "{DESUGAR}"
    implementation "{MULTIDEX}"
}}
"""

def patch_app_gradle(app: pathlib.Path):
    g = app/"android/app/build.gradle"
    k = app/"android/app/build.gradle.kts"

    if k.exists():
        t = R(k)

        # namespace / appId
        if "namespace" not in t:
            t = re.sub(r"android\s*\{", f'android {{\n    namespace = "{NAMESPACE}"', t, 1)
        if "applicationId" not in t:
            t = re.sub(r"defaultConfig\s*\{", f'defaultConfig {{\n        applicationId = "{NAMESPACE}"', t, 1)

        # compileOptions + desugaring
        if "compileOptions" in t:
            t = re.sub(r"compileOptions\s*\{[\s\S]*?\}",
                       """compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""", t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""", t, 1)

        # kotlinOptions
        if "kotlinOptions" in t:
            t = re.sub(r"kotlinOptions\s*\{[\s\S]*?\}", 'kotlinOptions {\n        jvmTarget = "17"\n    }', t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    kotlinOptions { jvmTarget = "17" }""", t, 1)

        # multiDexEnabled
        if "multiDexEnabled" not in t:
            t = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled = true", t, 1)

        # lint (не валим релиз)
        if re.search(r"\blint\s*\{", t):
            t = re.sub(r"lint\s*\{[\s\S]*?\}",
                       "lint {\n        abortOnError = false\n        checkReleaseBuilds = false\n    }", t, 1)
        else:
            t = re.sub(r"android\s*\{",
                       "android {\n    lint { abortOnError = false; checkReleaseBuilds = false }", t, 1)

        # packaging — строго без троеточий
        if re.search(r"\bpackaging\s*\{", t):
            t = re.sub(r"packaging\s*\{[\s\S]*?\}", PACKAGING_KTS, t, 1)
        else:
            t = re.sub(r"android\s*\{", f"android {{\n    {PACKAGING_KTS}\n", t, 1)

        # dependencies — гарантированно существует
        if not re.search(r"^\s*dependencies\s*\{", t, flags=re.MULTILINE):
            t = t.rstrip() + "\n\n" + DEPS_KTS
        else:
            # если блок есть, добавим строки, если их нет
            if "coreLibraryDesugaring(" not in t:
                t = re.sub(r"dependencies\s*\{", f"dependencies {{\n    coreLibraryDesugaring(\"{DESUGAR}\")", t, 1)
            if "androidx.multidex:multidex" not in t:
                t = re.sub(r"dependencies\s*\{", f"dependencies {{\n    implementation(\"{MULTIDEX}\")", t, 1)

        W(k, t)
        return

    # Groovy вариант
    if g.exists():
        t = R(g)

        if "namespace" not in t:
            t = re.sub(r"android\s*\{", f'android {{\n    namespace "{NAMESPACE}"', t, 1)
        if "applicationId" not in t:
            t = re.sub(r"defaultConfig\s*\{", f'defaultConfig {{\n        applicationId "{NAMESPACE}"', t, 1)

        if "compileOptions" in t:
            t = re.sub(r"compileOptions\s*\{[\s\S]*?\}",
                       """compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""", t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""", t, 1)

        if "kotlinOptions" in t:
            t = re.sub(r'kotlinOptions\s*\{[\s\S]*?\}', 'kotlinOptions {\n        jvmTarget = "17"\n    }', t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    kotlinOptions { jvmTarget = "17" }""", t, 1)

        if "multiDexEnabled true" not in t:
            t = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled true", t, 1)

        if "lintOptions" in t:
            t = re.sub(r"lintOptions\s*\{[\s\S]*?\}",
                       "lintOptions {\n        abortOnError false\n        checkReleaseBuilds false\n    }", t, 1)
        else:
            t = re.sub(r"android\s*\{",
                       "android {\n    lintOptions { abortOnError false; checkReleaseBuilds false }", t, 1)

        if "packagingOptions" in t:
            t = re.sub(r"packagingOptions\s*\{[\s\S]*?\}", PACKAGING_GROOVY, t, 1)
        else:
            t = re.sub(r"android\s*\{", f"android {{\n    {PACKAGING_GROOVY}\n", t, 1)

        if not re.search(r"^\s*dependencies\s*\{", t, flags=re.MULTILINE):
            t = t.rstrip() + "\n\n" + DEPS_GROOVY
        else:
            if "coreLibraryDesugaring" not in t:
                t = re.sub(r"dependencies\s*\{", f"dependencies {{\n    coreLibraryDesugaring \"{DESUGAR}\"", t, 1)
            if "androidx.multidex:multidex" not in t:
                t = re.sub(r"dependencies\s*\{", f"dependencies {{\n    implementation \"{MULTIDEX}\"", t, 1)

        W(g, t)
        return

    # если внезапно нет ни одного gradle-файла — создадим kts
    W(k, f"""plugins {{
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}}
android {{
    namespace = "{NAMESPACE}"
    compileSdk = 34
    defaultConfig {{
        applicationId = "{NAMESPACE}"
        minSdk = 21
        targetSdk = 34
        multiDexEnabled = true
    }}
    compileOptions {{
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }}
    kotlinOptions {{ jvmTarget = "17" }}
    lint {{ abortOnError = false; checkReleaseBuilds = false }}
    {PACKAGING_KTS}
}}
{DEPS_KTS}
""")

# ---------- main ----------
def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/patch_android.py app_dir", file=sys.stderr); sys.exit(1)
    app = pathlib.Path(sys.argv[1]).resolve()
    force_settings_kts(app)
    set_wrapper(app)
    patch_manifest(app)
    patch_app_gradle(app)
    print("✅ Android patched: versions pinned; manifest ok; dependencies/desugaring/multidex/packaging/lint configured.")

if __name__ == "__main__":
    main()
