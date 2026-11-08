#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=========================================================="
echo "🌿 Instalador de LIVIA para macOS"
echo "=========================================================="

# 1. Empaquetar si no existe
if [ ! -d "build/Livia.app" ]; then
    echo "==> Empaquetando Livia..."
    ./scripts/package_app.sh
fi

# 2. Instalar Livia.app en /Applications
echo "==> Instalando Livia.app en /Applications..."
rm -rf "/Applications/Livia.app"
cp -R "build/Livia.app" "/Applications/Livia.app"
echo "✓ Livia.app instalada en /Applications/Livia.app"

# 3. Instalar CLI 'livia' en /usr/local/bin
echo "==> Instalando CLI 'livia' en /usr/local/bin..."
if [ -w "/usr/local/bin" ]; then
    cp ".build/out/Products/Release/livia" "/usr/local/bin/livia"
    chmod +x "/usr/local/bin/livia"
    echo "✓ CLI 'livia' instalado en /usr/local/bin/livia"
else
    echo "Se requieren permisos para copiar a /usr/local/bin:"
    sudo cp ".build/out/Products/Release/livia" "/usr/local/bin/livia"
    sudo chmod +x "/usr/local/bin/livia"
    echo "✓ CLI 'livia' instalado con permisos de administrador en /usr/local/bin/livia"
fi

echo ""
echo "=========================================================="
echo "🎉 ¡Livia ha sido instalada con éxito!"
echo "=========================================================="
echo ""
echo "Formas de usar Livia:"
echo " 1. Aplicación de Barra de Menús: Abre '/Applications/Livia.app'"
echo "    (Aparecerá en tu barra de menús superior con un icono de hoja y % de RAM)"
echo ""
echo " 2. Desde Terminal:"
echo "    - 'livia' o 'livia status': Ver diagnóstico de memoria"
echo "    - 'livia clean': Liberar memoria caché inmediatamente"
echo "    - 'livia top': Ver qué procesos están consumiendo tu RAM"
echo ""
echo " 3. Habilitar Deep Purge permanente sin contraseña (Recomendado para 8GB):"
echo "    Ejecuta: 'sudo livia daemon --install'"
echo "    Esto activa el servicio root en segundo plano que mantendrá tu Mac"
echo "    fresco 24/7 con menos de 1 MB de consumo."
echo "=========================================================="
