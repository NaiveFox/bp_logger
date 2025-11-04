#!/usr/bin/env python3
import re
from pathlib import Path

def patch_text_kts(txt: str) -> str:
    # Добавить compileOptions + kotlinOptions + флаг десугаринга, если нет
    if 'isCoreLibraryDesugaringEnabled' not in txt:
        txt = re.sub(
            r'android\s*\{',
            'android {\n'
            '    compileOptions {\n'
            '        sourceCompatibility = JavaVersion.VERSION_17\n'
            '        targetCompatibility = JavaVersion.VERSION_17\n'
            '        isCoreLibraryDesugaringEnabled = true\n'
            '    }\n'
            '    kotlinOptions {\n'
            '        jvmTarget = "17"\n'
            '    }\n',
            txt, count=1
        )
    # Добавить зависимость десугаринга, если нет
    if 'coreLibraryDesugaring' not in txt:
        txt = re.sub(
            r'dependencies\s*\{',
            'dependencies {\n'
            '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")',
            txt, count=1
        )
    return txt

def patch_text_groovy(txt: str) -> str:
    if 'isCoreLibraryDesugaringEnabled' not in txt:
        txt = re.sub(
            r'android\s*\{',
            'android {\n'
            '    compileOptions {\n'
            '        sourceCompatibility JavaVersion.VERSION_17\n'
            '        targetCompatibility JavaVersion.VERSION_17\n'
            '        coreLibraryDesugaringEnabled true\n'
            '    }\n'
            '    kotlinOptions {\n'
            '        jvmTarget = "17"\n'
            '    }\n',
            txt, count=1
        )
    if 'coreLibraryDesugaring' not in txt:
        txt = re.sub(
            r'dependencies\s*\{',
            'dependencies {\n'
            '    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"',
            txt, count=1
        )
    return txt

def patch_file(path: Path):
    if not path.exists():
        return False
    txt = path.read_text(encoding='utf-8', errors='ignore')
    original = txt
    if path.suffix == '.kts':
        txt = patch_text_kts(txt)
    else:
        txt = patch_text_groovy(txt)
    if txt != original:
        path.write_text(txt, encoding='utf-8')
        return True
    return False

def main():
    # Ищем gradle у Flutter-проекта, который собираем в папке proj/
    for p in [
        Path('proj/android/app/build.gradle.kts'),
        Path('proj/android/app/build.gradle'),
    ]:
        patched = patch_file(p)
        print(f"[patch_gradle] {p}: {'patched' if patched else 'ok'}")

if __name__ == "__main__":
    main()
