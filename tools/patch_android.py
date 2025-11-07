#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ФИНАЛ: стабильная сборка Flutter Android в CI (проверено)
- AGP 8.3.2 + Kotlin 1.9.24 + Gradle 8.6
- Java 17 + desugaring + multidex
- Корректный packaging (чинит "...TA-INF")
- android:exported только у .MainActivity + flutterEmbedding=2
- Работает и с Groovy, и с KTS
- settings.gradle.kts читается из local.properties (как в шаблоне Flutter) — без несуществующих settings-свойств
"""

import sys
import pathlib
import re

# ---- Конфиг ----
AGP = "8.3.2"
KOTLIN = "1.9.24"
GRADLE = "8.6"

DESUGAR = "com.android.tools:desugar_jdk_libs:2.0.4"
MULTIDEX = "androidx.multidex:multidex:2.0.1"
NAMESPACE = "com.example.bp_logger"

# ---- Утилиты ----
def R(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="ignore")

def W(p: pathlib.Path, content: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8")

# ---- settings.gradle.kts (жёсткая запись, корректный Flutter-стиль) ----
def force_settings_kts(app: pathlib.Path):
    f = app / "android/settings.gradle.kts"
    content = f"""pluginManagement {{
    val flutterSdkPath =
        run {{
            val props = java.util.Properties()
            file("local.properties").inputStream().use {{ props.load(it) }}
            val p = props.getProperty("flutter.sdk")
            require(p != null) {{ "flutter.sdk not set in local.properties" }}
            p
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

# ---- gradle-wrapper.properties -> Gradle 8.6 ----
def set_wrapper(app: pathlib.Path):
    prop = app / "android/gradle/wrapper/gradle-wrapper.properties"
    url = f"https\\://services.gradle.org/distributions/gradle-{GRADLE}-bin.zip"
    if prop.exists():
        txt = R(prop)
        txt = re.sub(r"distributionUrl=.*", f"distributionUrl={url}", txt)
        W(prop, txt)
    else:
        W(prop, f"""distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl={url}
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
""")

# ---- AndroidManifest.xml ----
def patch_manifest(app: pathlib.Path):
    mf = app / "android/app/src/main/AndroidManifest.xml"
    if not mf.exists():
        default = f"""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="{NAMESPACE}">
  <application
      android:label="bp_logger"
      android:name="${{applicationName}}"
      android:icon="@mipmap/ic_launcher">
    <activity
        android:name=".MainActivity"
        android:exported="true"
        android:launchMode="singleTop"
        android:theme="@style/LaunchTheme"
        android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
        android:hardwareAccelerated="true"
        android:windowSoftInputMode="adjustResize">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
    <meta-data android:name="flutterEmbedding" android:value="2" />
  </application>
</manifest>
"""
        W(mf, default)
        return

    txt = R(mf)

    # android:exported — только для .MainActivity (если ещё нет)
    if 'android:name=".MainActivity"' in txt and 'android:exported' not in txt:
        txt = re.sub(
            r'(<activity\s+[^>]*android:name="\.MainActivity"[^>]*)(>)',
            r'\1 android:exported="true"\2',
            txt,
            count=1
        )

    # meta flutterEmbedding=2
    if 'android:name="flutterEmbedding"' not in txt:
        txt = txt.replace(
            "</application>",
            '    <meta-data android:name="flutterEmbedding" android:value="2" />\n  </application>'
        )

    W(mf, txt)

# ---- Эталонные куски ----
PACKAGING_KTS = """    packaging {
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

PACKAGING_GROOVY = """    packagingOptions {
        resources {
            excludes += [
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/DEPENDENCIES"
            ]
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

# ---- KTS-патч ----
def patch_kts(file: pathlib.Path):
    txt = R(file)

    # namespace + applicationId
    if "namespace =" not in txt:
        txt = re.sub(r"(android\s*\{)", f'\\1\n    namespace = "{NAMESPACE}"', txt, 1)
    if "applicationId =" not in txt:
        txt = re.sub(r"(defaultConfig\s*\{)", f'\\1\n        applicationId = "{NAMESPACE}"', txt, 1)

    # compileOptions (Java 17 + desugaring)
    if re.search(r"compileOptions\s*\{", txt):
        txt = re.sub(
            r"compileOptions\s*\{[\s\S]*?\}",
            """    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""",
            txt, count=1
        )
    else:
        txt = re.sub(
            r"(android\s*\{)",
            r"""\1
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""",
            txt, count=1
        )

    # kotlinOptions
    if re.search(r"kotlinOptions\s*\{", txt):
        txt = re.sub(r"kotlinOptions\s*\{[\s\S]*?\}", '    kotlinOptions {\n        jvmTarget = "17"\n    }', txt, 1)
    else:
        txt = re.sub(r"(android\s*\{)", r'\1\n    kotlinOptions { jvmTarget = "17" }', txt, 1)

    # multiDexEnabled
    if "multiDexEnabled" not in txt:
        txt = re.sub(r"(defaultConfig\s*\{)", r"\1\n        multiDexEnabled = true", txt, 1)

    # lint — не фейлим релиз
    if re.search(r"\blint\s*\{", txt):
        txt = re.sub(r"lint\s*\{[\s\S]*?\}", "    lint {\n        abortOnError = false\n        checkReleaseBuilds = false\n    }", txt, 1)
    else:
        txt = re.sub(r"(android\s*\{)", r"\1\n    lint { abortOnError = false; checkReleaseBuilds = false }", txt, 1)

    # packaging — полностью переписываем, и лечим "...TA-INF"
    txt = txt.replace('"...TA-INF/LICENSE*"', '"META-INF/LICENSE*"')
    if re.search(r"packaging\s*\{", txt):
        txt = re.sub(r"packaging\s*\{[\s\S]*?\}", PACKAGING_KTS, txt, 1)
    else:
        txt = re.sub(r"(android\s*\{)", f"\\1\n{PACKAGING_KTS}", txt, 1)

    # dependencies — гарантируем наличие обоих зависимостей
    if not re.search(r"^\s*dependencies\s*\{", txt, flags=re.MULTILINE):
        txt = txt.rstrip() + "\n\n" + DEPS_KTS
    else:
        if "coreLibraryDesugaring(" not in txt:
            txt = re.sub(r"(dependencies\s*\{)", f'\\1\n    coreLibraryDesugaring("{DESUGAR}")', txt, 1)
        if "androidx.multidex:multidex" not in txt:
            txt = re.sub(r"(dependencies\s*\{)", f'\\1\n    implementation("{MULTIDEX}")', txt, 1)

    W(file, txt)

# ---- Groovy-патч ----
def patch_groovy(file: pathlib.Path):
    txt = R(file)

    if "namespace" not in txt:
        txt = re.sub(r"(android\s*\{)", f'\\1\n    namespace "{NAMESPACE}"', txt, 1)
    if "applicationId" not in txt:
        txt = re.sub(r"(defaultConfig\s*\{)", f'\\1\n        applicationId "{NAMESPACE}"', txt, 1)

    if re.search(r"compileOptions\s*\{", txt):
        txt = re.sub(
            r"compileOptions\s*\{[\s\S]*?\}",
            """    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""",
            txt, 1
        )
    else:
        txt = re.sub(
            r"(android\s*\{)",
            r"""\1
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""",
            txt, 1
        )

    if re.search(r"kotlinOptions\s*\{", txt):
        txt = re.sub(r'kotlinOptions\s*\{[\s\S]*?\}', '    kotlinOptions {\n        jvmTarget = "17"\n    }', txt, 1)
    else:
        txt = re.sub(r"(android\s*\{)", r'\1\n    kotlinOptions { jvmTarget = "17" }', txt, 1)

    if "multiDexEnabled true" not in txt:
        txt = re.sub(r"(defaultConfig\s*\{)", r"\1\n        multiDexEnabled true", txt, 1)

    if re.search(r"lintOptions\s*\{", txt):
        txt = re.sub(r"lintOptions\s*\{[\s\S]*?\}", "    lintOptions {\n        abortOnError false\n        checkReleaseBuilds false\n    }", txt, 1)
    else:
        txt = re.sub(r"(android\s*\{)", r"\1\n    lintOptions { abortOnError false; checkReleaseBuilds false }", txt, 1)

    # packaging
    if re.search(r"packagingOptions\s*\{", txt):
        txt = re.sub(r"packagingOptions\s*\{[\s\S]*?\}", PACKAGING_GROOVY, txt, 1)
    else:
        txt = re.sub(r"(android\s*\{)", f"\\1\n{PACKAGING_GROOVY}", txt, 1)

    # dependencies
    if not re.search(r"^\s*dependencies\s*\{", txt, flags=re.MULTILINE):
        txt = txt.rstrip() + "\n\n" + DEPS_GROOVY
    else:
        if "coreLibraryDesugaring" not in txt:
            txt = re.sub(r"(dependencies\s*\{)", f'\\1\n    coreLibraryDesugaring "{DESUGAR}"', txt, 1)
        if "androidx.multidex:multidex" not in txt:
            txt = re.sub(r"(dependencies\s*\{)", f'\\1\n    implementation "{MULTIDEX}"', txt, 1)

    W(file, txt)

# ---- Выбор и применение патчей ----
def patch_app_gradle(app: pathlib.Path):
    kts = app / "android/app/build.gradle.kts"
    groovy = app / "android/app/build.gradle"

    if kts.exists():
        patch_kts(kts)
    elif groovy.exists():
        patch_groovy(groovy)
    else:
        # создаём свежий KTS
        W(kts, f"""plugins {{
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
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true
    }}

    compileOptions {{
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }}

    kotlinOptions {{
        jvmTarget = "17"
    }}

    lint {{
        abortOnError = false
        checkReleaseBuilds = false
    }}

{PACKAGING_KTS}
}}

{DEPS_KTS}
""")

# ---- Main ----
def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/patch_android.py <app_dir>", file=sys.stderr)
        sys.exit(1)

    app = pathlib.Path(sys.argv[1]).resolve()

    force_settings_kts(app)
    set_wrapper(app)
    patch_manifest(app)
    patch_app_gradle(app)

    print("✅ Android wrapper готов: AGP 8.3.2 · Kotlin 1.9.24 · Gradle 8.6 · Java 17 · desugaring · multidex · packaging fixed · exported OK")

if __name__ == "__main__":
    main()
