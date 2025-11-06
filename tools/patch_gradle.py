#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Идемпотентный патчер Gradle:
- gradle-wrapper -> 8.11.1
- Java 17, kotlin jvmTarget=17
- coreLibraryDesugaringEnabled + desugar_jdk_libs
Запуск из КОРНЯ репо:  python3 tools/patch_gradle.py app/android
"""

import sys, re, pathlib

ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
if not ROOT or not ROOT.exists():
    print("Usage: python3 tools/patch_gradle.py app/android")
    sys.exit(1)

WRAPPER = ROOT / "gradle" / "wrapper" / "gradle-wrapper.properties"
APP_GROOVY = ROOT / "app" / "build.gradle"
APP_KTS    = ROOT / "app" / "build.gradle.kts"

DESUGAR_VER = "2.1.2"
GRADLE_URL  = "https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip"

def rd(p): return p.read_text(encoding="utf-8") if p.exists() else ""
def wr(p,s): p.write_text(s, encoding="utf-8")

# 1) wrapper -> 8.11.1
w = rd(WRAPPER)
if w:
    w2 = re.sub(r"distributionUrl=.*", f"distributionUrl={GRADLE_URL}", w)
    if w2 != w:
        wr(WRAPPER, w2)
        print("[patch] gradle-wrapper -> 8.11.1")

def patch_groovy(s: str) -> str:
    # import JavaVersion если надо
    if not s.lstrip().startswith("import org.gradle.api.JavaVersion"):
        s = "import org.gradle.api.JavaVersion\n" + s
    # compileOptions
    if "compileOptions" not in s:
        s = re.sub(r"android\s*{",
                   "android {\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n        coreLibraryDesugaringEnabled true\n    }\n",
                   s, count=1)
    else:
        s = re.sub(r"compileOptions\s*{[^}]*}",
                   lambda m: re.sub(r"}\s*$",
                                    "    sourceCompatibility JavaVersion.VERSION_17\n"
                                    "    targetCompatibility JavaVersion.VERSION_17\n"
                                    "    coreLibraryDesugaringEnabled true\n}", m.group(0)),
                   s, count=1, flags=re.DOTALL)
        s = s.replace("VERSION_1_8", "VERSION_17")
    # kotlinOptions
    if "kotlinOptions" not in s:
        s = s.replace("android {", "android {\n    kotlinOptions { jvmTarget = '17' }\n", 1)
    else:
        s = re.sub(r"kotlinOptions\s*{[^}]*}",
                   lambda m: re.sub(r"jvmTarget\s*=\s*['\"]?1\.8['\"]?", "jvmTarget = '17'", m.group(0)),
                   s, count=1)
    # dependency
    if not re.search(r"coreLibraryDesugaring\s+['\"]", s):
        s = re.sub(r"dependencies\s*{",
                   "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:%s'" % DESUGAR_VER,
                   s, count=1)
    return s

def patch_kts(s: str) -> str:
    # import JavaVersion
    if not s.lstrip().startswith("import org.gradle.api.JavaVersion"):
        s = "import org.gradle.api.JavaVersion\n" + s
    # compileOptions
    if "compileOptions" not in s:
        s = re.sub(r"android\s*{",
                   "android {\n    compileOptions {\n        sourceCompatibility = JavaVersion.VERSION_17\n        targetCompatibility = JavaVersion.VERSION_17\n        isCoreLibraryDesugaringEnabled = true\n    }\n",
                   s, count=1)
    else:
        s = s.replace("VERSION_1_8", "VERSION_17")
        s = re.sub(r"compileOptions\s*{[^}]*}",
                   lambda m: re.sub(r"}\s*$",
                                    "    isCoreLibraryDesugaringEnabled = true\n}", m.group(0)),
                   s, count=1, flags=re.DOTALL)
    # kotlinOptions
    if "kotlinOptions" not in s:
        s = s.replace("android {", "android {\n    kotlinOptions { jvmTarget = \"17\" }\n", 1)
    else:
        s = re.sub(r"kotlinOptions\s*{[^}]*}",
                   lambda m: re.sub(r"jvmTarget\s*=\s*['\"]?1\.8['\"]?", "jvmTarget = \"17\"", m.group(0)),
                   s, count=1)
    # dependency
    if "coreLibraryDesugaring(" not in s:
        s = re.sub(r"dependencies\s*{",
                   "dependencies {\n    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:%s\")" % DESUGAR_VER,
                   s, count=1)
    return s

if APP_GROOVY.exists():
    g = rd(APP_GROOVY)
    g2 = patch_groovy(g)
    if g2 != g:
        wr(APP_GROOVY, g2)
        print("[patch] app/build.gradle (groovy)")

if APP_KTS.exists():
    k = rd(APP_KTS)
    k2 = patch_kts(k)
    if k2 != k:
        wr(APP_KTS, k2)
        print("[patch] app/build.gradle.kts (kts)")

print("[ok] Java17 + desugaring ensured")
