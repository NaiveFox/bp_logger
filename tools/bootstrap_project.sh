#!/usr/bin/env bash
set -euxo pipefail

echo ">> Flutter: $(flutter --version | head -n1)"

# 0) На раннере мог остаться мусор от прошлых запусков
rm -rf android || true

# 1) Создаём ЧИСТЫЙ android-хост (в2 embedding по умолчанию)
flutter create --platforms=android --org com.naivefox --project-name bp_logger .

# 2) Перекладываем твой код: app/lib -> lib (точка входа останется lib/main.dart)
if [ -d app/lib ]; then
  rm -rf lib
  mkdir -p lib
  cp -R app/lib/* lib/
fi

# Если pubspec.yaml лежит в app/, используем его (иначе останется корневой)
if [ -f app/pubspec.yaml ]; then
  cp app/pubspec.yaml ./pubspec.yaml
fi

# 3) Приводим ID пакета к единому виду
APP_KTS="android/app/build.gradle.kts"
APP_GRADLE="android/app/build.gradle"

if [ -f "$APP_KTS" ]; then
  sed -i 's/^namespace = .*/namespace = "com.naivefox.bp_logger"/' "$APP_KTS" || true
  sed -i 's/applicationId = ".*"/applicationId = "com.naivefox.bp_logger"/' "$APP_KTS" || true
fi

if [ -f "$APP_GRADLE" ]; then
  sed -i 's/^namespace .*=.*/namespace "com.naivefox.bp_logger"/' "$APP_GRADLE" || true
  sed -i 's/applicationId ".*"/applicationId "com.naivefox.bp_logger"/' "$APP_GRADLE" || true
fi

# 4) gradle.properties — базовые флаги
cat > android/gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.enableJetifier=true
EOF

# 5) Чиним манифест под v2-эмбеддинг + фикс пути к Activity
MANIFEST="android/app/src/main/AndroidManifest.xml"
sed -i '/android:name="\${applicationName}"/d' "$MANIFEST" || true
sed -i 's/android:name="\.MainActivity"/android:name="com.naivefox.bp_logger.MainActivity"/' "$MANIFEST" || true

# Вставим маркер v2-эмбеддинга сразу после <application ...>
awk '
  BEGIN{ins=0}
  /<application[^>]*>/ && ins==0 {
    print
    print "    <meta-data android:name=\"flutterEmbedding\" android:value=\"2\" />"
    ins=1
    next
  }
  {print}
' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

echo ">> Bootstrap done ✅"
