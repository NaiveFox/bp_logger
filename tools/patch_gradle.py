#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Патчим Flutter Android-проект под стабильную сборку:
- AGP 8.3.2
- Gradle Wrapper 8.6
- Kotlin 1.9.24
- Java 17 (jvmTarget 17)
- compileSdk/targetSdk 34, minSdk 21
- coreLibraryDesugaring (+ desugar_jdk_libs 2.0.4)
- settings.gradle(.kts) с pluginManagement и репозиториями
Работает с Groovy и Kotlin DSL (build.gradle / build.gradle.kts).

Запуск:
  python3 tools/patch_gradle.py app
  python3 tools/patch_gradle.py app/android   # тоже ок
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

def ptext(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8", errors="ignore")

def wtext(p: pathlib.Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8")

def norm_app_dir(arg: str) -> pathlib.Path:
    base = pathlib.Path(arg).resolve()
    return base.parent if base.name == "android" else base

# ----- wrapper / properties
def ensure_wrapper(app_dir: pathlib.Path):
    f = app_dir / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"
    body = (
        "distributionBase=GRADLE_USER_HOME\n"
        "distributionPath=wrapper/dists\n"
        f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE_WRAPPER}-bin.zip\n"
        "zipStoreBase=GRADLE_USER_HOME\n"
        "zipStorePath=wrapper/dists\n"
    )
    if f.exists():
        txt = ptext(f)
        txt = re.sub(r"distributionUrl=.*",
                     f"distributionUrl=https\\://services.gradle.org/distributions/gradle-{GRADLE_WRAPPER}-bin.zip",
                     txt)
        wtext(f, txt)
    else:
        wtext(f, body)

def ensure_gradle_properties(app_dir: pathlib.Path):
    f = app_dir / "android" / "gradle.properties"
    txt = ptext(f) if f.exists() else ""
    want = {
        "org.gradle.jvmargs": "-Xmx3g -Dfile.encoding=UTF-8",
        "android.useAndroidX": "true",
        "android.enableJetifier": "true",
        "org.gradle.java.installations.auto-detect": "true",
        # смягчим валидацию jvmTarget
        "kotlin.jvm.target.validation.mode": "warning",
    }
    for k, v in want.items():
        if re.search(rf"^{re.escape(k)}=", txt, flags=re.M):
            txt = re.sub(rf"^{re.escape(k)}=.*$", f"{k}={v}", txt, flags=re.M)
        else:
            if txt and not txt.endswith("\n"):
                txt += "\n"
            txt += f"{k}={v}\n"
    wtext(f, txt)

# ----- settings.gradle(.kts)
def patch_settings_groovy(f: pathlib.Path):
    if f.exists():
        txt = ptext(f)
    else:
        txt = ""

    # pluginManagement с репами и явными версиями плагинов
    if "pluginManagement" not in txt:
        txt = (
            "pluginManagement {\n"
            "    repositories {\n"
            "        gradlePluginPortal()\n"
            "        google()\n"
            "        mavenCentral()\n"
            "    }\n"
            f"    plugins {{\n"
            f"        id 'com.android.application' version '{AGP_VERSION}'\n"
            f"        id 'org.jetbrains.kotlin.android' version '{KOTLIN_VERSION}'\n"
            f"    }}\n"
            "}\n\n" + txt
        )

    # dependencyResolutionManagement
    if "dependencyResolutionManagement" not in txt:
        txt += (
            "dependencyResolutionManagement {\n"
            "    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)\n"
            "    repositories {\n"
            "        google()\n"
            "        mavenCentral()\n"
            "    }\n"
            "}\n"
        )

    # include(":app")
    if "include" not in txt or ":app" not in txt:
        txt += "\ninclude ':app'\n"

    wtext(f, txt)

def patch_settings_kts(f: pathlib.Path):
    if f.exists():
        txt = ptext(f)
    else:
        txt = ""

    if "pluginManagement" not in txt:
        txt = (
            "pluginManagement {\n"
            "    repositories {\n"
            "        gradlePluginPortal()\n"
            "        google()\n"
            "        mavenCentral()\n"
            "    }\n"
            f"    plugins {{\n"
            f"        id(\"com.android.application\") version \"{AGP_VERSION}\"\n"
            f"        id(\"org.jetbrains.kotlin.android\") version \"{KOTLIN_VERSION}\"\n"
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
            "    }\n"
            "}\n"
        )

    if "include(" not in txt or ":app" not in txt:
        txt += '\ninclude(":app")\n'

    wtext(f, txt)

# ----- root build.gradle(.kts)
def patch_root_groovy(f: pathlib.Path):
    if not f.exists():
        wtext(f, f"""// Generated by patch_gradle.py
plugins {{
    id "com.android.application" apply false
    id "org.jetbrains.kotlin.android" apply false
}}

task clean(type: Delete) {{
    delete rootProject.buildDir
}}
""")
        return
    # Ничего строгого тут не надо — версии возьмутся из settings.pluginManagement
    # Но убедимся, что plugins-блок есть.
    txt = ptext(f)
    if "plugins" not in txt:
        txt = f"""plugins {{
    id "com.android.application" apply false
    id "org.jetbrains.kotlin.android" apply false
}}
""" + txt
    wtext(f, txt)

def patch_root_kts(f: pathlib.Path):
    if not f.exists():
        wtext(f, f"""// Generated by patch_gradle.py
plugins {{
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}}
""")
        return
    txt = ptext(f)
    if "plugins" not in txt:
        txt = f"""plugins {{
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}}
""" + txt
    wtext(f, txt)

# ----- app/build.gradle(.kts)
def patch_app_groovy(f: pathlib.Path):
    if not f.exists():
        wtext(f, f"""// Generated by patch_gradle.py
plugins {{
    id "com.android.application"
    id "org.jetbrains.kotlin.android"
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

    txt = ptext(f)
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
    wtext(f, txt)

def patch_app_kts(f: pathlib.Path):
    if not f.exists():
        wtext(f, f"""// Generated by patch_gradle.py
plugins {{
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
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

    txt = ptext(f)

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
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }""", txt, count=1)

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
    wtext(f, txt)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tools/patch_gradle.py app_or_app_android", file=sys.stderr)
        sys.exit(1)

    app_dir = norm_app_dir(sys.argv[1])

    ensure_wrapper(app_dir)
    ensure_gradle_properties(app_dir)

    # settings.*
    s_groovy = app_dir / "android" / "settings.gradle"
    s_kts    = app_dir / "android" / "settings.gradle.kts"
    if s_kts.exists() or (not s_groovy.exists() and not s_kts.exists()):
        patch_settings_kts(s_kts)
    else:
        patch_settings_groovy(s_groovy)

    # root build.*
    r_groovy = app_dir / "android" / "build.gradle"
    r_kts    = app_dir / "android" / "build.gradle.kts"
    if r_kts.exists() or (not r_groovy.exists() and not r_kts.exists()):
        patch_root_kts(r_kts)
    else:
        patch_root_groovy(r_groovy)

    # app build.*
    a_groovy = app_dir / "android" / "app" / "build.gradle"
    a_kts    = app_dir / "android" / "app" / "build.gradle.kts"
    if a_kts.exists() or (not a_groovy.exists() and not a_kts.exists()):
        patch_app_kts(a_kts)
    else:
        patch_app_groovy(a_groovy)

    print("✅ Patched settings/build files for AGP 8.3.2 / Gradle 8.6 / Kotlin 1.9.24 / Java 17 with desugaring (Groovy/KTS).")

if __name__ == "__main__":
    main()
