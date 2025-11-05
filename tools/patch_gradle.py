#!/usr/bin/env python3
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_GRADLE = ROOT / "android" / "app" / "build.gradle"
TOP_GRADLE = ROOT / "android" / "build.gradle"
WRAPPER = ROOT / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"

def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8")

def write(p: pathlib.Path, s: str):
    p.write_text(s, encoding="utf-8")
    print(f"patched: {p.relative_to(ROOT)}")

def ensure_gradle_wrapper():
    # AGP 8.5.x → Gradle 8.7 — оптимально для Java 17
    if WRAPPER.exists():
        s = read(WRAPPER)
        s = re.sub(r"distributionUrl=.*",
                   "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip",
                   s)
        write(WRAPPER, s)

def ensure_top_level_agp():
    if not TOP_GRADLE.exists():
        return
    s = read(TOP_GRADLE)
    # Оба стиля: старый classpath и plugins {} — покроем оба

    # 1) classpath
    if "com.android.tools.build:gradle" in s:
        s = re.sub(r"(com\.android\.tools\.build:gradle:)\d+(\.\d+)*",
                   r"\g<1>8.5.2", s)

    # 2) plugins DSL (назв. не указывается с версией здесь — версия берётся из settings/pluginManagement,
    # но во Flutter-шаблоне обычно top-level build.gradle с classpath; оставим как есть)
    write(TOP_GRADLE, s)

def ensure_app_gradle_desugaring():
    if not APP_GRADLE.exists():
        print("WARN: android/app/build.gradle not found")
        return
    s = read(APP_GRADLE)

    # --- Java & Kotlin options ---
    s = re.sub(
        r"android\s*\{",
        (
            "android {\n"
            "    compileOptions {\n"
            "        sourceCompatibility JavaVersion.VERSION_17\n"
            "        targetCompatibility JavaVersion.VERSION_17\n"
            "        coreLibraryDesugaringEnabled true\n"
            "    }\n"
            "    kotlinOptions {\n"
            "        jvmTarget = '17'\n"
            "    }\n"
        ),
        s,
        count=1
    )

    # --- Добавим зависимость ---
    if "coreLibraryDesugaring" not in s:
        s = re.sub(
            r"dependencies\s*\{",
            (
                "dependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.2'\n"
            ),
            s,
            count=1
        )

    # --- Гарантируем наличие plugin'а com.android.application ---
    if "com.android.application" not in s:
        s = "plugins {\n    id 'com.android.application'\n    id 'org.jetbrains.kotlin.android'\n}\n\n" + s

    write(APP_GRADLE, s)

def main():
    ensure_gradle_wrapper()
    ensure_top_level_agp()
    ensure_app_gradle_desugaring()
    print(">> Gradle patched for Java17/AGP8/desugaring")

if __name__ == "__main__":
    sys.exit(main())
