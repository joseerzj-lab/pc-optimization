# pc-optimization

Flujo para que **Claude Code** optimice un PC con **Windows 10/11** para **jugar y navegar**. Revisa procesos ocultos o innecesarios, programas de inicio, servicios y configuraciones con un equipo de agentes especializados, **sin cambiar nada que no apruebes y con todo respaldado y reversible**.

## Uso rápido

```
# 1. Terminal como administrador (Win+X > Terminal (Administrador))
git clone https://github.com/joseerzj-lab/pc-optimization.git C:\pc-optimization
cd C:\pc-optimization
claude

# 2. Dentro de Claude Code
/optimizar-pc

# 3. Después del reinicio que te pedirá (otra vez en la Terminal como administrador)
cd C:\pc-optimization
claude --continue
```

## Qué hay aquí

| Documento | Para qué |
|---|---|
| [`PLAN.md`](PLAN.md) | **Empieza aquí.** Qué hace Claude, en qué orden, con qué agentes y con qué garantías |
| [`docs/FLUJO.md`](docs/FLUJO.md) | Diagramas BPMN del proceso (visión general y detalle por fase) |
| [`CLAUDE.md`](CLAUDE.md) | Reglas de oro que cumplen la sesión principal y todos los agentes |
| [`.claude/skills/optimizar-pc/`](.claude/skills/optimizar-pc/SKILL.md) | El orquestador (`/optimizar-pc`) y los criterios de análisis |
| [`.claude/agents/`](.claude/agents/) | Los 5 subagentes: analista-rendimiento, auditor-procesos, planificador, ejecutor y verificador |
| [`scripts/`](scripts/) | PowerShell: diagnóstico (solo lectura), respaldo, aplicar, revertir y comparar |
| [`config/catalogo.json`](config/catalogo.json) | Optimizaciones permitidas, con riesgo y condiciones, y la lista de elementos protegidos |

## Garantías

1. Diagnóstico de **solo lectura** antes de proponer nada.
2. Un plan legible que **tú apruebas** (puedes quitar acciones o cancelar).
3. **Punto de restauración** y copia del estado previo antes de aplicar.
4. Cada cambio queda registrado y se puede **revertir** uno por uno o todos juntos.
5. Defender, el firewall, Windows Update y otros elementos críticos están **bloqueados** en el propio script.
6. Medición **antes y después** para ver qué sirvió de verdad.

Los scripts se validaron con el analizador de PowerShell y se probó su lógica, pero todavía no se ejecutaron en un Windows real. Para la primera ejecución conviene elegir el perfil **Conservador**. Más detalles en la sección de limitaciones de `PLAN.md`.
