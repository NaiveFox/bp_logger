#!/usr/bin/env python3
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_DIR = ROOT / "android" / "app"
WRAPPER = ROOT / "android" / "gradle" / "wrapper" / "gradle-wrapper.properties"

DESUGAR_VER = "2.1.2"

def read(p): return p.read_text(encoding="utf-8") if p.exists() else ""
def write(p,s): p.write_text(s,encoding="utf-8"); print(f"patched: {p.relative_to(ROOT)}")

def ensure_gradle_wrapper():
    if WRAPPER.exists():
        s = read(WRAPPER)
        s = re.sub(r"distributionUrl=.*",
                   "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip",
                   s)
        write(WRAPPER, s)

def ensure_dependency_kts(s: str) -> str:
    # вставить coreLibraryDesugaring(...) в существующий блок dependencies { ... } или создать новый
    if re.search(r'coreLibraryDesugaring\s*\(', s):
        return s
    if re.search(r'^\s*dependencies\s*\{', s, flags=re.M):
        return re.sub(
            r'(^\s*dependencies\s*\{\s*)',
            r'\1    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:%s")\n' % DESUGAR_VER,
            s, count=1, flags=re.M
        )
    return s + (
        "\ndependencies {\n"
        f"    coreLibraryDesugaring(\"com.android.tools:desugar_jdk_libs:{DESUGAR_VER}\")\n"
        "}\n"
    )

def ensure_dependency_groovy(s: str) -> str:
    if re.search(r"coreLibraryDesugaring\s+['\"]", s):
        return s
    if re.search(r'^\s*dependencies\s*\{', s, flags=re.M):
        return re.sub(
            r'(^\s*dependencies\s*\{\s*)',
            r"\1    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:%s'\n" % DESUGAR_VER,
            s, count=1, flags=re.M
        )
    return s + (
        "\ndependencies {\n"
        f"    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:{DESUGAR_VER}'\n"
        "}\n"
    )

def ensure_android_block_kts(s: str) -> str:
    # compileOptions + kotlinOptions + включение desugaring (Kotlin DSL)
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
            s, count=1
        )
    if "kotlinOptions" not in s:
        s = re.sub(
            r"android\s*\{",
            "android {\n    kotlinOptions {\n        jvmTarget = \"17\"\n    }\n",
            s, count=1
        )
    return s

def ensure_android_block_groovy(s: str) -> str:
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
    if "kotlinOptions" not in s:
        s = re.sub(
            r"android\s*\{",
            "android {\n    kotlinOptions {\n        jvmTarget = '17'\n    }\n",
            s, count=1
        )
    return s

def patch_app_gradle():
    gradle = APP_DIR / "build.gradle"
    is_kts = False
    if not gradle.exists():
        gradle = APP_DIR / "build.gradle.kts"
        is_kts = True
    if not gradle.exists():
        print("⚠ no app gradle file")
        return

    s = read(gradle)
    print(f"patching {gradle.name}")

    if is_kts:
        s = ensure_android_block_kts(s)
        s = ensure_dependency_kts(s)
    else:
        s = ensure_android_block_groovy(s)
        s = ensure_dependency_groovy(s)

    # Импорт JavaVersion если нужен
    first_line = s.splitlines()[0] if s else ""
    if "JavaVersion" not in first_line:
        s = "import org.gradle.api.JavaVersion\n" + s

    write(gradle, s)
    print("✅ desugaring enabled + dependency added precisely")

def main():
    ensure_gradle_wrapper()
    patch_app_gradle()

if __name__ == "__main__":
    sys.exit(main())
