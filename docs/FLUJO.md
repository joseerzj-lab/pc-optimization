# Flujo del proceso de optimización

Modelo del proceso en **BPMN 2.0**, en dos niveles:

- **L1, visión general**: las 8 fases y sus posibles finales.
- **L2, detalle**: cada fase con carriles (quién hace qué). Las fases 1.0, 7.0 y 8.0 son lineales y se describen en tablas.

Fuente editable: [`diagramas/flujo-optimizacion.drawio`](diagramas/flujo-optimizacion.drawio). Ábrela en [diagrams.net](https://app.diagrams.net) (Archivo > Abrir desde > Dispositivo); cada nivel es una pestaña. Bajo cada imagen hay una versión en Mermaid (texto) que GitHub dibuja directamente.

## Cómo leer los diagramas

| Forma | Significado |
|---|---|
| Óvalo verde | Inicio del proceso (un solo inicio por diagrama) |
| Óvalo rojo de borde grueso | Final: estado terminal del proceso |
| Rectángulo morado | Subproceso: tiene su propio diagrama L2 |
| Rectángulo azul | Tarea de una persona o de un agente de IA |
| Rectángulo gris | Tarea automática: la ejecuta un script de PowerShell |
| Rombo con pregunta | Decisión exclusiva (XOR): se toma una sola rama |
| Rombo con **+** | Paralelo (AND): las ramas corren a la vez y se esperan en el rombo de unión |
| Rombo vacío | Unión de caminos |
| Nota con esquina doblada | Archivo que se genera en `reportes/<fecha>/` |

**Carriles (L2):** *Orquestador* es la sesión principal de Claude Code que sigue `/optimizar-pc` y habla contigo. *Usuario* eres tú. *Subagentes y scripts* son los agentes de `.claude/agents/` y los scripts de `scripts/`. Entre corchetes se indica qué agente hace cada tarea.

## Alcance del proceso

| Elemento | Definición |
|---|---|
| Disparador | El usuario ejecuta `/optimizar-pc` en Claude Code, abierto como administrador en la carpeta del repositorio |
| Entradas | El PC con Windows 10/11, las respuestas del usuario (uso, perfil, qué usa), `config/catalogo.json` |
| Salidas | PC optimizado, `informe.md`, registro reversible `cambios.json`, punto de restauración |
| Finales posibles | **PC optimizado y verificado** (éxito) · Detenido: faltan requisitos · Derivado a desinfección · Cancelado por el usuario · Detenido sin cambios · Sistema revertido |

## L1: visión general

![Visión general del proceso](diagramas/0-vision-general.png)

<details><summary>Versión Mermaid</summary>

```mermaid
flowchart TB
    s0(["Usuario inicia /optimizar-pc"])
    p1[["1.0 Preparar sesión"]]
    g1{"¿Requisitos cumplidos?"}
    e1(["Detenido: faltan requisitos"])
    p2[["2.0 Diagnosticar y auditar"]]
    g2{"¿Amenaza sin resolver?"}
    e2(["Derivado a desinfección"])
    p3[["3.0 Planificar con el usuario"]]
    g3{"¿Plan aprobado?"}
    e3(["Cancelado por el usuario"])
    p4[["4.0 Respaldar sistema"]]
    g4{"¿Respaldo listo?"}
    e4(["Detenido sin cambios"])
    p5[["5.0 Aplicar cambios"]]
    p6[["6.0 Verificar resultados"]]
    g5{"¿Resultado aceptable?"}
    p8[["8.0 Revertir cambios"]]
    p7[["7.0 Cerrar e informar"]]
    e5(["Sistema revertido"])
    e6(["PC optimizado y verificado"])
    s0 --> p1
    p1 --> g1
    g1 -->|"Sí"| p2
    p2 --> g2
    g2 -->|"No"| p3
    p3 --> g3
    g3 -->|"Sí"| p4
    p4 --> g4
    g4 -->|"Sí"| p5
    p5 --> p6
    p6 --> g5
    g5 -->|"Sí"| p7
    p8 --> e5
    p7 --> e6
    g1 -->|"No"| e1
    g2 -->|"Sí"| e2
    g3 -->|"No"| e3
    g4 -->|"No"| e4
    g5 -->|"No"| p8
    classDef inicio fill:#d5e8d4,stroke:#82b366,color:#000
    classDef fin fill:#f8cecc,stroke:#b85450,stroke-width:3px,color:#000
    classDef tarea fill:#dae8fc,stroke:#6c8ebf,color:#000
    classDef auto fill:#f5f5f5,stroke:#666666,color:#000
    classDef sub fill:#e1d5e7,stroke:#9673a6,color:#000,font-weight:bold
    classDef gw fill:#fff2cc,stroke:#d6b656,color:#000
    classDef dato fill:#ffffff,stroke:#666666,color:#000
    class s0 inicio
    class p1,p2,p3,p4,p5,p6,p8,p7 sub
    class g1,g2,g3,g4,g5 gw
    class e1,e2,e3,e4,e5,e6 fin
```

</details>

## 1.0 Preparar sesión

| # | Quién | Qué pasa |
|---|---|---|
| 1 | Orquestador | Verifica que es Windows y que Claude Code corre como administrador. Si no, explica cómo abrirlo bien y termina (*Detenido: faltan requisitos*). |
| 2 | Orquestador | Explica en pocas líneas qué va a pasar. |
| 3 | Usuario | Responde la entrevista: uso principal, perfil (conservador, equilibrado o máximo), tipo de equipo, si usa impresora, clips de Game Bar, Game Pass o búsqueda de Windows; juegos y navegador. |
| 4 | Orquestador | Crea `reportes/<fecha>/estado.md` con las respuestas. Este archivo permite retomar tras reiniciar. |

## 2.0 Diagnosticar y auditar

![2.0 Diagnosticar y auditar](diagramas/2-diagnosticar-y-auditar.png)

- El diagnóstico es **solo lectura**. Los dos análisis corren **en paralelo** para ahorrar tiempo.
- Un elemento "sospechoso" tiene señales, no pruebas: por eso primero se te pregunta si lo reconoces.
- El análisis de Defender lo corre el `ejecutor` con tu permiso. Si eliminó algo, se repite el diagnóstico (máximo 2 vueltas) para no medir un equipo infectado.

<details><summary>Versión Mermaid</summary>

```mermaid
flowchart TB
    s(["Requisitos verificados"])
    t1["<b>Usuario</b><br/>Cerrar juegos y navegador"]
    t2["<b>Claude</b><br/>Ejecutar diagnostico.ps1 (solo lectura)"]
    a1{"#43;"}
    t3["<b>Subagente</b><br/>Analizar rendimiento<br/>[analista-rendimiento]"]
    t4["<b>Subagente</b><br/>Auditar procesos, inicio, servicios y tareas<br/>[auditor-procesos]"]
    a2{"#43;"}
    t5["<b>Claude</b><br/>Consolidar hallazgos"]
    g1{"¿Hay elementos sospechosos?"}
    t6["<b>Usuario</b><br/>Indicar si reconoce cada elemento"]
    g2{"¿Reconoce todos?"}
    t7["<b>Subagente</b><br/>Analizar con Microsoft Defender<br/>[ejecutor]"]
    g3{"¿Resultado del análisis?"}
    m1{" "}
    e2(["Amenaza sin resolver"])
    t8["<b>Claude</b><br/>Priorizar hallazgos por impacto y riesgo"]
    e1(["Hallazgos listos"])
    s --> t1
    t1 --> t2
    t2 --> a1
    a1 --> t3
    a1 --> t4
    t3 --> a2
    t4 --> a2
    a2 --> t5
    t5 --> g1
    g1 -->|"No"| t8
    g1 -->|"Sí"| t6
    t6 --> g2
    g2 -->|"Sí"| m1
    g2 -->|"No"| t7
    t7 --> g3
    g3 -->|"Amenaza persiste"| e2
    g3 -->|"Sin detecciones"| m1
    g3 -->|"Amenaza eliminada: repetir (máx. 2)"| t2
    m1 --> t8
    t8 --> e1
    classDef inicio fill:#d5e8d4,stroke:#82b366,color:#000
    classDef fin fill:#f8cecc,stroke:#b85450,stroke-width:3px,color:#000
    classDef tarea fill:#dae8fc,stroke:#6c8ebf,color:#000
    classDef auto fill:#f5f5f5,stroke:#666666,color:#000
    classDef sub fill:#e1d5e7,stroke:#9673a6,color:#000,font-weight:bold
    classDef gw fill:#fff2cc,stroke:#d6b656,color:#000
    classDef dato fill:#ffffff,stroke:#666666,color:#000
    class s inicio
    class t1,t3,t4,t5,t6,t8 tarea
    class t2,t7 auto
    class a1,a2,g1,g2,g3,m1 gw
    class e2,e1 fin
```

</details>

## 3.0 Planificar con el usuario

![3.0 Planificar con el usuario](diagramas/3-planificar.png)

- El `planificador` solo puede usar acciones del catálogo. Antes de mostrarte el plan, lo **simula** (`aplicar.ps1 -Simular`) para descartar lo que no existe en tu equipo o está protegido.
- "Aprobar" incluye aprobar quitando algunas acciones. Solo después de tu "sí" el orquestador marca `"aprobado": true`.

<details><summary>Versión Mermaid</summary>

```mermaid
flowchart TB
    s(["Hallazgos listos"])
    t1["<b>Subagente</b><br/>Armar plan desde el catálogo<br/>[planificador]"]
    t2["<b>Subagente</b><br/>Simular plan sin cambios (aplicar.ps1 -Simular)"]
    t3["<b>Claude</b><br/>Presentar plan y simulación"]
    t4["<b>Usuario</b><br/>Revisar el plan"]
    g1{"¿Decisión sobre el plan?"}
    t5["<b>Claude</b><br/>Marcar plan como aprobado"]
    e2(["Cancelado por el usuario"])
    e1(["Plan aprobado"])
    s --> t1
    t1 --> t2
    t2 --> t3
    t3 --> t4
    t4 --> g1
    g1 -->|"Aprobar"| t5
    g1 -->|"Cancelar"| e2
    g1 -->|"Pedir cambios"| t1
    t5 --> e1
    classDef inicio fill:#d5e8d4,stroke:#82b366,color:#000
    classDef fin fill:#f8cecc,stroke:#b85450,stroke-width:3px,color:#000
    classDef tarea fill:#dae8fc,stroke:#6c8ebf,color:#000
    classDef auto fill:#f5f5f5,stroke:#666666,color:#000
    classDef sub fill:#e1d5e7,stroke:#9673a6,color:#000,font-weight:bold
    classDef gw fill:#fff2cc,stroke:#d6b656,color:#000
    classDef dato fill:#ffffff,stroke:#666666,color:#000
    class s inicio
    class t1,t3,t4,t5 tarea
    class t2 auto
    class g1 gw
    class e2,e1 fin
```

</details>

## 4.0 Respaldar sistema

![4.0 Respaldar sistema](diagramas/4-respaldar.png)

- Windows solo permite un punto de restauración cada 24 h y a veces la Protección del sistema viene apagada: el reintento resuelve ambos casos.
- Sin punto de restauración no se aplica nada irreversible, y solo se sigue si tú lo aceptas.

<details><summary>Versión Mermaid</summary>

```mermaid
flowchart TB
    s(["Plan aprobado"])
    t1["<b>Subagente</b><br/>Crear punto de restauración e instantánea<br/>[ejecutor]"]
    g1{"¿Punto de restauración creado?"}
    t2["<b>Subagente</b><br/>Activar protección y forzar frecuencia<br/>[ejecutor]"]
    t3["<b>Usuario</b><br/>Decidir si continuar sin punto de restauración"]
    g2{"¿Continuar?"}
    t4["<b>Claude</b><br/>Excluir acciones irreversibles del plan"]
    e2(["Detenido sin cambios"])
    m1{" "}
    e1(["Respaldo listo"])
    s --> t1
    t1 --> g1
    g1 -->|"Sí"| m1
    g1 -->|"No, primer intento"| t2
    t2 --> t1
    g1 -->|"No, tras reintento"| t3
    t3 --> g2
    g2 -->|"Sí, solo reversibles"| t4
    g2 -->|"No"| e2
    t4 --> m1
    m1 --> e1
    classDef inicio fill:#d5e8d4,stroke:#82b366,color:#000
    classDef fin fill:#f8cecc,stroke:#b85450,stroke-width:3px,color:#000
    classDef tarea fill:#dae8fc,stroke:#6c8ebf,color:#000
    classDef auto fill:#f5f5f5,stroke:#666666,color:#000
    classDef sub fill:#e1d5e7,stroke:#9673a6,color:#000,font-weight:bold
    classDef gw fill:#fff2cc,stroke:#d6b656,color:#000
    classDef dato fill:#ffffff,stroke:#666666,color:#000
    class s inicio
    class t1,t2 auto
    class g1,g2,m1 gw
    class t3,t4 tarea
    class e2,e1 fin
```

</details>

## 5.0 Aplicar cambios

![5.0 Aplicar cambios](diagramas/5-aplicar.png)

- `aplicar.ps1` guarda el **estado previo** de cada elemento antes de tocarlo: eso es lo que permite revertir con precisión.
- Rechaza cualquier paso sobre elementos protegidos (Defender, Windows Update, firewall, etc.) aunque venga en el plan.
- Al reiniciar se cierra Claude Code. Para seguir: abre la Terminal como administrador en la carpeta del repo y ejecuta `claude --continue`.

<details><summary>Versión Mermaid</summary>

```mermaid
flowchart TB
    s(["Respaldo listo"])
    t1["<b>Subagente</b><br/>Leer siguiente acción del plan<br/>[ejecutor, aplicar.ps1]"]
    g1{"¿Protegida o ya aplicada?"}
    t2["<b>Subagente</b><br/>Registrar como bloqueada u omitida"]
    t3["<b>Subagente</b><br/>Guardar estado previo en cambios.json"]
    t4["<b>Subagente</b><br/>Ejecutar el paso"]
    t5["<b>Subagente</b><br/>Registrar resultado (ok o error)"]
    g2{"¿Quedan acciones?"}
    t6["<b>Claude</b><br/>Explicar resultados y pasos manuales"]
    t7["<b>Usuario</b><br/>Completar pasos manuales guiados"]
    t8["<b>Usuario</b><br/>Reiniciar el equipo"]
    e1(["Cambios aplicados"])
    s --> t1
    t1 --> g1
    g1 -->|"Sí"| t2
    g1 -->|"No"| t3
    t3 --> t4
    t4 --> t5
    t5 --> g2
    t2 --> g2
    g2 -->|"Sí"| t1
    g2 -->|"No"| t6
    t6 --> t7
    t7 --> t8
    t8 --> e1
    classDef inicio fill:#d5e8d4,stroke:#82b366,color:#000
    classDef fin fill:#f8cecc,stroke:#b85450,stroke-width:3px,color:#000
    classDef tarea fill:#dae8fc,stroke:#6c8ebf,color:#000
    classDef auto fill:#f5f5f5,stroke:#666666,color:#000
    classDef sub fill:#e1d5e7,stroke:#9673a6,color:#000,font-weight:bold
    classDef gw fill:#fff2cc,stroke:#d6b656,color:#000
    classDef dato fill:#ffffff,stroke:#666666,color:#000
    class s inicio
    class t1,t2,t3,t4,t5 auto
    class g1,g2 gw
    class t6,t7,t8 tarea
    class e1 fin
```

</details>

## 6.0 Verificar resultados

![6.0 Verificar resultados](diagramas/6-verificar.png)

- La medición posterior se hace en las mismas condiciones que la inicial (recién reiniciado, sin juegos ni navegador abiertos).
- Si algo dejó de funcionar, se revierte **solo el cambio sospechoso** y se vuelve a probar. Si no se encuentra la causa, se pasa a la reversión total (8.0).

<details><summary>Versión Mermaid</summary>

```mermaid
flowchart TB
    s(["Sesión retomada tras reiniciar"])
    t1["<b>Subagente</b><br/>Medir de nuevo y comparar antes y después<br/>[verificador]"]
    t2["<b>Subagente</b><br/>Interpretar resultados<br/>[verificador]"]
    t3["<b>Claude</b><br/>Explicar resultados"]
    t4["<b>Usuario</b><br/>Probar juegos, navegador y periféricos"]
    g1{"¿Algo dejó de funcionar?"}
    t5["<b>Subagente</b><br/>Identificar cambio responsable<br/>[verificador]"]
    t6["<b>Subagente</b><br/>Revertir cambios puntuales<br/>[ejecutor, revertir.ps1]"]
    t7["<b>Usuario</b><br/>Volver a probar"]
    g2{"¿Problema resuelto?"}
    m1{" "}
    e1(["Resultado aceptable"])
    e2(["Requiere reversión total"])
    s --> t1
    t1 --> t2
    t2 --> t3
    t3 --> t4
    t4 --> g1
    g1 -->|"No"| m1
    g1 -->|"Sí"| t5
    t5 --> t6
    t6 --> t7
    t7 --> g2
    g2 -->|"Sí"| m1
    g2 -->|"No, quedan sospechosos"| t5
    g2 -->|"No, sin más sospechosos"| e2
    m1 --> e1
    classDef inicio fill:#d5e8d4,stroke:#82b366,color:#000
    classDef fin fill:#f8cecc,stroke:#b85450,stroke-width:3px,color:#000
    classDef tarea fill:#dae8fc,stroke:#6c8ebf,color:#000
    classDef auto fill:#f5f5f5,stroke:#666666,color:#000
    classDef sub fill:#e1d5e7,stroke:#9673a6,color:#000,font-weight:bold
    classDef gw fill:#fff2cc,stroke:#d6b656,color:#000
    classDef dato fill:#ffffff,stroke:#666666,color:#000
    class s inicio
    class t1,t6 auto
    class t2,t3,t4,t5,t7 tarea
    class g1,g2,m1 gw
    class e1,e2 fin
```

</details>

## 7.0 Cerrar e informar

| # | Quién | Qué pasa |
|---|---|---|
| 1 | Orquestador | Escribe `informe.md`: equipo, cuello de botella, cambios aplicados, revertidos y pendientes, tabla antes/después. |
| 2 | Orquestador | Añade recomendaciones de hardware y ajustes dentro de tus juegos y del navegador. |
| 3 | Orquestador | Propone el mantenimiento: reiniciar cada semana, revisar el inicio al instalar programas, repetir `/optimizar-pc` cada 2-3 meses. |
| 4 | Orquestador | Marca `estado.md` como `cerrada`. **Fin: PC optimizado y verificado.** |

## 8.0 Revertir cambios

| # | Quién | Qué pasa |
|---|---|---|
| 1 | Usuario | Confirma que quiere deshacer todo. |
| 2 | `ejecutor` | Ejecuta `revertir.ps1` con todo `cambios.json`, en orden inverso. |
| 3 | Usuario | Reinicia y prueba. |
| 4 | Usuario + Orquestador | Si sigue fallando: restaurar sistema (Win+R > `rstrui` > punto "Antes de optimizar el PC (Claude Code)"). |
| 5 | Orquestador | Marca `estado.md` como `cerrada` (revertido). **Fin: sistema revertido.** |

## Validación del modelo

Los diagramas se generaron desde una sola especificación y pasaron estas comprobaciones automáticas en todos los niveles:

- [x] Un inicio por diagrama y al menos un final; todos los finales son estados reales del proceso.
- [x] Todo nodo es alcanzable desde el inicio y llega a algún final.
- [x] Cada decisión es una pregunta y todas sus ramas están etiquetadas; las ramas son excluyentes y cubren todos los casos.
- [x] Cada rombo paralelo (AND) que abre tiene su rombo de unión.
- [x] Cada ciclo (pedir cambios, reintentar respaldo, repetir diagnóstico, revertir otro sospechoso) tiene una salida.
- [x] Cada tarea empieza con un verbo.
- [x] Sin aristas cruzadas en draw.io; ruteo ortogonal; leyenda en cada pestaña.
