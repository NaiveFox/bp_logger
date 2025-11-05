#!/usr/bin/env bash
set -euo pipefail

echo ">> checking Flutter version"
flutter --version

# 1. Если есть app/, скопировать в корень
if [ -d "app" ]; then
  echo ">> copying app/ into repo root"
  cp -r app/lib . 2>/dev/null || true
  cp -r app/pubspec.yaml . 2>/dev/null || true
fi

# 2. Создать android-проект, если отсутствует
if [ ! -d "android" ]; then
  echo ">> android/ not found: creating Flutter android skeleton"
  PROJ_NAME=$(awk '/^name:/{print $2; exit}' pubspec.yaml 2>/dev/null || echo "bp_logger")
  flutter create --org com.naivefox.bp --project-name "${PROJ_NAME}" --platforms android .
else
  echo ">> android/ already exists, skipping creation"
fi

# 3. Обновить gradle.properties
GP="android/gradle.properties"
mkdir -p android
touch "$GP"
grep -q "android.useAndroidX=true" "$GP" || echo "android.useAndroidX=true" >> "$GP"
grep -q "android.enableR8=true" "$GP" || echo "android.enableR8=true" >> "$GP"
grep -q "android.nonTransitiveRClass=true" "$GP" || echo "android.nonTransitiveRClass=true" >> "$GP"
grep -q "org.gradle.jvmargs" "$GP" || echo "org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8" >> "$GP"
grep -q "kotlin.code.style=official" "$GP" || echo "kotlin.code.style=official" >> "$GP"
grep -q "kotlin.incremental=true" "$GP" || echo "kotlin.incremental=true" >> "$GP"

# 4. Загрузить зависимости
echo ">> running flutter pub get"
flutter pub get

echo ">> bootstrap done ✅"
