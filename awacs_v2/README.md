# AWACS Agent for DCS

## Setup previo obligatorio (Python backend)

Antes de ejecutar validaciones o desarrollar el backend AWACS, completa estos pasos:

1. Instala Python 3.11+ y activa la opcion **Add Python to PATH**.
2. Abre PowerShell en `C:\repos\DCS_Missions\awacs_v2`.
3. Crea el entorno virtual e instala dependencias:

```powershell
.\setup_env.ps1
```

4. Activa el entorno virtual (si necesitas ejecutar comandos manuales):

```powershell
.\.venv\Scripts\Activate.ps1
```

5. Ejecuta la validacion del contrato parser -> schema:

```powershell
.\.venv\Scripts\python.exe -m backend.validate_contract
```

Archivos de referencia del setup:
- `requirements.txt`
- `requirements-dev.txt`
- `.gitignore`
- `setup_env.ps1`

Comprobacion automatica recomendada:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest -q
```

### Troubleshooting rapido

- Si `python` no se reconoce, reinstala Python 3.11+ y marca **Add Python to PATH**.
- Si falla la activacion del venv por politica de ejecucion:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\.venv\Scripts\Activate.ps1
```

- Si faltan paquetes, reinstala dependencias:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

- Si quieres validar sin activar el entorno, ejecuta siempre con ruta completa:

```powershell
.\.venv\Scripts\python.exe -m backend.validate_contract
```

## Version de Lua y lint (DCS)

- Este modulo debe mantenerse compatible con el runtime Lua embebido de DCS (ecosistema Lua 5.1/LuaJIT).
- No se debe migrar la sintaxis a Lua 5.4+ para scripts de mision DCS.

Configuracion local incluida en este directorio:
- `.luarc.json` (Lua Language Server).
- `.luacheckrc` (luacheck).
- `run_luacheck.ps1` (runner estable para Windows).

### Instalacion de luacheck en Windows (paso a paso)

1. Instalar Lua (incluye `lua` y `luarocks`):

```powershell
winget install --id DEVCOM.Lua -e --accept-package-agreements --accept-source-agreements
```

2. Instalar compilador MinGW requerido por dependencias nativas (ej: `luafilesystem`):

```powershell
winget install --id MartinStorsjo.LLVM-MinGW.UCRT -e --accept-package-agreements --accept-source-agreements
```

3. Cerrar y abrir PowerShell.

4. Verificar herramientas base:

```powershell
lua -v
luarocks --version
x86_64-w64-mingw32-gcc --version
```

5. Instalar `luacheck`:

```powershell
luarocks install luacheck
```

6. Verificar lint sobre AWACS:

```powershell
cd C:\repos\DCS_Missions\awacs_v2
.\run_luacheck.ps1
```

### Uso recomendado en este repo

Desde `C:\repos\DCS_Missions\awacs_v2`:

```powershell
.\run_luacheck.ps1
```

Opcional (target especifico):

```powershell
.\run_luacheck.ps1 -Target scripts/awacs/adapters
```

Tarea VS Code disponible:
- `Lua: luacheck AWACS scripts` (archivo `.vscode/tasks.json`).

### Troubleshooting de instalacion

Si algun comando no se reconoce:

```powershell
where.exe lua
where.exe luarocks
where.exe x86_64-w64-mingw32-gcc
```

Si `luarocks install luacheck` falla por compilacion, confirma que el compilador este instalado y abre una nueva shell:

```powershell
x86_64-w64-mingw32-gcc --version
```

Si `run_luacheck.ps1` indica que falta `luacheck`, reinstala:

```powershell
luarocks install luacheck
```

## Integracion recomendada en mision (MOOSE preferente)

- Opcion elegida: `MOOSE`.
- Motivo: facilita tracking de grupos y eventos sin acoplar el nucleo tactico a una libreria.
- Nucleo tactico agnostico: `scripts/awacs/awacs_agent.lua` + modulos de `perception/tracking/threat_eval/comms/message_builder`.
- Adaptador MOOSE: `scripts/awacs/adapters/moose_adapter.lua`.
- Bootstrap de mision: `scripts/awacs/bootstrap_moose.lua`.

Ejemplo minimo:

```lua
local MooseBootstrap = require("awacs.bootstrap_moose")
MooseBootstrap.start({
    adapter = {
        package_group_names = { "COLT11" },
        hostile_group_prefixes = { "RED_CAP_" },
    }
})
```


Perfiles disponibles:
- `tactical_realistic` (default).
- `academy_basic` (mayor cadencia y ayudas para entrenamiento).
- Definidos en `scripts/awacs/profile_presets.lua`.

Ejemplo academy_basic:

```lua
local MooseBootstrap = require("awacs.bootstrap_moose")
MooseBootstrap.start({
    profile = "academy_basic",
    adapter = {
        package_group_prefixes = { "BLUE_ACA_" },
        hostile_group_prefixes = { "RED_ACA_" },
    }
})
```
---
## PropÃ³sito

Este mÃ³dulo implementa la base de un agente **AWACS / GCI** para DCS World orientado a misiones de escuadrÃ³n, academia y entrenamiento tÃ¡ctico.

Su objetivo es proporcionar una lÃ³gica reutilizable para:
- seguimiento de paquetes blue,
- detecciÃ³n de grupos hostiles relevantes,
- priorizaciÃ³n de amenazas,
- generaciÃ³n de comunicaciones tÃ¡cticas,
- soporte a modos de realismo distintos,
- integraciÃ³n limpia con scripts de misiÃ³n existentes.

Este sistema estÃ¡ pensado para evolucionar de forma incremental:
1. primero como **MVP funcional**,
2. despuÃ©s con mÃ¡s robustez tÃ¡ctica,
3. y mÃ¡s adelante con capacidades avanzadas como picture calls, check-ins, hooks de scoring o integraciÃ³n con otros agentes.

---

## Objetivos del diseÃ±o

Este mÃ³dulo no busca ser un script monolÃ­tico que emita mensajes automÃ¡ticos sin control.

Busca una arquitectura:
- **modular**,
- **mantenible**,
- **configurable**,
- **trazable**,
- **reutilizable entre misiones**.

El agente debe comportarse como un **controlador tÃ¡ctico Ãºtil y sobrio**, no como un narrador omnisciente.

---

## Casos de uso previstos

Este mÃ³dulo puede utilizarse para:

- misiones de academia con ayuda tÃ¡ctica simplificada,
- entrenamiento BVR,
- control tÃ¡ctico semiautomatizado,
- apoyo a paquetes strike o CAP,
- escenarios con control de amenaza por sectores,
- pruebas doctrinales de fraseo y priorizaciÃ³n,
- base para otros agentes de misiÃ³n.

---

## FilosofÃ­a de funcionamiento

El agente AWACS debe:

- hablar **solo cuando aporte valor**,
- priorizar **amenazas accionables**,
- evitar **spam de frecuencia**,
- usar **cooldowns** y supresiÃ³n de duplicados,
- adaptar el nivel de detalle al perfil configurado.

No debe:
- repetir la misma informaciÃ³n sin cambios,
- emitir mensajes continuos por cada contacto detectado,
- mezclar percepciÃ³n, razonamiento y salida en una sola funciÃ³n gigante,
- depender completamente de nombres hardcodeados de una sola misiÃ³n.

---

## Arquitectura esperada

La lÃ³gica del agente deberÃ­a separarse en responsabilidades claras.
La implementación de este módulo puede apoyarse en MOOSE como framework principal y en MIST como librería auxiliar cuando aporte simplicidad real. La lógica táctica del agente debe permanecer lo bastante desacoplada como para no quedar totalmente atada a una sola librería.

### 1. Perception
Se encarga de leer el estado relevante del entorno DCS.

Ejemplos:
- grupos blue monitorizados,
- grupos hostiles detectados,
- sectores o zonas activas,
- referencias geogrÃ¡ficas o bullseye,
- estado bÃ¡sico de unidades y paquetes.

### 2. Tracking
Mantiene un estado mÃ­nimo Ãºtil para decidir.

Ejemplos:
- contactos ya vistos,
- timestamps de detecciÃ³n,
- historial reciente,
- pÃ©rdida de track,
- cambios de estado relevantes.

### 3. Threat Evaluation
Calcula quÃ© amenazas importan mÃ¡s.

Ejemplos:
- distancia a paquete protegido,
- aspecto o direcciÃ³n de cierre,
- altitud relativa,
- tipo de contacto,
- urgencia tÃ¡ctica,
- novedad del contacto.

### 4. Comms Decision
Decide si el agente debe hablar o no.

Ejemplos:
- prioridad del mensaje,
- cooldown por paquete,
- supresiÃ³n de duplicados,
- filtro de mensajes poco Ãºtiles,
- elecciÃ³n del tipo de call.

### 5. Message Generation
Construye el mensaje tÃ¡ctico.

Ejemplos:
- BRAA,
- picture,
- threat advisory,
- merge warning,
- updates contextuales.

### 6. Output
Entrega la salida por el canal adecuado.

Ejemplos:
- texto en misiÃ³n,
- radio,
- logs,
- hooks para debriefing o scoring.

### 7. Config
Centraliza parÃ¡metros y reglas ajustables.

Ejemplos:
- paquetes monitorizados,
- sectores activos,
- timings,
- perfil de fraseo,
- umbrales de amenaza,
- canales de salida,
- nivel de debug.

---

## Estructura sugerida

Ejemplo de organizacion minima:

```text
scripts/
|-- awacs/
|   |-- AGENTS.md
|   |-- README.md
|   |-- awacs_agent.lua
|   |-- awacs_config.lua
|   |-- profile_presets.lua
|   |-- perception.lua
|   |-- tracking.lua
|   |-- threat_eval.lua
|   |-- comms.lua
|   |-- message_builder.lua
|   |-- output.lua
|   |-- bootstrap_moose.lua
|   |-- adapters/
|   |   `-- moose_adapter.lua
|   `-- examples/
|       |-- moose_start_example.lua
|       `-- moose_start_academy_basic.lua
```


