<#
.SYNOPSIS
    Crea el respaldo previo a cualquier cambio: punto de restauracion de Windows
    + instantanea de servicios, plan de energia y claves de registro relevantes.

.PARAMETER Salida
    Carpeta del reporte de esta sesion (la misma del diagnostico).

.PARAMETER HabilitarProteccion
    Activa la Proteccion del sistema en la unidad del sistema si estaba apagada.

.PARAMETER ForzarFrecuencia
    Windows solo permite un punto de restauracion cada 24 h. Con este switch se
    levanta ese limite temporalmente y se deja como estaba al terminar.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/respaldo.ps1 -Salida reportes/20260101-120000
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Salida,
    [switch]$HabilitarProteccion,
    [switch]$ForzarFrecuencia,
    [string]$Descripcion = 'Antes de optimizar el PC (Claude Code)'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
Assert-Admin

$carpeta = New-CarpetaReporte $Salida
$dirRespaldo = Join-Path $carpeta 'respaldo'
New-Item -ItemType Directory -Path $dirRespaldo -Force | Out-Null

$resultado = [ordered]@{
    fecha = (Get-Date).ToString('s')
    puntoRestauracion = [ordered]@{ estado = 'fallo'; fecha = $null; secuencia = $null; mensaje = $null }
    archivos = @()
}

# ---------------------------------------------------------------- punto de restauracion
function Get-PuntosRestauracion {
    return @(Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction SilentlyContinue)
}

# CreationTime llega como texto WMI (yyyyMMddHHmmss.ffffff+zzz) o como fecha.
function Get-FechaPunto($Punto) {
    $v = $Punto.CreationTime
    if ($v -is [datetime]) { return $v }
    try { return [datetime]::ParseExact(([string]$v).Substring(0, 14), 'yyyyMMddHHmmss', $null) } catch { return $null }
}

Write-Paso 'Creando punto de restauracion (puede tardar 1-2 minutos)...'
$antes = Get-PuntosRestauracion
$secuenciasAntes = @($antes | ForEach-Object { $_.SequenceNumber })
$claveSR = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$frecuenciaPrevia = $null

try {
    if ($HabilitarProteccion) {
        Write-Paso "Activando Proteccion del sistema en $env:SystemDrive"
        $r = Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName Enable -Arguments @{ Drive = "$env:SystemDrive\" }
        if ($r.ReturnValue -ne 0) { Write-Aviso "Enable devolvio codigo $($r.ReturnValue)" }
    }
    if ($ForzarFrecuencia) {
        $frecuenciaPrevia = Get-RegValor $claveSR 'SystemRestorePointCreationFrequency'
        New-ItemProperty -Path $claveSR -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value 0 -Force | Out-Null
    }
    $r = Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments @{
        Description      = $Descripcion
        RestorePointType = [uint32]12   # MODIFY_SETTINGS
        EventType        = [uint32]100  # BEGIN_SYSTEM_CHANGE
    }
    $resultado.puntoRestauracion.mensaje = "CreateRestorePoint devolvio $($r.ReturnValue)"
} catch {
    $resultado.puntoRestauracion.mensaje = $_.Exception.Message
} finally {
    if ($ForzarFrecuencia -and $null -ne $frecuenciaPrevia) {
        if ($frecuenciaPrevia.existe) {
            New-ItemProperty -Path $claveSR -Name 'SystemRestorePointCreationFrequency' -PropertyType DWord -Value $frecuenciaPrevia.datos -Force | Out-Null
        } else {
            Remove-ItemProperty -Path $claveSR -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
        }
    }
}

$despues = Get-PuntosRestauracion
$nuevo = $despues | Where-Object { $secuenciasAntes -notcontains $_.SequenceNumber } | Sort-Object SequenceNumber -Descending | Select-Object -First 1
if ($nuevo) {
    $resultado.puntoRestauracion.estado = 'creado'
    $resultado.puntoRestauracion.secuencia = $nuevo.SequenceNumber
    $f = Get-FechaPunto $nuevo
    if ($f) { $resultado.puntoRestauracion.fecha = $f.ToString('s') }
} else {
    $ultimo = $despues | Sort-Object SequenceNumber -Descending | Select-Object -First 1
    $fUltimo = $null
    if ($ultimo) { $fUltimo = Get-FechaPunto $ultimo }
    if ($fUltimo -and ((Get-Date) - $fUltimo).TotalHours -lt 24) {
        # Hay uno de las ultimas 24 h. Solo sirve si se creo ANTES de cualquier cambio.
        $resultado.puntoRestauracion.estado = 'reciente'
        $resultado.puntoRestauracion.secuencia = $ultimo.SequenceNumber
        $resultado.puntoRestauracion.fecha = $fUltimo.ToString('s')
        $resultado.puntoRestauracion.mensaje = 'No se creo uno nuevo: existe uno de las ultimas 24 h. Reintentar con -ForzarFrecuencia si ese punto no es de hoy antes de los cambios.'
    } elseif (-not $resultado.puntoRestauracion.mensaje -or $resultado.puntoRestauracion.mensaje -like '*devolvio 0') {
        $resultado.puntoRestauracion.mensaje = 'No se creo el punto. Probable causa: Proteccion del sistema desactivada. Reintentar con -HabilitarProteccion -ForzarFrecuencia.'
    }
}

# ---------------------------------------------------------------- instantanea de servicios
Write-Paso 'Guardando estado de todos los servicios...'
$servicios = @(Get-CimInstance Win32_Service | ForEach-Object {
    [ordered]@{ nombre = $_.Name; modo = (Get-ModoInicioServicio $_.Name); estado = $_.State }
})
$rutaServicios = Join-Path $dirRespaldo 'servicios.json'
Write-Json $servicios $rutaServicios
$resultado.archivos += $rutaServicios

# ---------------------------------------------------------------- plan de energia
$rutaEnergia = Join-Path $dirRespaldo 'energia.json'
Write-Json ([ordered]@{ activo = Get-PlanEnergiaActivo; planes = Get-PlanesEnergia }) $rutaEnergia
$resultado.archivos += $rutaEnergia

# ---------------------------------------------------------------- claves de registro
Write-Paso 'Exportando claves de registro que el plan puede tocar...'
$claves = [ordered]@{
    'inicio-hkcu-run'        = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
    'inicio-hklm-run'        = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    'inicio-hklm-run32'      = 'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    'inicio-hkcu-aprobado'   = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    'inicio-hklm-aprobado'   = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    'juego-gamebar'          = 'HKCU\Software\Microsoft\GameBar'
    'juego-gameconfigstore'  = 'HKCU\System\GameConfigStore'
    'juego-gamedvr'          = 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    'grafica-drivers'        = 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    'visual-efectos'         = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    'visual-personalizar'    = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    'apps-segundo-plano'     = 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'
    'politicas-edge'         = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'
    'politicas-chrome'       = 'HKLM\SOFTWARE\Policies\Google\Chrome'
}
foreach ($nombre in $claves.Keys) {
    $archivo = Join-Path $dirRespaldo "$nombre.reg"
    $r = Invoke-Nativo 'reg.exe' @('export', $claves[$nombre], $archivo, '/y')
    if ($r.codigo -eq 0) { $resultado.archivos += $archivo }
}

$rutaResultado = Join-Path $carpeta 'respaldo.json'
Write-Json $resultado $rutaResultado

Write-Host ''
Write-Host ('Punto de restauracion: {0} {1}' -f $resultado.puntoRestauracion.estado, $resultado.puntoRestauracion.fecha)
if ($resultado.puntoRestauracion.mensaje) { Write-Host ('Detalle: {0}' -f $resultado.puntoRestauracion.mensaje) }
Write-Host ('Archivos de respaldo: {0}' -f @($resultado.archivos).Count)
Write-Host "RESPALDO_ESTADO=$($resultado.puntoRestauracion.estado)"
Write-Host "RESPALDO_JSON=$rutaResultado"
if ($resultado.puntoRestauracion.estado -eq 'fallo') { exit 1 }
