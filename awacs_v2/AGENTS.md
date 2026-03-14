# AGENTS.md

## Propósito del módulo

Este directorio contiene la lógica del agente AWACS / GCI para DCS World.

El objetivo es construir un controlador táctico automatizado o semiautomatizado que sea:
- útil,
- sobrio,
- mantenible,
- configurable,
- reutilizable entre misiones.

Este agente no debe comportarse como un narrador omnisciente. Debe comportarse como un controlador táctico creíble, con disciplina de emisiones y foco en amenazas relevantes.

## Rol doctrinal del agente

El AWACS debe:
- mantener una imagen táctica simplificada y útil,
- priorizar amenazas para vuelos o paquetes protegidos,
- emitir BRAA, picture y avisos contextuales cuando aporten valor,
- evitar saturar la frecuencia,
- actualizar solo cuando haya cambios relevantes.

Debe ser más parecido a un controlador táctico que a un sistema de mensajes automáticos.

## Prioridades funcionales

Orden general de prioridad:
1. amenaza inmediata a paquete o vuelo protegido,
2. commit o intercept relevante,
3. aviso de grupo hostil prioritario,
4. picture útil para la situación táctica,
5. actualización significativa,
6. housekeeping mínimo.

No hablar por cada detección.
Hablar cuando la información sea accionable o cuando cambie la situación táctica.

## Capacidades esperadas

El agente debe poder evolucionar para cubrir:
- check-in de vuelos o paquetes,
- seguimiento de paquetes blue,
- detección de grupos hostiles relevantes,
- priorización por amenaza,
- BRAA simplificado o detallado según perfil,
- picture calls,
- threat advisories,
- merge warnings,
- clean / no factor cuando aplique,
- pérdida de contacto,
- actualizaciones con cooldown y supresión de duplicados.

## Perfiles de realismo

El módulo debe estar preparado para soportar perfiles como:
- `academy_basic`
- `academy_intermediate`
- `tactical_concise`
- `tactical_realistic`

Por defecto, este directorio debe asumir `tactical_realistic` salvo que la tarea indique otra cosa.

En `tactical_realistic`, priorizar:
- frases cortas,
- tono profesional,
- pocas repeticiones,
- énfasis en amenaza y utilidad,
- picture solo cuando aporte contexto real,
- BRAA cuando sea accionable para el receptor.

## Arquitectura deseada

Separar claramente estas responsabilidades:

1. `perception`
   - lectura de contactos relevantes,
   - estado de paquetes blue,
   - zonas, sectores, bullseye u otras referencias,
   - clasificación básica de grupos.

2. `tracking`
   - persistencia mínima de contactos,
   - timestamps,
   - historial útil para decidir cambios,
   - control de desapariciones o pérdida de track.

3. `threat_evaluation`
   - distancia a paquete,
   - aspecto hot/cold/flanking si aplica,
   - altitud relativa,
   - velocidad o cierre si aplica,
   - rol o categoría de amenaza,
   - prioridad resultante.

4. `comms_decision`
   - decidir si hablar,
   - decidir a quién hablar,
   - decidir tipo de mensaje,
   - aplicar cooldowns,
   - aplicar supresión de duplicados,
   - evitar spam.

5. `message_generation`
   - BRAA,
   - picture,
   - threat advisory,
   - merge / defensive / update calls,
   - fraseo según perfil.

6. `output`
   - radio,
   - texto,
   - logs,
   - hooks para debriefing.

7. `config`
   - perfiles de misión,
   - timings,
   - filtros,
   - umbrales,
   - canales de salida,
   - estilo de fraseo.

## Reglas de implementación

- No concentrar toda la lógica AWACS en una única función o archivo gigante.
- Mantener la evaluación táctica separada de la presentación del mensaje.
- Mantener la configuración fuera de la lógica siempre que tenga sentido.
- Los nombres concretos de grupos, sectores o paquetes deben venir de config.
- Todo cambio importante en criterio táctico debe quedar trazable.
- Manejar datos incompletos de DCS sin fallos silenciosos.
- Preferir un MVP funcional y ampliable antes que un sistema “perfecto” pero frágil.

## Reglas de comunicaciones

El agente debe:
- hablar poco,
- hablar claro,
- hablar con prioridad.

Evitar:
- repetir el mismo BRAA sin cambio relevante,
- updates constantes sin valor,
- mensajes excesivamente verbosos,
- picture innecesario cuando basta una llamada prioritaria,
- omnisciencia injustificada si la lógica del escenario no lo soporta.

Preguntas que deben guiar la decisión de hablar:
- ¿hay amenaza accionable?
- ¿la información cambió de forma relevante?
- ¿el paquete o vuelo necesita esta información ahora?
- ¿ya se dijo algo equivalente hace poco?
- ¿este mensaje desplaza otro más importante?

## Criterios tácticos recomendados

Cuando falte una regla explícita, priorizar contactos por combinación razonable de:
- proximidad al paquete protegido,
- cierre hacia el paquete,
- aspecto,
- altitud amenazante,
- tipo de grupo o rol,
- persistencia de la amenaza,
- novedad del contacto,
- urgencia temporal.

Dejar estas reglas parametrizables siempre que no complique en exceso el diseño.

## Configuración recomendada

Las tablas de configuración deberían contemplar, cuando aplique:
- paquetes blue,
- sectores o zonas monitorizadas,
- bullseye o referencias,
- cooldown por paquete o por canal,
- ventana de supresión de duplicados,
- umbral mínimo de amenaza,
- perfil de fraseo,
- flags de salida radio/texto/log,
- niveles de depuración,
- timings de evaluación.

## Logging específico de AWACS

Registrar, al menos cuando aplique:
- contacto detectado,
- contacto descartado y por qué,
- amenaza priorizada,
- mensaje emitido,
- mensaje suprimido por cooldown o duplicado,
- pérdida de track,
- errores de integración.

El log debe permitir entender:
- qué sabía el agente,
- qué priorizó,
- por qué habló,
- por qué calló.

## Forma de trabajar en este directorio

Cuando la tarea afecte a AWACS:

1. Resume el objetivo táctico y técnico.
2. Identifica si el cambio afecta a:
   - percepción,
   - tracking,
   - evaluación,
   - decisión,
   - mensaje,
   - output,
   - config.
3. Propón módulos o funciones antes de hacer cambios grandes.
4. Implementa primero una versión operativa mínima.
5. Explica cómo validar el comportamiento en misión real o de prueba.
6. Si hay varias rutas, compara:
   - la más rápida,
   - la más robusta,
   - la más doctrinal.

## Formato obligatorio de respuesta

Responder con esta estructura:

A) Resumen técnico del objetivo  
B) Suposiciones explícitas  
C) Arquitectura propuesta  
D) Plan de implementación  
E) Código  
F) Cómo probarlo en misión  
G) Riesgos y siguientes mejoras

## Qué no hacer

- No hacer del AWACS un narrador continuo.
- No acoplar toda la lógica a una sola misión.
- No mezclar cálculo de amenaza y construcción de fraseo en bloques indivisibles.
- No hardcodear nombres de grupos o zonas si pueden ir en config.
- No introducir realismo doctrinal que rompa la utilidad práctica.
- No priorizar cantidad de mensajes sobre calidad táctica.