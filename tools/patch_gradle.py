#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys, re, pathlib

ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
if not ROOT or not ROOT.exists():
    print("Usage: python3 tools/patch_gradle.py app/android")
    sys.exit(1)

WRAPPER = ROOT / "gradle" / "wrapper" / "gradle-wrapper.properties"
APP_G = ROOT / "app" / "build.gradle"
APP_K = ROOT / "app" / "build.gradle.kts"

DESUGAR = "2.1.2"
GRADLE = "https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip"

def rd(p): return p.read_text(encoding="utf-8") if p.exists() else ""
def wr(p,s): p.parent.mkdir(parents=True, exist_ok=True); p.write_text(s, encoding="utf-8")

# gradle-wrapper → 8.11.1
w = rd(WRAPPER)
if w:
    w2 = re.sub(r"distributionUrl=.*", f"distributionUrl={GRADLE}", w)
    if w2 != w:
        wr(WRAPPER, w2)

def patch_groovy(s: str) -> str:
    if "import org.gradle.api.JavaVersion" not in s:
        s = "import org.gradle.api.JavaVersion\n" + s
    # namespace / compileSdk sane defaults if missing (idempotent)
    if "namespace" not in s:
        s = s.replace("android {", "android {\n    namespace \"com.naivefox.bp_logger\"\n", 1)
    s = s.replace("VERSION_1_8", "VERSION_17")
    if "compileOptions" not in s:
        s = re.sub(r"android\s*{", "android {\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n        coreLibraryDesugaringEnabled true\n    }\n", s, count=1)
    else:
        s = re.sub(r"compileOptions\s*{[^}]*}", lambda m: re.sub(r"}\s*$", "    sourceCompatibility JavaVersion.VERSION_17\n    targetCompatibility JavaVersion.VERSION_17\n    coreLibraryDesugaringEnabled true\n}", m.group(0)), s, count=1, flags=re.DOTALL)
    if "kotlinOptions" not in s:
        s = s.replace("android {", "android {\n    kotlinOptions { jvmTarget = '17' }\n", 1)
    else:
        s = re.sub(r"kotlinOptions\s*{[^}]*}", lambda m: re.sub(r"jvmTarget\s*=\s*['\"]?1\.8['\"]?", "jvmTarget = '17'", m.group(0)), s, count=1)
    if "coreLibraryDesugaring" not in s:
        s = re.sub(r"dependencies\s*{", "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:%s'" % DESUGAR, s, count=1)
    return s

def patch_kts(s: str) -> str:
    if "import org.gradle.api.JavaVersion" not in s:
        s = "import org.gradle.api.JavaVersion\n" + s
    if "namespace" not in s:
        s = s.replace("android {", "android {\n    namespace = \"com.naivefox.bp_logger\"\n", 1)
    s = s.replace("VERSION_1_8", "VERSION_17")
    if "compileOptions" not in s:
        s = re.sub(r"android\s*{", "android {\n    compileOptions {\n        sourceCompatibility = JavaVersion.VERSION_17\n        targetCompatibility = JavaVersion.VERSION_17\n        isCoreLibraryDesugaringEnabled = true\n    }\n", s, count=1)
    else:
        s = re.sub(r"compileOptions\s*{[^}]*}", lambda m: re.sub(r"}\s*$", "    isCoreLibraryDesugaringEnabled = true\n}", m.group(0)), s, count=1, flags=re.DOTALL)
    if "kotlinOptions" not in s:
        s = s.replace("android {", "android {\n    kotlinOptions { jvmTarget = \"17\" }\n", 1)
    else:
        s = re.sub(r"kotlinOptions\s*{[^}]*}", lambda m: re.sub(r"jvmTarget\s*=\s*['\"]?1\.8['\"]?", "jvmTarget = \"17\"", m.group(0)), s, count=1)
    if "coreLibraryDesugaring(" not in s:
        s = re.sub(r"dependencies\s*{", "dependencies {\n    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:%s\")" % DESUGAR, s, count=1)
    return s

g = rd(APP_G)
k = rd(APP_K)
if g:
    s2 = patch_groovy(g)
    if s2 != g: wr(APP_G, s2)
if k:
    s2 = patch_kts(k)
    if s2 != k: wr(APP_K, s2)

print("[ok] Gradle patched (Java17 + desugaring + namespace)")
