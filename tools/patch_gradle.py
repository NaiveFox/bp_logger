#!/usr/bin/env python3
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_GRADLE = ROOT / "android" / "app" / "build.gradle"
WRAPPER = ROOT / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"

def read(p: pathlib.Path) -> str:
    return p.read_text(encoding="utf-8") if p.exists() else ""

def write(p: pathlib.Path, s: str):
    p.write_text(s, encoding="utf-8")
    print(f"patched: {p.relative_to(ROOT)}")

def ensure_gradle_wrapper():
    if WRAPPER.exists():
        s = read(WRAPPER)
        s = re.sub(
            r"distributionUrl=.*",
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip",
            s
        )
        write(WRAPPER, s)

def patch_app_gradle():
    if not APP_GRADLE.exists():
        print("⚠ android/app/build.gradle not found")
        return
    s = read(APP_GRADLE)

    # 1. Убедимся, что есть compileOptions с Java 17 и десугарингом
    if "coreLibraryDesugaringEnabled" not in s:
        s = re.sub(
            r"(compileOptions\s*\{[^\}]*targetCompatibility[^\}]*\})",
            lambda m: m.group(1) + "\n    coreLibraryDesugaringEnabled true",
            s,
            count=1
        )
    if "compileOptions" not in s:
        s = re.sub(
            r"android\s*\{",
            (
                "android {\n"
                "    compileOptions {\n"
                "        sourceCompatibility JavaVersion.VERSION_17\n"
                "        targetCompatibility JavaVersion.VERSION_17\n"
                "        coreLibraryDesugaringEnabled true\n"
                "    }\n"
            ),
            s, count=1
        )

    # 2. kotlinOptions jvmTarget = '17'
    if "kotlinOptions" not in s:
        s = re.sub(
            r"android\s*\{",
            "android {\n    kotlinOptions {\n        jvmTarget = '17'\n    }\n",
            s, count=1
        )
    else:
        s = re.sub(
            r"kotlinOptions\s*\{[^\}]*\}",
            "kotlinOptions {\n    jvmTarget = '17'\n}",
            s, flags=re.DOTALL
        )

    # 3. Добавим зависимость coreLibraryDesugaring
    if "coreLibraryDesugaring" not in s:
        s = re.sub(
            r"dependencies\s*\{",
            (
                "dependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.2'\n"
            ),
            s, count=1
        )

    # 4. Вставим import для JavaVersion в начало файла, если его нет
    if "JavaVersion" not in s.splitlines()[0]:
        s = "import org.gradle.api.JavaVersion\n" + s

    write(APP_GRADLE, s)
    print("✅ build.gradle patched with coreLibraryDesugaringEnabled true")

def main():
    ensure_gradle_wrapper()
    patch_app_gradle()

if __name__ == "__main__":
    sys.exit(main())
