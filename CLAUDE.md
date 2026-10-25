# Optimización de PC con Claude Code

Este repositorio contiene un flujo para que Claude Code optimice un PC con **Windows 10/11** para **juegos y navegación**, revisando procesos ocultos o innecesarios, de forma segura y reversible.

- Punto de entrada: la skill **`/optimizar-pc`** (`.claude/skills/optimizar-pc/SKILL.md`).
- Plan completo para humanos: `PLAN.md`. Diagramas del proceso: `docs/FLUJO.md`.
- Agentes: `.claude/agents/` (analista-rendimiento, auditor-procesos, planificador, ejecutor, verificador).

## Reglas de oro (aplican a la sesión principal y a todos los subagentes)

1. **Nada se modifica sin un plan aprobado** de forma explícita por el usuario en esta sesión (`"aprobado": true` en `plan.json`, puesto solo tras su "sí").
2. **Respaldo antes de cambiar**: punto de restauración con `scripts/respaldo.ps1`. Si no se puede crear, solo se aplican acciones reversibles y con consentimiento expreso.
3. **Los cambios al sistema solo se hacen con los scripts** `respaldo.ps1`, `aplicar.ps1` y `revertir.ps1`, y solo los ejecuta el agente `ejecutor`. Prohibido modificar el sistema con comandos sueltos (`Set-ItemProperty`, `reg add`, `sc.exe config`, `Stop-Process`, `Remove-Item` fuera de `reportes/`, `bcdedit`, `netsh`, etc.).
4. **Nunca** desactivar Microsoft Defender o el antivirus activo, el firewall, Windows Update, el Control de cuentas de usuario, la Protección del sistema ni el archivo de paginación. Nunca tocar lo listado en `config/catalogo.json` → `protegidos`.
5. **No cerrar procesos ni desinstalar nada** sin confirmación del usuario, elemento por elemento.
6. **No descargar ni ejecutar herramientas o scripts de internet** ("debloaters", optimizadores, limpiadores de registro, ISOs modificadas).
7. **Honestidad**: no prometer FPS ni porcentajes. Distinguir siempre el *dato medido* (citar el valor del JSON) de la *estimación*. Si un paso falla, reportarlo tal cual.
8. **Privacidad**: `reportes/` contiene datos del equipo y está en `.gitignore`. No subirlo a GitHub.

## Cómo ejecutar los scripts

Claude Code debe haberse abierto desde una terminal **como administrador**, dentro de la carpeta del repositorio.

- Con la herramienta PowerShell: `& ./scripts/diagnostico.ps1 -Salida reportes/<carpeta>`
- Con la herramienta Bash (Git Bash): `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/diagnostico.ps1 -Salida reportes/<carpeta>`

Los scripts funcionan en Windows PowerShell 5.1 y en PowerShell 7. El diagnóstico tarda unos minutos: usar un timeout de 600000 ms. Si el plan incluye mantenimiento largo (DISM, SFC, análisis de Defender), ejecutar `aplicar.ps1` en segundo plano y esperar la notificación de que terminó.

Cada script imprime al final líneas `CLAVE=valor` (`DIAGNOSTICO_JSON=`, `RESPALDO_ESTADO=`, `REGISTRO_JSON=`, `COMPARACION_MD=`) para encadenar pasos sin adivinar rutas.

## Mapa del repositorio

| Ruta | Contenido |
|---|---|
| `scripts/diagnostico.ps1` | Diagnóstico de solo lectura → `diagnostico-antes.json` / `diagnostico-despues.json` |
| `scripts/respaldo.ps1` | Punto de restauración + instantánea de servicios, energía y registro |
| `scripts/aplicar.ps1` | Aplica un plan aprobado y guarda el estado previo en `cambios.json` (`-Simular` para probar) |
| `scripts/revertir.ps1` | Revierte todo o por id de acción usando `cambios.json` |
| `scripts/comparar.ps1` | Tabla antes/después → `comparacion.md` |
| `config/catalogo.json` | Acciones permitidas, riesgos, condiciones y lista de elementos protegidos |
| `plantillas/plan-ejemplo.json` | Formato de `plan.json` |
| `reportes/<fecha>/` | Todo lo generado en una sesión (local, ignorado por git) |
