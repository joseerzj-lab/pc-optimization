<#
.SYNOPSIS
    Aplica un plan de optimizacion APROBADO y registra el estado previo de cada
    cambio en cambios.json para poder revertirlo con revertir.ps1.

.PARAMETER Plan
    Ruta a plan.json (generado por el agente planificador).

.PARAMETER Simular
    No cambia nada: muestra que haria cada paso y el estado actual. No exige
    que el plan este aprobado. Escribe simulacion.json.

.PARAMETER Registro
    Ruta del registro de cambios. Por defecto: cambios.json junto al plan.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/aplicar.ps1 -Plan reportes/20260101-120000/plan.json -Simular
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/aplicar.ps1 -Plan reportes/20260101-120000/plan.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Plan,
    [switch]$Simular,
    [string]$Registro
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
Assert-Admin

$rutaPlan = (Resolve-Path $Plan).Path
$plan = Read-Json $rutaPlan
$catalogo = Get-Catalogo
$prot = $catalogo.protegidos

if (-not $Simular -and $plan.aprobado -ne $true) {
    Write-Host 'ERROR: el plan no esta aprobado ("aprobado": true). Muestra el plan al usuario y espera su aprobacion.' -ForegroundColor Red
    exit 3
}

$carpeta = Split-Path -Parent $rutaPlan
if ($Simular) { $Registro = Join-Path $carpeta 'simulacion.json' }
elseif (-not $Registro) { $Registro = Join-Path $carpeta 'cambios.json' }

$log = [ordered]@{ plan = $rutaPlan; simulacion = [bool]$Simular; pasos = @() }
if (-not $Simular -and (Test-Path $Registro)) {
    $previo = Read-Json $Registro
    $log.pasos = @($previo.pasos)
}

function Save-Log { Write-Json $log $Registro }

function Test-YaAplicado([string]$AccionId, [int]$Indice) {
    foreach ($p in @($log.pasos)) {
        if ($p.accionId -eq $AccionId -and $p.indice -eq $Indice -and $p.resultado -eq 'ok' -and -not $p.revertido) { return $true }
    }
    return $false
}

# Devuelve el motivo si el paso esta protegido, o $null.
function Get-MotivoProteccion($Paso) {
    switch ($Paso.tipo) {
        'servicio' { if ($prot.servicios -contains $Paso.nombre) { return "servicio protegido: $($Paso.nombre)" } }
        'tarea' {
            $completa = $Paso.ruta + $Paso.nombre
            foreach ($pre in $prot.tareasPrefijo) { if ($completa.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase)) { return "tarea protegida: $completa" } }
        }
        'registro' {
            if ($Paso.ruta -notmatch '^(HKCU|HKLM):\\') { return "ruta de registro no permitida: $($Paso.ruta)" }
            if (Test-Coincide $Paso.ruta $prot.registroPatrones) { return "clave de registro protegida: $($Paso.ruta)" }
        }
        'appx' { if (Test-Coincide $Paso.paquete $prot.appxPatrones) { return "paquete protegido: $($Paso.paquete)" } }
    }
    return $null
}

# ---------------------------------------------------------------- estado previo
function Get-EstadoPrevio($Paso) {
    switch ($Paso.tipo) {
        'servicio' {
            $s = Get-Service -Name $Paso.nombre -ErrorAction SilentlyContinue
            if (-not $s) { return $null }
            return [ordered]@{ modo = (Get-ModoInicioServicio $Paso.nombre); estado = [string]$s.Status }
        }
        'inicio' {
            $def = $script:UbicacionesInicio[$Paso.ubicacion]
            if (-not $def) { throw "Ubicacion de inicio desconocida: $($Paso.ubicacion)" }
            $v = Get-RegValor $def.Aprobado $Paso.nombre
            $bytes = $null
            if ($v.existe) { $bytes = [Convert]::ToBase64String([byte[]]$v.datos) }
            return [ordered]@{ existe = $v.existe; bytesBase64 = $bytes; habilitado = (Test-InicioHabilitado $Paso.ubicacion $Paso.nombre) }
        }
        'tarea' {
            $t = Get-ScheduledTask -TaskPath $Paso.ruta -TaskName $Paso.nombre -ErrorAction SilentlyContinue
            if (-not $t) { return $null }
            return [ordered]@{ estado = [string]$t.State }
        }
        'registro' {
            $v = Get-RegValor $Paso.ruta $Paso.nombre
            return [ordered]@{ claveExiste = $v.claveExiste; existe = $v.existe; datos = $v.datos; tipo = $v.tipo }
        }
        'energia' { return [ordered]@{ planActivo = (Get-PlanEnergiaActivo) } }
        'limpieza' { return [ordered]@{ } }
        'mantenimiento' { return [ordered]@{ } }
        'appx' {
            $a = Get-AppxPaquetes $Paso.paquete | Select-Object -First 1
            if (-not $a) { return $null }
            return [ordered]@{ paqueteCompleto = $a.PackageFullName }
        }
        'manual' { return [ordered]@{ } }
    }
    throw "Tipo de paso desconocido: $($Paso.tipo)"
}

function Get-Objetivo($Paso) {
    switch ($Paso.tipo) {
        'servicio' { return "$($Paso.nombre) -> $($Paso.inicio)" }
        'inicio' { return "$($Paso.ubicacion)\$($Paso.nombre) -> deshabilitado" }
        'tarea' { return "$($Paso.ruta)$($Paso.nombre) -> deshabilitada" }
        'registro' { return "$($Paso.ruta)\$($Paso.nombre) = $($Paso.valor)" }
        'energia' { return "plan $($Paso.plan)" }
        'limpieza' { return $Paso.objetivo }
        'mantenimiento' { return $Paso.objetivo }
        'appx' { return "quitar $($Paso.paquete)" }
        'manual' { return $Paso.instrucciones }
    }
    return ''
}

# ---------------------------------------------------------------- ejecucion por tipo
function Invoke-Servicio($Paso) {
    $modo = $script:ModosServicio[[string]$Paso.inicio]
    if (-not $modo) { throw "Modo de inicio no valido: $($Paso.inicio)" }
    $r = Invoke-Nativo 'sc.exe' @('config', $Paso.nombre, 'start=', $modo)
    if ($r.codigo -ne 0) { throw "sc.exe config fallo ($($r.codigo)): $($r.salida)" }
    $msg = "inicio = $modo"
    if ($Paso.detener) {
        try { Stop-Service -Name $Paso.nombre -Force -ErrorAction Stop; $msg += '; detenido' }
        catch { $msg += "; no se pudo detener ahora (se aplicara al reiniciar): $($_.Exception.Message)" }
    }
    return $msg
}

function Invoke-Inicio($Paso) {
    $def = $script:UbicacionesInicio[$Paso.ubicacion]
    if (-not (Test-Path $def.Aprobado)) { New-Item -Path $def.Aprobado -Force | Out-Null }
    New-ItemProperty -Path $def.Aprobado -Name $Paso.nombre -PropertyType Binary -Value (Get-BytesInicioDeshabilitado) -Force | Out-Null
    return 'deshabilitado en StartupApproved (igual que el Administrador de tareas)'
}

function Invoke-Tarea($Paso) {
    Disable-ScheduledTask -TaskPath $Paso.ruta -TaskName $Paso.nombre -ErrorAction Stop | Out-Null
    return 'tarea deshabilitada'
}

function Invoke-Registro($Paso) {
    if (-not (Test-Path $Paso.ruta)) { New-Item -Path $Paso.ruta -Force | Out-Null }
    New-ItemProperty -Path $Paso.ruta -Name $Paso.nombre -PropertyType $Paso.tipoDato -Value $Paso.valor -Force | Out-Null
    return 'valor escrito'
}

function Invoke-Energia($Paso) {
    $guid = [string]$Paso.plan
    if ($script:PlanesEnergia.ContainsKey($guid)) { $guid = $script:PlanesEnergia[$guid] }
    $existe = @(Get-PlanesEnergia | Where-Object { $_.guid -eq $guid }).Count -gt 0
    $msg = ''
    if (-not $existe) {
        $r = Invoke-Nativo 'powercfg.exe' @('/duplicatescheme', $guid)
        $m = [regex]::Match($r.salida, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
        if ($r.codigo -ne 0 -or -not $m.Success) { throw "No se pudo crear el plan $($Paso.plan): $($r.salida)" }
        $guid = $m.Value.ToLower()
        $msg = "plan creado ($guid); "
    }
    $r = Invoke-Nativo 'powercfg.exe' @('/setactive', $guid)
    if ($r.codigo -ne 0) { throw "powercfg /setactive fallo: $($r.salida)" }
    return $msg + "plan activo $guid"
}

function Remove-Contenido([string]$Ruta) {
    if (-not (Test-Path -LiteralPath $Ruta)) { return 0 }
    $antes = Get-TamanoCarpetaMB $Ruta
    Get-ChildItem -LiteralPath $Ruta -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    return [math]::Round($antes - (Get-TamanoCarpetaMB $Ruta), 1)
}

function Invoke-Limpieza($Paso) {
    switch ($Paso.objetivo) {
        'temp-usuario' { return ('liberados {0} MB' -f (Remove-Contenido $env:TEMP)) }
        'temp-windows' { return ('liberados {0} MB' -f (Remove-Contenido (Join-Path $env:WINDIR 'Temp'))) }
        'cache-entrega-optimizacion' { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; return 'cache vaciada' }
        'papelera' { Clear-RecycleBin -Force -ErrorAction Stop; return 'papelera vaciada' }
    }
    throw "Objetivo de limpieza desconocido: $($Paso.objetivo)"
}

function Invoke-Mantenimiento($Paso) {
    switch ($Paso.objetivo) {
        'optimizar-unidad' {
            $letra = $env:SystemDrive.TrimEnd(':')
            $num = (Get-Partition -DriveLetter $letra).DiskNumber
            $tipo = [string](Get-PhysicalDisk | Where-Object { [string]$_.DeviceId -eq [string]$num } | Select-Object -First 1).MediaType
            if ($tipo -eq 'SSD') { Optimize-Volume -DriveLetter $letra -ReTrim -ErrorAction Stop; return 'TRIM ejecutado (SSD)' }
            if ($tipo -eq 'HDD') { Optimize-Volume -DriveLetter $letra -Defrag -ErrorAction Stop; return 'desfragmentacion ejecutada (HDD)' }
            throw "Tipo de disco '$tipo' no reconocido: no se optimiza por seguridad"
        }
        'sfc' {
            $r = Invoke-Nativo 'sfc.exe' @('/scannow')
            if ($r.codigo -ne 0) { throw "sfc termino con codigo $($r.codigo)" }
            return 'sfc /scannow completado (detalle en C:\Windows\Logs\CBS\CBS.log)'
        }
        'dism-reparar' {
            $r = Invoke-Nativo 'DISM.exe' @('/Online', '/Cleanup-Image', '/RestoreHealth')
            if ($r.codigo -ne 0) { throw "DISM RestoreHealth termino con codigo $($r.codigo)" }
            return 'DISM RestoreHealth completado'
        }
        'dism-limpiar-componentes' {
            $r = Invoke-Nativo 'DISM.exe' @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
            if ($r.codigo -ne 0) { throw "DISM StartComponentCleanup termino con codigo $($r.codigo)" }
            return 'DISM StartComponentCleanup completado'
        }
        'escaneo-defender-rapido' {
            Start-MpScan -ScanType QuickScan -ErrorAction Stop
            $amenazas = @(Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { $_.IsActive })
            return ('analisis rapido completado; amenazas activas: {0}' -f $amenazas.Count)
        }
    }
    throw "Objetivo de mantenimiento desconocido: $($Paso.objetivo)"
}

function Invoke-Appx($Paso) {
    foreach ($a in (Get-AppxPaquetes $Paso.paquete)) { Remove-AppxPackage -Package $a.PackageFullName -ErrorAction Stop }
    return 'app desinstalada (se puede reinstalar desde Microsoft Store)'
}

$reversiblesPorTipo = @('servicio', 'inicio', 'tarea', 'registro', 'energia')

# ---------------------------------------------------------------- bucle principal
$cuenta = @{ ok = 0; error = 0; omitido = 0; bloqueado = 0; manual = 0; simulado = 0 }
$reinicio = $false
$secuencia = @($log.pasos).Count

foreach ($accion in @($plan.acciones)) {
    if ($accion.PSObject.Properties['incluir'] -and $accion.incluir -eq $false) { continue }
    Write-Paso ("Accion: {0} - {1}" -f $accion.id, $accion.titulo)
    $i = 0
    foreach ($paso in @($accion.pasos)) {
        $i++
        $secuencia++
        $entrada = [ordered]@{
            secuencia = $secuencia; accionId = $accion.id; indice = $i; tipo = $paso.tipo
            objetivo = (Get-Objetivo $paso); paso = $paso; antes = $null
            resultado = $null; mensaje = $null; reversible = ($reversiblesPorTipo -contains $paso.tipo)
            revertido = $false; fecha = (Get-Date).ToString('s')
        }
        try {
            $motivo = Get-MotivoProteccion $paso
            if ($motivo) {
                $entrada.resultado = 'bloqueado'; $entrada.mensaje = $motivo
            } elseif (-not $Simular -and (Test-YaAplicado $accion.id $i)) {
                $entrada.resultado = 'omitido'; $entrada.mensaje = 'ya aplicado en una ejecucion anterior'
            } elseif ($paso.tipo -eq 'manual') {
                $entrada.resultado = 'manual'; $entrada.mensaje = 'paso manual: lo guia Claude con el usuario'
            } else {
                $entrada.antes = Get-EstadoPrevio $paso
                if ($null -eq $entrada.antes) {
                    $entrada.resultado = 'omitido'; $entrada.mensaje = 'el elemento no existe en este equipo'
                } elseif ($Simular) {
                    $entrada.resultado = 'simulado'; $entrada.mensaje = 'se aplicaria: ' + $entrada.objetivo
                } else {
                    switch ($paso.tipo) {
                        'servicio' { $entrada.mensaje = Invoke-Servicio $paso }
                        'inicio' { $entrada.mensaje = Invoke-Inicio $paso }
                        'tarea' { $entrada.mensaje = Invoke-Tarea $paso }
                        'registro' { $entrada.mensaje = Invoke-Registro $paso }
                        'energia' { $entrada.mensaje = Invoke-Energia $paso }
                        'limpieza' { $entrada.mensaje = Invoke-Limpieza $paso }
                        'mantenimiento' { $entrada.mensaje = Invoke-Mantenimiento $paso }
                        'appx' { $entrada.mensaje = Invoke-Appx $paso }
                    }
                    $entrada.resultado = 'ok'
                    if ($accion.PSObject.Properties['requiereReinicio'] -and $accion.requiereReinicio) { $reinicio = $true }
                }
            }
        } catch {
            $entrada.resultado = 'error'; $entrada.mensaje = $_.Exception.Message
        }
        $cuenta[$entrada.resultado]++
        $color = @{ ok = 'Green'; error = 'Red'; bloqueado = 'Magenta'; omitido = 'DarkGray'; manual = 'Yellow'; simulado = 'Gray' }[$entrada.resultado]
        Write-Host ('   [{0}] {1} :: {2}' -f $entrada.resultado.ToUpper(), $entrada.objetivo, $entrada.mensaje) -ForegroundColor $color
        $log.pasos += $entrada
        Save-Log
    }
}

Write-Host ''
Write-Host ('Resultado: ok={0} error={1} omitido={2} bloqueado={3} manual={4} simulado={5}' -f $cuenta.ok, $cuenta.error, $cuenta.omitido, $cuenta.bloqueado, $cuenta.manual, $cuenta.simulado)
if ($reinicio) { Write-Host 'Algunos cambios requieren REINICIAR el equipo para tener efecto.' -ForegroundColor Yellow }
Write-Host "REGISTRO_JSON=$Registro"
if ($cuenta.error -gt 0) { exit 1 }
