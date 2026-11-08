#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "==> Compilando binarios de Livia en modo Release..."
swift build -c release

RELEASE_DIR="$DIR/.build/out/Products/Release"
APP_DIR="$DIR/build/Livia.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Creando estructura del App Bundle en $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copiar ejecutable
cp "$RELEASE_DIR/LiviaApp" "$MACOS_DIR/Livia"
chmod +x "$MACOS_DIR/Livia"

# Crear Info.plist
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Livia</string>
    <key>CFBundleDisplayName</key>
    <string>Livia</string>
    <key>CFBundleIdentifier</key>
    <string>com.nachovinilo.livia</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Livia</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Livia. Todos los derechos reservados.</string>
</dict>
</plist>
EOF

# Validar Info.plist
plutil -lint "$CONTENTS_DIR/Info.plist"

# Firmar bundle con firma ad-hoc para macOS
codesign --force --deep --sign - "$APP_DIR"

echo "==> ¡Livia.app empaquetada exitosamente en $APP_DIR!"
