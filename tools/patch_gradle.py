#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Стабильная сборка Flutter Android:
- AGP 8.3.2, Gradle Wrapper 8.6, Kotlin 1.9.24, Java 17
- compileSdk/targetSdk 34, minSdk 21
- coreLibraryDesugaring + desugar_jdk_libs 2.0.4
- Поддержка Groovy и Kotlin DSL (build.gradle / build.gradle.kts)
- Flutter plugin loader + flutter maven repo

Запуск:
  python3 tools/patch_gradle.py app
  python3 tools/patch_gradle.py app/android
"""

import sys
import pathlib
import re

AGP_VERSION = "8.3.2"
GRADLE_WRAPPER = "8.6"
KOTLIN_VERSION = "1.9.24"
COMPILE_SDK = "34"
TARGET_SDK = "34"
MIN_SDK = "21"
DESUGAR_VER = "2.0.4"

def r(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="ignore")

def w(p: pathlib.Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8")

def norm(arg: str) -> pathlib.Path:
    base = pathlib.Path(arg).resolve()
    return base.parent if base.name == "android" else base

# ---------- wrapper / properties
def ensure_wrapper(app: pathlib.Path):
    f = app / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"
    body = (
        "distributionBase=GRADLE_USER_HOME\n"
        "distributionPath=wrapper/dists\n"
        f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE_WRAPPER}-bin.zip\n"
        "zipStoreBase=GRADLE_USER_HOME\n"
        "zipStorePath=wrapper/dists\n"
    )
    if f.exists():
        txt = r(f)
        txt = re.sub(r"distributionUrl=.*",
                     f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE_WRAPPER}-bin.zip",
                     txt)
        w(f, txt)
    else:
        w(f, body)

def ensure_gradle_props(app: pathlib.Path):
    f = app / "android" / "gradle.properties"
    txt = r(f) if f.exists() else ""
    want = {
        "org.gradle.jvmargs": "-Xmx3g -Dfile.encoding=UTF-8",
        "android.useAndroidX": "true",
        "android.enableJetifier": "true",
        "org.gradle.java.installations.auto-detect": "true",
        "kotlin.jvm.target.validation.mode": "warning",
    }
    for k, v in want.items():
        if re.search(rf"^{re.escape(k)}=", txt, flags=re.M):
            txt = re.sub(rf"^{re.escape(k)}=.*$", f"{k}={v}", txt, flags=re.M)
        else:
            if txt and not txt.endswith("\n"):
                txt += "\n"
            txt += f"{k}={v}\n"
    w(f, txt)

# ---------- settings.gradle(.kts)
FLUTTER_MAVEN = 'maven { url "https://storage.googleapis.com/download.flutter.io" }'
FLUTTER_MAVEN_KTS = 'maven { url = uri("https://storage.googleapis.com/download.flutter.io") }'

def patch_settings_groovy(f: pathlib.Path):
    txt = r(f) if f.exists() else ""
    if "pluginManagement" not in txt:
        txt = (
            "pluginManagement {\n"
            "    repositories {\n"
            "        gradlePluginPortal()\n"
            "        google()\n"
            "        mavenCentral()\n"
            f"        {FLUTTER_MAVEN}\n"
            "    }\n"
            f"    plugins {{\n"
            f"        id 'com.android.application' version '{AGP_VERSION}'\n"
            f"        id 'org.jetbrains.kotlin.android' version '{KOTLIN_VERSION}'\n"
            f"        id 'dev.flutter.flutter-plugin-loader' version '1.0.0'\n"
            f"    }}\n"
            "}\n\n" + txt
        )
    if "dependencyResolutionManagement" not in txt:
        txt += (
            "dependencyResolutionManagement {\n"
            "    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)\n"
            "    repositories {\n"
            "        google()\n"
            "        mavenCentral()\n"
            f"        {FLUTTER_MAVEN}\n"
            "    }\n"
            "}\n"
        )
    if "include" not in txt or ":app" not in txt:
        txt += "\ninclude ':app'\n"
    # на всякий — allprojects
    if "allprojects" not in txt:
        txt += (
            "\nallprojects {\n"
            "    repositories {\n"
            "        google()\n"
            "        mavenCentral()\n"
            f"        {FLUTTER_MAVEN}\n"
            "    }\n"
            "}\n"
        )
    w(f, txt)

def patch_settings_kts(f: pathlib.Path):
    txt = r(f) if f.exists() else ""
    if "pluginManagement" not in txt:
        txt = (
            "pluginManagement {\n"
            "    repositories {\n"
            "        gradlePluginPortal()\n"
            "        google()\n"
            "        mavenCentral()\n"
            f"        {FLUTTER_MAVEN_KTS}\n"
            "    }\n"
            f"    plugins {{\n"
            f"        id(\"com.android.application\") version \"{AGP_VERSION}\"\n"
            f"        id(\"org.jetbrains.kotlin.android\") version \"{KOTLIN_VERSION}\"\n"
            f"        id(\"dev.flutter.flutter-plugin-loader\") version \"1.0.0\"\n"
            "    }\n"
            "}\n\n" + txt
        )
    if "dependencyResolutionManagement" not in txt:
        txt += (
            "dependencyResolutionManagement {\n"
            "    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)\n"
            "    repositories {\n"
            "        google()\n"
            "        mavenCentral()\n"
            f"        {FLUTTER_MAVEN_KTS}\n"
            "    }\n"
            "}\n"
        )
    if "include(" not in txt or ":app" not in txt:
        txt += '\ninclude(":app")\n'
    if "allprojects" not in txt:
        txt += (
            "\nallprojects {\n"
            "    repositories {\n"
            "        google()\n"
            "        mavenCentral()\n"
            f"        {FLUTTER_MAVEN_KTS}\n"
            "    }\n"
            "}\n"
        )
    w(f, txt)

# ---------- root build.gradle(.kts)
def patch_root_groovy(f: pathlib.Path):
    txt = r(f) if f.exists() else ""
    if "plugins" not in txt:
        txt = (
            "plugins {\n"
            "    id \"com.android.application\" apply false\n"
            "    id \"org.jetbrains.kotlin.android\" apply false\n"
            "}\n\n" + txt
        )
    w(f, txt or "// Generated by patch_gradle.py\n")

def patch_root_kts(f: pathlib.Path):
    txt = r(f) if f.exists() else ""
    if "plugins" not in txt:
        txt = (
            "plugins {\n"
            "    id(\"com.android.application\") apply false\n"
            "    id(\"org.jetbrains.kotlin.android\") apply false\n"
            "}\n\n" + txt
        )
    w(f, txt or "// Generated by patch_gradle.py\n")

# ---------- app build.gradle(.kts)
def patch_app_groovy(f: pathlib.Path):
    if not f.exists():
        w(f, f"""// Generated by patch_gradle.py
plugins {{
    id "com.android.application"
    id "org.jetbrains.kotlin.android"
    id "dev.flutter.flutter-plugin-loader"
}}

android {{
    namespace "com.example.bp_logger"
    compileSdk {COMPILE_SDK}

    defaultConfig {{
        applicationId "com.example.bp_logger"
        minSdk {MIN_SDK}
        targetSdk {TARGET_SDK}
        versionCode 1
        versionName "1.0"
    }}

    buildTypes {{
        release {{
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }}
    }}

    compileOptions {{
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }}
    kotlinOptions {{
        jvmTarget = "17"
    }}
}}

dependencies {{
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:{DESUGAR_VER}"
}}
""")
        return

    txt = r(f)
    if "plugins" in txt and "dev.flutter.flutter-plugin-loader" not in txt:
        txt = re.sub(r"plugins\s*\{", 'plugins {\n    id "dev.flutter.flutter-plugin-loader"', txt, count=1)
    elif "plugins" not in txt:
        txt = 'plugins {\n    id "dev.flutter.flutter-plugin-loader"\n}\n' + txt

    if "namespace" not in txt:
        txt = re.sub(r"android\s*\{", 'android {\n    namespace "com.example.bp_logger"', txt, count=1)

    txt = re.sub(r"compileSdk\s+\d+", f"compileSdk {COMPILE_SDK}", txt) if re.search(r"compileSdk\s+\d+", txt) \
        else re.sub(r"android\s*\{", f"android {{\n    compileSdk {COMPILE_SDK}", txt, count=1)

    txt = re.sub(r"minSdk\s+\d+", f"minSdk {MIN_SDK}", txt) if re.search(r"minSdk\s+\d+", txt) \
        else re.sub(r"defaultConfig\s*\{", f"defaultConfig {{\n        minSdk {MIN_SDK}", txt, count=1)

    txt = re.sub(r"targetSdk\s+\d+", f"targetSdk {TARGET_SDK}", txt) if re.search(r"targetSdk\s+\d+", txt) \
        else re.sub(r"defaultConfig\s*\{", f"defaultConfig {{\n        targetSdk {TARGET_SDK}", txt, count=1)

    if "compileOptions" in txt:
        txt = re.sub(r"compileOptions\s*\{[\s\S]*?\}",
                     """compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""", txt, count=1)
    else:
        txt = re.sub(r"android\s*\{", """android {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
        coreLibraryDesugaringEnabled true
    }""", txt, count=1)

    if "kotlinOptions" in txt:
        txt = re.sub(r'kotlinOptions\s*\{[\s\S]*?\}', 'kotlinOptions {\n        jvmTarget = "17"\n    }', txt, count=1)
    else:
        txt = re.sub(r"android\s*\{", """android {
    kotlinOptions {
        jvmTarget = "17"
    }""", txt, count=1)

    if "coreLibraryDesugaring" not in txt:
        if "dependencies" in txt:
            txt = re.sub(r"dependencies\s*\{",
                         f"""dependencies {{
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:{DESUGAR_VER}" """,
                         txt, count=1)
        else:
            txt += f"""

dependencies {{
    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:{DESUGAR_VER}"
}}
"""
    w(f, txt)

def patch_app_kts(f: pathlib.Path):
    if not f.exists():
        w(f, f"""// Generated by patch_gradle.py
plugins {{
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-plugin-loader")
}}

android {{
    namespace = "com.example.bp_logger"
    compileSdk = {COMPILE_SDK}

    defaultConfig {{
        applicationId = "com.example.bp_logger"
        minSdk = {MIN_SDK}
        targetSdk = {TARGET_SDK}
        versionCode = 1
        versionName = "1.0"
    }}

    buildTypes {{
        release {{
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }}
    }}

    compileOptions {{
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }}
    kotlinOptions {{
        jvmTarget = "17"
    }}
}}

dependencies {{
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_VER}")
}}
""")
        return

    txt = r(f)
    if "plugins" in txt and "dev.flutter.flutter-plugin-loader" not in txt:
        txt = re.sub(r"plugins\s*\{", 'plugins {\n    id("dev.flutter.flutter-plugin-loader")', txt, count=1)
    elif "plugins" not in txt:
        txt = 'plugins {\n    id("dev.flutter.flutter-plugin-loader")\n}\n' + txt

    # namespace/SDKs
    if re.search(r'namespace\s*=', txt):
        txt = re.sub(r'namespace\s*=\s*".*?"', 'namespace = "com.example.bp_logger"', txt)
    else:
        txt = re.sub(r"android\s*\{", 'android {\n    namespace = "com.example.bp_logger"', txt, count=1)

    txt = re.sub(r"compileSdk\s*=\s*\d+", f"compileSdk = {COMPILE_SDK}", txt) if re.search(r"compileSdk\s*=", txt) \
        else re.sub(r"android\s*\{", f"android {{\n    compileSdk = {COMPILE_SDK}", txt, count=1)

    def set_in_default(name, value):
        nonlocal txt
        if re.search(rf"{name}\s*=\s*\d+", txt):
            txt = re.sub(rf"{name}\s*=\s*\d+", f"{name} = {value}", txt)
        else:
            txt = re.sub(r"defaultConfig\s*\{", f"defaultConfig {{\n        {name} = {value}", txt, count=1)

    set_in_default("minSdk", MIN_SDK)
    set_in_default("targetSdk", TARGET_SDK)

    if "compileOptions" in txt:
        txt = re.sub(r"compileOptions\s*\{[\s\S]*?\}",
                     """compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""", txt, count=1)
    else:
        txt = re.sub(r"android\s*\{", """android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion_17
        isCoreLibraryDesugaringEnabled = true
    }""", txt, count=1).replace("JavaVersion_17", "JavaVersion.VERSION_17")

    if "kotlinOptions" in txt:
        txt = re.sub(r'kotlinOptions\s*\{[\s\S]*?\}', 'kotlinOptions {\n        jvmTarget = "17"\n    }', txt, count=1)
    else:
        txt = re.sub(r"android\s*\{", """android {
    kotlinOptions {
        jvmTarget = "17"
    }""", txt, count=1)

    if "coreLibraryDesugaring(" not in txt:
        if re.search(r"dependencies\s*\{", txt):
            txt = re.sub(r"dependencies\s*\{",
                         f"""dependencies {{
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_VER}") """,
                         txt, count=1)
        else:
            txt += f"""

dependencies {{
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:{DESUGAR_VER}")
}}
"""
    w(f, txt)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/patch_gradle.py app_or_app_android", file=sys.stderr)
        sys.exit(1)

    app = norm(sys.argv[1])

    ensure_wrapper(app)
    ensure_gradle_props(app)

    s_g = app / "android" / "settings.gradle"
    s_k = app / "android" / "settings.gradle.kts"
    if s_k.exists() or (not s_g.exists() and not s_k.exists()):
        patch_settings_kts(s_k)
    else:
        patch_settings_groovy(s_g)

    r_g = app / "android" / "build.gradle"
    r_k = app / "android" / "build.gradle.kts"
    if r_k.exists() or (not r_g.exists() and not r_k.exists()):
        patch_root_kts(r_k)
    else:
        patch_root_groovy(r_g)

    a_g = app / "android" / "app" / "build.gradle"
    a_k = app / "android" / "app" / "build.gradle.kts"
    if a_k.exists() or (not a_g.exists() and not a_k.exists()):
        patch_app_kts(a_k)
    else:
        patch_app_groovy(a_g)

    print("✅ Patched: AGP 8.3.2 / Gradle 8.6 / Kotlin 1.9.24 / Java 17 / desugaring / flutter plugin-loader & repo.")

if __name__ == "__main__":
    main()
