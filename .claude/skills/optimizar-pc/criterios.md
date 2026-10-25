# Criterios de interpretación

Reglas para leer `diagnostico-*.json` y decidir qué palanca mover. Los umbrales son **orientativos**: sirven para priorizar, no son verdades absolutas. Siempre se cita el dato real del JSON y se confirma con el usuario cuando algo depende de su uso.

## 1. Señales y qué hacer

### Memoria (RAM)

| Señal en el JSON | Umbral orientativo | Interpretación | Acción |
|---|---|---|---|
| `metricas.ramUsoPct` en reposo | > 70 % | Poca memoria libre antes de abrir el juego o el navegador | Reducir inicio (`inicio-*`), servicios de terceros (`svc3-*`), `nav-*` |
| `hardware.ramGB` | ≤ 8 GB | Límite físico para juegos actuales con navegador abierto | Recomendar 16 GB (mejora de hardware) |
| `hardware.ramModulos` = 1 y `ramRanurasTotales` ≥ 2 | — | Probable **canal simple**: con GPU integrada el impacto suele ser grande | Recomendar un segundo módulo igual (hardware) |
| `ramModulos[].mhzConfigurada` < `mhz` | diferencia notable | La RAM puede estar por debajo de su velocidad nominal (perfil XMP/EXPO desactivado en la BIOS) | Solo informar; tocar la BIOS queda fuera de este flujo |
| `metricas.paginasPorSeg` | alto y sostenido (cientos o más) | Windows está usando el disco como memoria | Liberar RAM; recomendar más RAM |
| `comprometidaGB` cerca de `limiteCompromisoGB` | > 85 % | Riesgo de quedarse sin memoria | Verificar `ajustes.paginacionAutomatica` = true; no desactivar el archivo de paginación |

### Disco

| Señal | Umbral | Interpretación | Acción |
|---|---|---|---|
| `discos.tipoDiscoSistema` = `HDD` | — | Es el cuello de botella más común en equipos modestos: arranque, carga de juegos, todo | Recomendar SSD (la mejora física con más impacto); considerar `svc-sysmain` y `svc-busqueda` si el disco está saturado |
| `metricas.discoOcupadoPct` en reposo | > 50 % | Algo usa el disco sin parar | Buscar el culpable en `procesos.topCpu` (indexador, actualizaciones, análisis de antivirus, SysMain) |
| `discos.volumenes[].librePct` (sistema) | < 15 % | Poco espacio libre: Windows y las actualizaciones se resienten | `limpieza-*`, desinstalar juegos o programas que no usa |
| `ajustes.desfragProgramada` = `Disabled` | — | La optimización automática está apagada | `mant-optimizar-unidad` |

### CPU, GPU y pantalla

| Señal | Umbral | Interpretación | Acción |
|---|---|---|---|
| `metricas.cpuPromedioPct` en reposo | > 10-15 % | Algún proceso consume sin que el usuario haga nada | Ver `procesos.topCpu`; si es desconocido → sospechoso (posible minero) |
| `hardware.gpu[].diasDriver` | > 180 | Driver antiguo | `juego-driver-gpu` |
| `hardware.gpu[].hzActual` < `hzMax` | — | El monitor puede estar a menos Hz de los que soporta (el dato de WMI es indicativo) | `juego-frecuencia-monitor` |
| Dos GPU en `hardware.gpu` (integrada + dedicada) en portátil | — | El juego podría estar usando la integrada | `juego-gpu-dedicada-portatil` |
| `ajustes.planEnergiaActivo` = equilibrado o ahorro en escritorio | — | La CPU baja frecuencia más de la cuenta | `energia-alto-rendimiento` |
| `sistema.esPortatil` y solo existe el plan Equilibrado | — | Portátil con Modern Standby | `energia-modo-rendimiento-manual` |
| `sistema.enBateria` = true durante el diagnóstico | — | Métricas no representativas | Repetir el diagnóstico enchufado |

### Sistema y estabilidad

| Señal | Umbral | Interpretación | Acción |
|---|---|---|---|
| `sistema.reinicioPendiente` = true | — | Hay actualizaciones a medio instalar | Reiniciar antes de optimizar |
| `sistema.diasEncendido` | > 7 | Con el inicio rápido, "Apagar" no reinicia el kernel | `sistema-reinicio-regular` |
| `arranque.eventos[0].arranqueMs` | > 60 000 en SSD o > 120 000 en HDD | Arranque lento | Ver `arranque.degradaciones` (qué app o driver lo retrasa) y `inicio.entradas` |
| `estabilidad.erroresHardwareWhea` | > 0 | Errores de hardware reportados por el procesador (RAM, CPU, overclock, temperatura) | **Alerta**: investigar antes de optimizar; no se arregla con software |
| `estabilidad.apagadosInesperados` | > 0 repetidos | Cortes de energía, temperatura, fuente de alimentación o drivers | Alerta; preguntar al usuario si se apaga solo jugando (posible temperatura) |
| `temporales.pantallazosAzules` | recientes | Pantallazos azules | `mant-reparar-sistema`, `juego-driver-gpu`; alerta |
| `estabilidad.appsQueFallan` | repetidos | Una app concreta se cierra sola | Informar; reinstalar o actualizar esa app |

### Seguridad

| Señal | Interpretación | Acción |
|---|---|---|
| `seguridad.defender.tiempoReal` = false y ningún otro antivirus activo | Equipo desprotegido | Alerta crítica; reactivar desde Seguridad de Windows (lo hace el usuario) |
| Dos o más antivirus con `activo` = true | Se pisan entre sí y duplican el trabajo en segundo plano | Recomendar quedarse con uno (el de Windows es suficiente para la mayoría); desinstalación manual |
| `seguridad.amenazas` con `activa` = true | Malware presente | Fase de seguridad antes de optimizar |
| `sospechosos` no vacío | Señales, no pruebas | Preguntar al usuario → análisis de Defender si no lo reconoce |

### Red (para juegos en línea)

| Señal | Interpretación | Acción |
|---|---|---|
| Adaptador activo `inalambrico` = true | El Wi-Fi añade latencia variable | Recomendar cable Ethernet para jugar (manual) |
| Ping a la puerta de enlace con `promMs` > 10 o pérdida > 0 | El problema está en la red de casa (Wi-Fi, router) | Acercarse al router, banda de 5 GHz, cable |
| Puerta de enlace bien, pero `jitterMs` o pérdida altos hacia 1.1.1.1 | Problema del proveedor de internet | Informar; fuera del alcance del PC |

### Navegador

| Señal | Interpretación | Acción |
|---|---|---|
| `procesos.agrupados` con chrome, msedge, firefox u opera entre los que más memoria usan | El navegador es el mayor consumidor | `nav-ahorro-memoria`; revisar extensiones |
| Procesos de msedge con Edge cerrado | Arranque acelerado o segundo plano activos | `nav-edge-arranque-rapido-off`, `nav-edge-segundo-plano-off` |

## 2. Qué NO hacer (mitos frecuentes)

Ninguna de estas prácticas forma parte del flujo, aunque se recomienden mucho en internet:

- **"Liberadores de RAM" o "boosters"**: Windows ya gestiona la memoria; vaciarla a la fuerza provoca más lecturas de disco después.
- **Limpiadores de registro**: no aportan una mejora apreciable y pueden romper programas. Microsoft no da soporte a su uso.
- **Desactivar el archivo de paginación**, aunque haya mucha RAM: hay programas y juegos que lo necesitan.
- **Borrar Prefetch o la caché del navegador "para acelerar"**: esas cachés existen para ir *más rápido*. Borrar la del navegador solo sirve para resolver un problema puntual de una web.
- **Desactivar Windows Update, Defender o el firewall.**
- **Scripts de "debloat" descargados o ISOs de Windows modificadas**: no se pueden auditar y pueden dejar el sistema inestable o inseguro.
- **Ajustes de red en el registro** (TCP, Nagle, "network throttling", QoS) sin una medición que lo justifique.
- **Desactivar servicios en masa** siguiendo listas de internet.
- **Cambiar la prioridad o la afinidad de procesos de forma permanente.**
- **Overclock o undervolt**: fuera del alcance de este flujo.

## 3. Expectativas honestas

- Optimizar el software **reduce la carga en segundo plano y corrige configuraciones**; no sube el techo del hardware.
- Las mejoras grandes suelen venir de: malware o antivirus duplicados, demasiados programas de inicio, plan de energía o frecuencia del monitor mal configurados, RAM en canal simple, drivers muy antiguos y disco casi lleno.
- Si el juego está **limitado por la GPU**, lo que más cambia los FPS son los **ajustes dentro del juego**.
- Nunca prometas cifras. Se miden antes y después, y se informa lo que salió.

## 4. Ajustes dentro del juego (orientación para el informe final)

**Saber qué limita**: con el juego abierto, Administrador de tareas > Rendimiento, o el widget de rendimiento de Xbox Game Bar (Win+G).
- GPU cerca del 95-100 % → **limitado por la GPU**.
- GPU baja y un núcleo de CPU al máximo → **limitado por la CPU**.

**Limitado por la GPU**: bajar la resolución de renderizado o usar escalado (FSR, XeSS o DLSS si la tarjeta es NVIDIA RTX); bajar sombras, iluminación volumétrica, oclusión ambiental y reflejos.

**Limitado por la CPU**: bajar la distancia de dibujado, la densidad de multitudes y la física; cerrar el navegador mientras se juega.

**En general**:
- Limitar los FPS a la frecuencia del monitor (o un poco menos) reduce temperatura y tirones, sobre todo en portátiles.
- En portátiles con dos GPU, asignar el juego a la GPU dedicada (`juego-gpu-dedicada-portatil`).
- Jugar enchufado y con buena ventilación: un portátil caliente baja su frecuencia.
- Instalar los juegos en el SSD si hay uno.
