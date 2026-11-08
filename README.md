# 🌿 Livia

**Livia** es una herramienta nativa para macOS desarrollada en **Swift 6** diseñada específicamente para mantener los equipos Mac (especialmente modelos con **8 GB de RAM**) ágiles, libres de lag y respirando con holgura durante largas jornadas de trabajo.

---

## 💡 El Problema en los Mac de 8 GB

En macOS, la filosofía del kernel Mach es que *"la RAM no usada es RAM desperdiciada"*. Por ello, el sistema acumula memoria inactiva y cachés de lectura de disco (File-backed cache). 

En equipos con 8 GB de RAM:
1. Las cachés inactivas y aplicaciones en segundo plano llenan rápidamente los 8 GB.
2. Cuando abres una app pesada o varias pestañas de navegador, macOS se ve forzado a comprimir memoria y escribir en el **Swap del SSD**.
3. Esto genera los temidos **micro-tirones (stutters)**, degradación del rendimiento y mayor desgaste en el disco SSD.
4. El comando tradicional `sudo purge` requiere abrir la terminal, escribir tu contraseña de administrador a cada rato y corta tu flujo de trabajo.

---

## ✨ La Solución: ¿Cómo Funciona Livia?

Livia resuelve esto en segundo plano con **consumo prácticamente nulo de recursos**:

1. **Huella Ultraligera (< 15 MB de RAM / 0% CPU en reposo):**
   - Construida 100% en Swift nativo con AppKit y SwiftUI.
   - Sin Electron, sin Python, sin dependencias pesadas.
   - Corre como elemento de barra de menú (`LSUIElement = true`), sin ocupar espacio en el Dock.

2. **Cerebro Inteligente (Livia Smart Engine):**
   - **Regla Anti-Lag (Idle Detection):** Utiliza APIs de `CoreGraphics` para detectar cuándo estás inactivo (lejos del teclado o mouse). Ejecuta la limpieza silenciosa durante esos momentos para que **nunca notes una caída de fotogramas** mientras escribes, diseñas o juegas.
   - **Regla Anti-Desgaste SSD (Cooldown):** Mantiene un período de descanso inteligente (por defecto 3 minutos) entre limpiezas para evitar el ciclado excesivo del disco.
   - **Kernel Memory Pressure Watcher:** Conectada directamente a `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` del kernel Darwin para reaccionar inmediatamente antes de que el Mac sufra congelamientos.
   - **Puntaje de Salud de RAM (0 - 100):** Evalúa presión, swap y memoria disponible en tiempo real.

3. **Doble Motor de Optimización:**
   - **Modo Estándar (Espacio de Usuario):** Limpieza de cachés de miniaturas (`qlmanage`), servicios de directorio/DNS (`dscacheutil`) y evicción progresiva de memoria virtual sin requerir contraseña de administrador.
   - **Modo Profundo (Kernel Deep Purge):** Incluye un daemon de sistema opcional (`com.livia.daemon`) que se instala con un comando en `LaunchDaemons`. Corre como root en segundo plano (< 1 MB de RAM) y permite ejecutar el `purge` del kernel instantáneamente sin pedir contraseña nunca más.

---

## 🚀 Instalación Rápida

Puedes compilar e instalar Livia en un solo paso con el script incluido:

```bash
git clone https://github.com/nachovinilo/livia.git
cd livia
./install.sh
```

Esto:
- Compilará los binarios optimizados en Release.
- Instalará `Livia.app` en `/Applications`.
- Instalará el comando `livia` en `/usr/local/bin/livia`.

---

## 🖥️ Uso de Livia

### 1. Aplicación de Barra de Menú (`Livia.app`)

Abre **Livia** desde Spotlight o tu carpeta de Aplicaciones:
- Verás un discreto icono de hoja con el porcentaje de RAM actual en tu barra de menú superior.
- Al hacer clic, se despliega una interfaz translúcida nativa con:
  - **Barra de memoria segmentada:** Activa, Wired, Comprimida, Caché Inactiva y Libre.
  - **Botón "Liberar Memoria Ahora":** Optimización inmediata en 1 clic.
  - **Interruptor de Auto-Limpieza Inteligente:** Activa la supervisión en reposo.
  - **Top Apps con Mayor Consumo:** Detecta al instante si Chrome, Slack o algún helper están devorando tu memoria.
  - **Estado del Daemon de Kernel:** Indica si Deep Purge está listo.

### 2. Desde la Terminal (`livia` CLI)

Livia también incluye una potente herramienta de línea de comandos:

```bash
# Ver diagnóstico completo, salud y top procesos
livia

# Liberar memoria de inmediato
livia clean

# Ver los 15 procesos que más RAM consumen
livia top

# Modo monitor interactivo en tiempo real
livia watch

# Comprobar estado del daemon
livia daemon status
```

---

## ⚡ Habilitar Kernel Deep Purge Permanente (Recomendado)

Para que Livia pueda ejecutar el vaciado profundo de buffers de disco (`purge`) automáticamente y sin pedirte contraseña cada vez:

```bash
sudo livia daemon --install
```

Esto registra un servicio ultraligero en `/Library/LaunchDaemons/com.livia.daemon.plist` que se comunica con Livia mediante un socket UNIX local (`/var/run/livia.sock`).

Para desinstalar el daemon en cualquier momento:
```bash
sudo livia daemon --uninstall
```

---

## 🏗️ Estructura del Proyecto

```
livia/
├── Package.swift               # Definición de paquetes Swift 6
├── Sources/
│   ├── LiviaCore/             # Núcleo compartido
│   │   ├── MemoryStats.swift         # Estructuras de datos y formateo
│   │   ├── SystemMemoryMonitor.swift # APIs Mach VM, sysctl, libproc
│   │   ├── MemoryCleaner.swift       # Motores de limpieza y evicción
│   │   ├── DaemonIPC.swift           # Comunicación cliente/servidor por Socket
│   │   └── SmartEngine.swift         # Heurísticas de IA y reglas para 8GB
│   ├── LiviaCLI/              # Binario de línea de comandos
│   │   └── main.swift
│   └── LiviaApp/              # Aplicación de Barra de Menú (macOS)
│       ├── AppDelegate.swift         # Gestión de NSStatusItem y ciclo de vida
│       ├── LiviaViewModel.swift      # Estado reactivo y comandos
│       └── ContentView.swift         # Interfaz SwiftUI con efecto translúcido
├── scripts/
│   └── package_app.sh         # Script de empaquetado del bundle .app
├── install.sh                 # Instalador automatizado
└── README.md
```

---

## 📄 Licencia

MIT License © 2026 Livia. Desarrollado con Swift nativo para la comunidad de macOS.
