<#
.SYNOPSIS
    Revierte cambios registrados en cambios.json (todos o los de ciertas acciones).

.DESCRIPTION
    Recorre el registro en orden inverso y devuelve cada elemento a su estado
    previo. Solo revierte pasos con resultado 'ok' y reversibles (servicio,
    inicio, tarea, registro, energia). Las limpiezas y apps desinstaladas no se
    pueden revertir con este script: para eso existe el punto de restauracion.

.PARAMETER Registro
    Ruta a cambios.json.

.PARAMETER Ids
    Ids de accion a revertir (separados por coma). Sin este parametro se revierte todo.

.PARAMETER Simular
    Muestra que se revertiria sin tocar nada.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/revertir.ps1 -Registro reportes/20260101-120000/cambios.json -Ids juego-hags
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/revertir.ps1 -Registro reportes/20260101-120000/cambios.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Registro,
    [string[]]$Ids,
    [switch]$Simular
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
Assert-Admin

$rutaRegistro = (Resolve-Path $Registro).Path
$log = Read-Json $rutaRegistro
# Desde "powershell -File" la lista llega como un solo texto "a,b".
$Ids = @($Ids | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$candidatos = @($log.pasos | Where-Object {
    $_.resultado -eq 'ok' -and $_.reversible -and -not $_.revertido -and ($Ids.Count -eq 0 -or $Ids -contains $_.accionId)
} | Sort-Object secuencia -Descending)

if ($candidatos.Count -eq 0) {
    Write-Host 'No hay cambios reversibles pendientes para esos criterios.'
    exit 0
}

function Undo-Servicio($e) {
    $modo = [string]$e.antes.modo
    if (@('auto', 'delayed-auto', 'demand', 'disabled') -notcontains $modo) { throw "Modo previo no restaurable: $modo" }
    $r = Invoke-Nativo 'sc.exe' @('config', $e.paso.nombre, 'start=', $modo)
    if ($r.codigo -ne 0) { throw "sc.exe config fallo ($($r.codigo)): $($r.salida)" }
    $msg = "inicio restaurado a $modo"
    if ($e.antes.estado -eq 'Running') {
        try { Start-Service -Name $e.paso.nombre -ErrorAction Stop; $msg += '; iniciado' }
        catch { $msg += "; no se pudo iniciar: $($_.Exception.Message)" }
    }
    return $msg
}

function Undo-Inicio($e) {
    $def = $script:UbicacionesInicio[[string]$e.paso.ubicacion]
    if ($e.antes.existe) {
        $bytes = [Convert]::FromBase64String([string]$e.antes.bytesBase64)
        New-ItemProperty -Path $def.Aprobado -Name $e.paso.nombre -PropertyType Binary -Value $bytes -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $def.Aprobado -Name $e.paso.nombre -ErrorAction SilentlyContinue
    }
    return 'entrada de inicio restaurada'
}

function Undo-Tarea($e) {
    if ($e.antes.estado -ne 'Disabled') {
        Enable-ScheduledTask -TaskPath $e.paso.ruta -TaskName $e.paso.nombre -ErrorAction Stop | Out-Null
        return 'tarea habilitada de nuevo'
    }
    return 'la tarea ya estaba deshabilitada antes: sin cambios'
}

function Undo-Registro($e) {
    $ruta = [string]$e.paso.ruta
    if ($e.antes.existe) {
        New-ItemProperty -Path $ruta -Name $e.paso.nombre -PropertyType $e.antes.tipo -Value $e.antes.datos -Force | Out-Null
        return 'valor previo restaurado'
    }
    Remove-ItemProperty -Path $ruta -Name $e.paso.nombre -ErrorAction SilentlyContinue
    # Si la clave la creo aplicar.ps1 y quedo vacia, se elimina (ej. directivas del navegador).
    if (-not $e.antes.claveExiste -and (Test-Path $ruta)) {
        $clave = Get-Item $ruta
        if ($clave.ValueCount -eq 0 -and $clave.SubKeyCount -eq 0) { Remove-Item -Path $ruta -Force }
    }
    return 'valor eliminado (no existia antes)'
}

function Undo-Energia($e) {
    $guid = [string]$e.antes.planActivo
    if (-not $guid) { throw 'No hay plan previo registrado' }
    $r = Invoke-Nativo 'powercfg.exe' @('/setactive', $guid)
    if ($r.codigo -ne 0) { throw "powercfg /setactive fallo: $($r.salida)" }
    return "plan previo activo $guid"
}

$ok = 0; $fallos = 0
foreach ($e in $candidatos) {
    $texto = '{0} #{1} {2}' -f $e.accionId, $e.indice, $e.objetivo
    if ($Simular) { Write-Host "   [SIMULADO] se revertiria: $texto"; continue }
    try {
        $msg = switch ($e.tipo) {
            'servicio' { Undo-Servicio $e }
            'inicio' { Undo-Inicio $e }
            'tarea' { Undo-Tarea $e }
            'registro' { Undo-Registro $e }
            'energia' { Undo-Energia $e }
            default { throw "Tipo no reversible: $($e.tipo)" }
        }
        $e.revertido = $true
        if ($e.PSObject.Properties['fechaReversion']) { $e.fechaReversion = (Get-Date).ToString('s') }
        else { $e | Add-Member -NotePropertyName fechaReversion -NotePropertyValue (Get-Date).ToString('s') }
        Write-Host "   [REVERTIDO] $texto :: $msg" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "   [ERROR] $texto :: $($_.Exception.Message)" -ForegroundColor Red
        $fallos++
    }
    Write-Json $log $rutaRegistro
}

Write-Host ''
Write-Host ("Revertidos: $ok | Errores: $fallos")
if (-not $Simular) {
    Write-Host 'Reinicia el equipo para que todos los cambios revertidos tengan efecto.' -ForegroundColor Yellow
    if ($fallos -gt 0) {
        Write-Host 'Si algo sigue mal: Win+R > rstrui > elegir el punto "Antes de optimizar el PC (Claude Code)".' -ForegroundColor Yellow
    }
}
if ($fallos -gt 0) { exit 1 }
