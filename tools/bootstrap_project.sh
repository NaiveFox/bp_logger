#!/usr/bin/env bash
set -euo pipefail

# 1) Если нет android/, создаём проект (оставляем только Android-платформу)
if [ ! -d "android" ]; then
  echo ">> android/ not found: creating Flutter android skeleton"
  # Имя проекта берём из pubspec.yaml, иначе — bp_logger
  PROJ_NAME=$(awk '/^name:/{print $2; exit}' pubspec.yaml 2>/dev/null || echo "bp_logger")
  flutter create \
    --org com.naivefox.bp \
    --project-name "${PROJ_NAME}" \
    --platforms android \
    .
fi

# 2) Если твои исходники лежат в app/, подложим их в корень
if [ -d "app" ]; then
  echo ">> syncing app/ into repo root"
  rsync -a --delete app/ .
fi

# 3) Базовые gradle.properties (безопасные флаги, AndroidX, R8, etc.)
GP="android/gradle.properties"
mkdir -p android
touch "$GP"
grep -q "android.useAndroidX=true" "$GP" || echo "android.useAndroidX=true" >> "$GP"
grep -q "android.enableR8=true" "$GP" || echo "android.enableR8=true" >> "$GP"
grep -q "android.nonTransitiveRClass=true" "$GP" || echo "android.nonTransitiveRClass=true" >> "$GP"
grep -q "org.gradle.jvmargs" "$GP" || echo "org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8" >> "$GP"
grep -q "kotlin.code.style=official" "$GP" || echo "kotlin.code.style=official" >> "$GP"
grep -q "kotlin.incremental=true" "$GP" || echo "kotlin.incremental=true" >> "$GP"

# 4) Pub get
flutter pub get
echo ">> bootstrap done"
