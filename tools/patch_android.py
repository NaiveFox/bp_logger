#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Жёсткая стабилизация сборки:
- settings.gradle(.kts): пин плагинов на AGP 8.3.2 / Kotlin 1.9.24 + репозитории google/mavenCentral (+ Flutter tools уже есть)
- gradle-wrapper.properties -> Gradle 8.6
- app/build.gradle(.kts): Java 17, desugaring (2.0.4), multidex, packaging, lint (release не падает), namespace/appId
- AndroidManifest: android:exported="true" у MAIN/LAUNCHER activity + meta flutterEmbedding=2
"""

import sys, pathlib, re

AGP = "8.3.2"
KOTLIN = "1.9.24"
GRADLE = "8.6"
DESUGAR = "com.android.tools:desugar_jdk_libs:2.0.4"
MULTIDEX = "androidx.multidex:multidex:2.0.1"
NAMESPACE = "com.example.bp_logger"

def R(p): return p.read_text(encoding="utf-8", errors="ignore")
def W(p, s): p.parent.mkdir(parents=True, exist_ok=True); p.write_text(s, encoding="utf-8")

def pin_settings(path: pathlib.Path):
    # KTS
    if path.with_suffix(".kts").exists():
        f = path.with_suffix(".kts")
        t = R(f)
        # plugins { id("dev.flutter.flutter-plugin-loader") version "1.0.0"
        #          id("com.android.application") version "8.x.x" apply false
        #          id("org.jetbrains.kotlin.android") version "2.x.x" apply false }
        t = re.sub(r'id\("com\.android\.application"\)\s+version\s*".*?"',
                   f'id("com.android.application") version "{AGP}"', t)
        t = re.sub(r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s*".*?"',
                   f'id("org.jetbrains.kotlin.android") version "{KOTLIN}"', t)
        # убедимся в репозиториях
        if "repositories {" in t and "mavenCentral()" not in t:
            t = t.replace("repositories {", "repositories {\n        mavenCentral()")
        W(f, t)
        return
    # Groovy
    if path.exists():
        f = path
        t = R(f)
        t = re.sub(r"id 'com\.android\.application' version '.*?'", 
                   f"id 'com.android.application' version '{AGP}'", t)
        t = re.sub(r"id 'org\.jetbrains\.kotlin\.android' version '.*?'", 
                   f"id 'org.jetbrains.kotlin.android' version '{KOTLIN}'", t)
        if "repositories {" in t and "mavenCentral()" not in t:
            t = t.replace("repositories {", "repositories {\n        mavenCentral()")
        W(f, t)

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
    if k.exists(): # KTS
        t = R(k)
        if "namespace" not in t: t = re.sub(r"android\s*\{", f'android {{\n    namespace = "{NAMESPACE}"', t, 1)
        if "applicationId" not in t: t = re.sub(r"defaultConfig\s*\{", f'defaultConfig {{\n        applicationId = "{NAMESPACE}"', t, 1)
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
        if "kotlinOptions" in t:
            t = re.sub(r"kotlinOptions\s*\{[\s\S]*?\}", 'kotlinOptions {\n        jvmTarget = "17"\n    }', t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    kotlinOptions { jvmTarget = "17" }""", t, 1)
        if "multiDexEnabled" not in t:
            t = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled = true", t, 1)
        # lint
        if re.search(r"\blint\s*\{", t):
            t = re.sub(r"lint\s*\{[\s\S]*?\}", "lint {\n        abortOnError = false\n        checkReleaseBuilds = false\n    }", t, 1)
        else:
            t = re.sub(r"android\s*\{", "android {\n    lint { abortOnError = false; checkReleaseBuilds = false }", t, 1)
        # packaging
        if re.search(r"\bpackaging\s*\{", t):
            t = re.sub(r"packaging\s*\{[\s\S]*?\}", 
                       """packaging {
        resources { excludes += setOf("META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES") }
    }""", t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    packaging { resources { excludes += setOf("META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES") } }""", t, 1)
        # deps
        if "coreLibraryDesugaring(" not in t:
            t = re.sub(r"dependencies\s*\{", f"""dependencies {{
    coreLibraryDesugaring("{DESUGAR}") """, t, 1)
        if "androidx.multidex:multidex" not in t:
            t = re.sub(r"dependencies\s*\{", f"""dependencies {{
    implementation("{MULTIDEX}") """, t, 1)
        W(k, t); return

    # Groovy
    if g.exists():
        t = R(g)
        if "namespace" not in t: t = re.sub(r"android\s*\{", f'android {{\n    namespace "{NAMESPACE}"', t, 1)
        if "applicationId" not in t: t = re.sub(r"defaultConfig\s*\{", f'defaultConfig {{\n        applicationId "{NAMESPACE}"', t, 1)
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
        if "multiDexEnabled" not in t:
            t = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled true", t, 1)
        # lint
        if "lintOptions" in t:
            t = re.sub(r"lintOptions\s*\{[\s\S]*?\}", "lintOptions {\n        abortOnError false\n        checkReleaseBuilds false\n    }", t, 1)
        else:
            t = re.sub(r"android\s*\{", "android {\n    lintOptions { abortOnError false; checkReleaseBuilds false }", t, 1)
        # packaging
        if "packagingOptions" in t:
            t = re.sub(r"packagingOptions\s*\{[\s\S]*?\}", 
                       """packagingOptions {
        resources { excludes += ["META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES"] }
    }""", t, 1)
        else:
            t = re.sub(r"android\s*\{", """android {
    packagingOptions { resources { excludes += ["META-INF/AL2.0","META-INF/LGPL2.1","META-INF/LICENSE*","META-INF/NOTICE*","META-INF/DEPENDENCIES"] } }""", t, 1)
        # deps
        if "coreLibraryDesugaring" not in t:
            t = re.sub(r"dependencies\s*\{", f"""dependencies {{
    coreLibraryDesugaring "{DESUGAR}" """, t, 1)
        if "androidx.multidex:multidex" not in t:
            t = re.sub(r"dependencies\s*\{", f"""dependencies {{
    implementation "{MULTIDEX}" """, t, 1)
        W(g, t)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/patch_android.py app_dir", file=sys.stderr); sys.exit(1)
    app = pathlib.Path(sys.argv[1]).resolve()
    # settings pin
    pin_settings(app/"android/settings.gradle")
    # gradle wrapper
    set_wrapper(app)
    # manifest
    patch_manifest(app)
    # app gradle
    patch_app_gradle(app)
    print(f"✅ Pinned AGP {AGP} / Kotlin {KOTLIN} / Gradle {GRADLE} and patched app/manifest.")

if __name__ == "__main__":
    main()
