#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import re
from pathlib import Path
import sys

def patch_kts(txt: str) -> str:
    if 'isCoreLibraryDesugaringEnabled' not in txt:
        txt = re.sub(
            r'android\s*\{',
            (
                'android {\n'
                '    compileOptions {\n'
                '        sourceCompatibility = JavaVersion.VERSION_17\n'
                '        targetCompatibility = JavaVersion.VERSION_17\n'
                '        isCoreLibraryDesugaringEnabled = true\n'
                '    }\n'
                '    kotlinOptions {\n'
                '        jvmTarget = "17"\n'
                '    }\n'
            ),
            txt, count=1
        )
    if 'coreLibraryDesugaring(' not in txt:
        txt = re.sub(
            r'dependencies\s*\{',
            (
                'dependencies {\n'
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")\n'
            ),
            txt, count=1
        )
    return txt

def patch_groovy(txt: str) -> str:
    if 'coreLibraryDesugaringEnabled' not in txt:
        txt = re.sub(
            r'android\s*\{',
            (
                'android {\n'
                '    compileOptions {\n'
                '        sourceCompatibility JavaVersion.VERSION_17\n'
                '        targetCompatibility JavaVersion.VERSION_17\n'
                '        coreLibraryDesugaringEnabled true\n'
                '    }\n'
                '    kotlinOptions {\n'
                '        jvmTarget = "17"\n'
                '    }\n'
            ),
            txt, count=1
        )
    if 'coreLibraryDesugaring ' not in txt:
        txt = re.sub(
            r'dependencies\s*\{',
            (
                'dependencies {\n'
                '    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"\n'
            ),
            txt, count=1
        )
    return txt

def main() -> int:
    kts = Path("proj/android/app/build.gradle.kts")
    groovy = Path("proj/android/app/build.gradle")

    target = None
    is_kts = False
    if kts.exists():
        target = kts
        is_kts = True
    elif groovy.exists():
        target = groovy
        is_kts = False
    else:
        print("❌ Gradle file not found under proj/android/app/", file=sys.stderr)
        return 1

    txt = target.read_text(encoding="utf-8")
    new_txt = patch_kts(txt) if is_kts else patch_groovy(txt)

    if new_txt != txt:
        target.write_text(new_txt, encoding="utf-8")
        print(f"✅ Patched {target}")
    else:
        print(f"ℹ️ Patch not needed for {target}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
