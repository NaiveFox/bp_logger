#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
patch_gradle.py  —  минимальный и идемпотентный патчёр Gradle-проектов Flutter.
Запуск из корня репо:  python3 tools/patch_gradle.py app/android
Делает:
  1) gradle/wrapper/gradle-wrapper.properties -> distributionUrl = gradle-8.11-all.zip (если ниже)
  2) app/build.gradle(.kts): включает coreLibraryDesugaring и зависимость desugar_jdk_libs
  3) app/build.gradle(.kts): compileOptions / kotlinOptions под Java 17
Ничего не ломает, повторные запуски безопасны.
"""

import sys, re, pathlib

ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
if not ROOT or not ROOT.exists():
    print("Usage: patch_gradle.py <path-to-android-dir>, e.g. app/android")
    sys.exit(1)

def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8") if p.exists() else ""

def write(p: pathlib.Path, s: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(s, encoding="utf-8")

# 1) gradle-wrapper.properties -> Gradle 8.11+
wrapper = ROOT / "gradle/wrapper/gradle-wrapper.properties"
w = read(wrapper)
if w:
    w2 = re.sub(r"distributionUrl=.*",
                "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11-all.zip",
                w)
    if w2 != w:
        write(wrapper, w2)
        print("[patch] gradle-wrapper.properties -> 8.11-all")
    else:
        print("[ok] gradle-wrapper already 8.11+")
else:
    print("[warn] gradle-wrapper.properties not found (will be created by flutter create)")

# Определяем groovy/kts
app_gradle_groovy = ROOT / "app/build.gradle"
app_gradle_kts    = ROOT / "app/build.gradle.kts"
is_kts = app_gradle_kts.exists()
app_gradle = app_gradle_kts if is_kts else app_gradle_groovy

g = read(app_gradle)
if not g:
    print(f"[warn] {app_gradle} not found yet. Maybe first run flutter create?")
    sys.exit(0)

# 2) Включаем coreLibraryDesugaring и зависимость
if is_kts:
    if "isCoreLibraryDesugaringEnabled" not in g:
        g = re.sub(r"android\s*{", "android {\n    compileOptions {\n        sourceCompatibility = JavaVersion.VERSION_17\n        targetCompatibility = JavaVersion.VERSION_17\n        isCoreLibraryDesugaringEnabled = true\n    }\n", g, count=1)
    if "kotlinOptions" not in g:
        g = g.replace("android {", "android {\n    kotlinOptions { jvmTarget = \"17\" }\n", 1)
    if "coreLibraryDesugaring(" not in g:
        g = re.sub(r"dependencies\s*{",
                   "dependencies {\n    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:2.0.4\")",
                   g, count=1)
else:
    if "coreLibraryDesugaringEnabled true" not in g:
        # compileOptions + desugaring
        if "compileOptions" not in g:
            g = re.sub(r"android\s*{", "android {\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n        coreLibraryDesugaringEnabled true\n    }\n", g, count=1)
        else:
            g = g.replace("compileOptions {", "compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n        coreLibraryDesugaringEnabled true", 1)
    if "kotlinOptions" not in g:
        g = g.replace("android {", "android {\n    kotlinOptions { jvmTarget = '17' }\n", 1)
    if "coreLibraryDesugaring" not in g:
        g = re.sub(r"dependencies\s*{",
                   "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4'",
                   g, count=1)

write(app_gradle, g)
print(f"[patch] {app_gradle.name}: Java17 + desugaring ensured")
