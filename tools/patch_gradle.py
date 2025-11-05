#!/usr/bin/env python3
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_GRADLE = ROOT / "android" / "app"
WRAPPER = ROOT / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"

def read(p): return p.read_text(encoding="utf-8") if p.exists() else ""
def write(p, s): p.write_text(s, encoding="utf-8"); print(f"patched: {p.relative_to(ROOT)}")

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
    # Определим файл — build.gradle или build.gradle.kts
    gradle_file = APP_GRADLE / "build.gradle"
    if not gradle_file.exists():
        gradle_file = APP_GRADLE / "build.gradle.kts"
    if not gradle_file.exists():
        print("⚠ no app build.gradle(.kts) found")
        return

    s = read(gradle_file)
    print(f"patching {gradle_file.name}")

    # Kotlin DSL вариант (.kts)
    if gradle_file.suffix == ".kts":
        if "isCoreLibraryDesugaringEnabled" not in s:
            s = re.sub(
                r"android\s*\{",
                (
                    "android {\n"
                    "    compileOptions {\n"
                    "        sourceCompatibility = JavaVersion.VERSION_17\n"
                    "        targetCompatibility = JavaVersion.VERSION_17\n"
                    "        isCoreLibraryDesugaringEnabled = true\n"
                    "    }\n"
                ),
                s,
                count=1
            )
        if "coreLibraryDesugaring" not in s:
            s = re.sub(
                r"dependencies\s*\{",
                (
                    "dependencies {\n"
                    "    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:2.1.2\")\n"
                ),
                s,
                count=1
            )
        if "kotlinOptions" not in s:
            s = re.sub(
                r"android\s*\{",
                "android {\n    kotlinOptions {\n        jvmTarget = \"17\"\n    }\n",
                s,
                count=1
            )
    else:
        # Groovy-вариант
        if "coreLibraryDesugaringEnabled" not in s:
            s = re.sub(
                r"compileOptions\s*\{[^}]*\}",
                (
                    "compileOptions {\n"
                    "    sourceCompatibility JavaVersion.VERSION_17\n"
                    "    targetCompatibility JavaVersion.VERSION_17\n"
                    "    coreLibraryDesugaringEnabled true\n"
                    "}"
                ),
                s, flags=re.DOTALL
            )
        if "coreLibraryDesugaring" not in s:
            s = re.sub(
                r"dependencies\s*\{",
                (
                    "dependencies {\n"
                    "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.2'\n"
                ),
                s, count=1
            )

    # Убедимся, что импорт есть
    if "JavaVersion" not in s:
        s = "import org.gradle.api.JavaVersion\n" + s

    write(gradle_file, s)
    print("✅ Patched for Java17 + Desugaring")

def main():
    ensure_gradle_wrapper()
    patch_app_gradle()

if __name__ == "__main__":
    sys.exit(main())
