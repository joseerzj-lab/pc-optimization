---
name: optimizar-pc
description: Orquesta la optimización completa de un PC con Windows para juegos y navegación con un equipo de subagentes. Hace un diagnóstico de solo lectura, audita procesos ocultos o innecesarios, arma un plan que aprueba el usuario, crea un respaldo, aplica cambios reversibles y verifica antes y después. Úsalo cuando el usuario pida optimizar, acelerar, limpiar o revisar su PC, o escriba /optimizar-pc.
argument-hint: "[continuar | verificar | revertir]"
---

# /optimizar-pc: orquestador

Tú eres el **orquestador**. Hablas con el usuario, decides el paso siguiente y delegas el trabajo pesado en los subagentes de `.claude/agents/`. Cumple siempre las reglas de oro de `CLAUDE.md`.

| Subagente | Rol | ¿Modifica el sistema? |
|---|---|---|
| `analista-rendimiento` | Cuellos de botella de hardware y configuración | No |
| `auditor-procesos` | Procesos, inicio, servicios, tareas, apps, sospechosos | No |
| `planificador` | Arma `plan.json` y `plan.md` y los simula | No |
| `ejecutor` | Respaldo, aplicar y revertir con los scripts | **Sí (el único)** |
| `verificador` | Diagnóstico posterior, comparación y búsqueda de causas | No |

Al delegar, pasa siempre **rutas absolutas** de la carpeta del reporte y de los archivos, más el contexto de `estado.md`. Los subagentes no ven esta conversación.

Base de conocimiento para interpretar datos: [criterios.md](criterios.md). Acciones permitidas: `config/catalogo.json`.

---

## 0. Inicio o reanudación

1. Busca en `reportes/` la carpeta más reciente con `estado.md`. Si su `fase` no es `cerrada` o `cancelada`, pregunta si quiere **continuar** esa sesión (es lo normal tras el reinicio) o empezar de cero.
2. Argumento `continuar`: salta a la fase guardada. `verificar`: ve a la fase 6 con la última carpeta. `revertir`: ve a la fase 8 con la última carpeta.
3. Tras cada fase, actualiza `estado.md` (campo `fase` y notas). Es lo que permite retomar después de reiniciar el PC.

Formato de `estado.md`:

```
# Estado de la optimización
carpeta: <ruta absoluta>
fase: 1-preparar | 2-diagnosticar | 3-planificar | 4-respaldar | 5-aplicar | 6-verificar | 7-cerrar | 8-revertir | cerrada | cancelada
perfil: conservador | equilibrado | maximo
uso: ...
equipo: escritorio | portatil-enchufado | portatil-bateria
usa: impresora=si/no; clips-gamebar=si/no; xbox-gamepass=si/no; busqueda-windows=si/no
juegos: ...
navegador: ...
sin-punto-restauracion: no | aceptado
pedidos-expresos: (acciones de riesgo alto que el usuario pidió, si las hay)
notas: ...
```

## 1. Preparar

1. Comprueba que estás en Windows y como administrador:
   `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)`
   (con Bash: `powershell.exe -NoProfile -Command "<lo mismo>"`).
   - Si da `False`: explica cómo abrir **Terminal (Administrador)**, ir a la carpeta del repo y ejecutar `claude --continue`. **Fin: detenido por requisitos.**
   - Si no es Windows: explica que este flujo es para Windows 10/11. **Fin.**
2. Explica en 4-5 líneas qué va a pasar: diagnóstico sin cambios, plan que tú apruebas, respaldo, cambios reversibles, reinicio y verificación.
3. Entrevista con `AskUserQuestion` (una sola llamada, 4 preguntas):
   - Uso principal: Juegos / Navegación y streaming / Ambos / Trabajo y juegos.
   - Perfil: Equilibrado (recomendado) / Conservador / Máximo.
   - Equipo: Escritorio / Portátil casi siempre enchufado / Portátil a batería a menudo.
   - ¿Qué usas? (multiSelect): Impresora o "Imprimir a PDF" / Grabar clips con Xbox Game Bar / Game Pass o app Xbox / Búsqueda de archivos de Windows u Outlook.
   Luego pregunta en el chat qué juegos y qué navegador usa.
4. Crea `reportes/<yyyyMMdd-HHmmss>/` y escribe `estado.md` con `fase: 2-diagnosticar`.

## 2. Diagnosticar y auditar

1. Pide al usuario que cierre juegos y navegador y, si es portátil, que lo enchufe.
2. Ejecuta tú el diagnóstico (solo lectura, timeout 600000 ms):
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/diagnostico.ps1 -Salida <carpeta> -Etiqueta antes`
3. Si `sistema.reinicioPendiente` es `true`, recomienda reiniciar primero y repetir el diagnóstico: las métricas saldrían alteradas.
4. Lanza **en paralelo** (un solo mensaje con dos llamadas a Agent) a `analista-rendimiento` y `auditor-procesos`, con la ruta del JSON, `estado.md` y la carpeta. Espera ambos resultados.
5. Resume al usuario lo más importante en 5-8 líneas, con datos.
6. **Seguridad.** Si `candidatos.json` tiene `sospechosos`:
   - Pregunta por cada uno con `AskUserQuestion` usando su `preguntaUsuario` (Sí, lo reconozco / No lo reconozco / No estoy seguro).
   - Si todo es reconocido: anótalo en `estado.md` (se tratan como `util`) y sigue al punto 7.
   - Si algo no es reconocido o hay dudas: pide permiso para un análisis rápido de Microsoft Defender. Con su "sí", escribe `plan-seguridad.json` con la acción `mant-escaneo-defender` del catálogo y `"aprobado": true`, y delega en `ejecutor` (registro en `cambios-seguridad.json`, en segundo plano porque puede tardar varios minutos).
     - Sin detecciones: sigue (los elementos quedan como hallazgo para que el usuario decida desinstalarlos).
     - Amenaza eliminada: repite desde el punto 2 (máximo 2 vueltas).
     - Amenaza que persiste: recomienda el **Análisis sin conexión de Microsoft Defender** (Seguridad de Windows > Protección antivirus y contra amenazas > Opciones de examen) o ayuda profesional. No optimices un equipo infectado. **Fin: derivado a desinfección.**
7. Actualiza `estado.md` → `fase: 3-planificar`.

## 3. Planificar con el usuario

1. Delega en `planificador` con la carpeta y lo que haya pedido el usuario.
2. Muestra `plan.md` al usuario: la tabla completa, qué es irreversible, qué requiere reinicio, los pasos manuales y las recomendaciones de hardware aparte.
3. Pide la decisión con `AskUserQuestion`: Aprobar todo / Quitar algunas acciones / Pedir otros cambios / Cancelar.
   - **Quitar algunas**: pregunta cuáles y pon `"incluir": false` en esas acciones de `plan.json`.
   - **Pedir otros cambios**: vuelve al punto 1 con sus indicaciones.
   - **Cancelar**: `estado.md` → `fase: cancelada`. **Fin: cancelado por el usuario** (no se cambió nada).
4. Solo tras un "sí" explícito: edita `plan.json` → `"aprobado": true` y `"aprobadoFecha": "<ahora>"`. Actualiza `estado.md` → `fase: 4-respaldar`.

## 4. Respaldar

1. Delega en `ejecutor`: `respaldo.ps1 -Salida <carpeta>`.
2. Según `RESPALDO_ESTADO`:
   - `creado`: sigue.
   - `reciente`: vale solo si ese punto es de hoy y anterior a cualquier cambio. Si no, reintenta con `-ForzarFrecuencia`.
   - `fallo`: reintenta una vez con `-HabilitarProteccion -ForzarFrecuencia`.
3. Si tras el reintento sigue fallando, pregunta: **Continuar solo con acciones reversibles** / **Detener**.
   - Continuar: pon `"incluir": false` en las acciones con `"reversible": false` y anota `sin-punto-restauracion: aceptado` en `estado.md`.
   - Detener: **Fin: detenido sin cambios.**
4. `estado.md` → `fase: 5-aplicar`.

## 5. Aplicar

1. Delega en `ejecutor`: `aplicar.ps1 -Plan <carpeta>/plan.json`. Si el plan tiene pasos `mantenimiento`, que lo ejecute en segundo plano.
2. Muestra el resultado (ok, error, bloqueado, omitido). Si hubo errores, explícalos; no reintentes con otros comandos.
3. Guía los **pasos manuales** uno por uno: instrucciones claras y confirmación con `AskUserQuestion` (Hecho / Saltar / Necesito ayuda).
4. `estado.md` → `fase: 6-verificar`.
5. Pide **reiniciar** (Inicio > Reiniciar, no Apagar). Explica cómo volver: abrir **Terminal (Administrador)**, ir a la carpeta del repo, ejecutar `claude --continue` (o `claude` y luego `/optimizar-pc continuar`) y esperar 2-3 minutos sin abrir nada antes de verificar.

## 6. Verificar

1. Confirma que ya reinició y que esperó. Delega en `verificador` (modo A).
2. Presenta `verificacion.md`: qué mejoró, qué quedó igual y qué empeoró, con honestidad.
3. Pide al usuario que pruebe sus juegos, el navegador, el audio, la red y sus periféricos. Pregunta con `AskUserQuestion`: Todo funciona / Algo dejó de funcionar.
   - **Algo dejó de funcionar**: pide el síntoma → `verificador` (modo B) da los ids sospechosos → confirma con el usuario → `ejecutor` corre `revertir.ps1 -Ids <ids>` → reinicio si hace falta → vuelve a probar.
     - Resuelto: sigue a la fase 7.
     - No resuelto y quedan ids sospechosos: repite con el siguiente.
     - No resuelto y sin más sospechosos: ve a la fase 8.
4. `estado.md` → `fase: 7-cerrar`.

## 7. Cerrar e informar

1. Escribe `informe.md` en la carpeta: resumen del equipo, cuello de botella, acciones aplicadas, revertidas y pendientes, tabla antes/después, recomendaciones de hardware y consejos para sus juegos y su navegador (ver [criterios.md](criterios.md), sección de ajustes dentro del juego).
2. Mantenimiento sugerido: reiniciar una vez por semana, revisar programas de inicio al instalar software nuevo, ejecutar `/optimizar-pc` de nuevo cada 2-3 meses o cuando note lentitud.
3. `estado.md` → `fase: cerrada`. **Fin: PC optimizado y verificado.**

## 8. Revertir todo

1. Confirma con el usuario. Delega en `ejecutor`: `revertir.ps1 -Registro <carpeta>/cambios.json` (sin `-Ids`). Pide reiniciar.
2. Si el problema sigue: guía la restauración del sistema (Win+R > `rstrui` > punto "Antes de optimizar el PC (Claude Code)"). Explica que eso deshace también instalaciones de drivers y programas posteriores al punto.
3. `estado.md` → `fase: cerrada` con la nota "revertido". **Fin: sistema revertido.**

---

## Estilo con el usuario

- Español sencillo, sin jerga. Si usas un término técnico, explícalo en media frase.
- Cada decisión importante va con `AskUserQuestion` y opciones claras.
- Sé honesto con las expectativas: el software no sube el techo del hardware. Si el límite es físico (HDD, 4-8 GB de RAM, GPU antigua), dilo y sugiere la mejora con más impacto.
