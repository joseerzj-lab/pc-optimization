<#
.SYNOPSIS
    Compara dos diagnosticos (antes/despues) y genera comparacion.md.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/comparar.ps1 -Antes reportes/X/diagnostico-antes.json -Despues reportes/X/diagnostico-despues.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Antes,
    [Parameter(Mandatory = $true)][string]$Despues,
    [string]$Salida
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"

$a = Read-Json $Antes
$d = Read-Json $Despues
if (-not $Salida) { $Salida = Join-Path (Split-Path -Parent (Resolve-Path $Despues).Path) 'comparacion.md' }

function Get-Seguro($Objeto, [scriptblock]$Ruta) {
    try { $v = & $Ruta $Objeto; if ($null -eq $v) { return $null }; return [double]$v } catch { return $null }
}

# Nombre, como obtener el valor, unidad, si 'menor' o 'mayor' es mejor, y
# diferencia minima para no confundir ruido de medicion con un cambio real.
$metricas = @(
    @('Procesos en ejecucion',            { param($x) $x.metricas.procesos }, '', 'menor', 3),
    @('RAM en uso (reposo)',              { param($x) $x.metricas.ramUsoGB }, 'GB', 'menor', 0.1),
    @('RAM en uso (reposo)',              { param($x) $x.metricas.ramUsoPct }, '%', 'menor', 2),
    @('Memoria comprometida',             { param($x) $x.metricas.comprometidaGB }, 'GB', 'menor', 0.1),
    @('CPU en reposo',                    { param($x) $x.metricas.cpuPromedioPct }, '%', 'menor', 2),
    @('Disco ocupado en reposo',          { param($x) $x.metricas.discoOcupadoPct }, '%', 'menor', 3),
    @('Programas de inicio habilitados',  { param($x) $x.inicio.habilitadas }, '', 'menor', 0),
    @('Servicios automaticos activos',    { param($x) @($x.servicios.automaticosEnEjecucion).Count }, '', 'menor', 0),
    @('Ultimo arranque medido',           { param($x) $e = @($x.arranque.eventos); if ($e.Count -gt 0 -and $e[0].arranqueMs) { [double]$e[0].arranqueMs / 1000 } }, 's', 'menor', 2),
    @('Espacio libre en unidad sistema',  { param($x) ($x.discos.volumenes | Where-Object { $_.letra -eq $env:SystemDrive.TrimEnd(':') } | Select-Object -First 1).libreGB }, 'GB', 'mayor', 0.5),
    @('Temporales (usuario + Windows)',   { param($x) if ($x.temporales.PSObject.Properties['tempUsuarioMB']) { [double]$x.temporales.tempUsuarioMB + [double]$x.temporales.tempWindowsMB } }, 'MB', 'menor', 50),
    @('Ping a internet (promedio)',       { param($x) ($x.red.ping | Where-Object { $_.destino -eq '1.1.1.1' } | Select-Object -First 1).promMs }, 'ms', 'menor', 3),
    @('Jitter a internet',                { param($x) ($x.red.ping | Where-Object { $_.destino -eq '1.1.1.1' } | Select-Object -First 1).jitterMs }, 'ms', 'menor', 2)
)

$filas = @()
foreach ($m in $metricas) {
    $va = Get-Seguro $a $m[1]
    $vd = Get-Seguro $d $m[1]
    $veredicto = 'sin dato'
    $delta = ''
    if ($null -ne $va -and $null -ne $vd) {
        $dif = [math]::Round($vd - $va, 2)
        $delta = $(if ($dif -gt 0) { "+$dif" } else { "$dif" })
        $umbral = [math]::Max(0.05 * [math]::Abs($va), [double]$m[4])
        if ([math]::Abs($dif) -le $umbral) { $veredicto = 'igual' }
        elseif (($m[3] -eq 'menor' -and $dif -lt 0) -or ($m[3] -eq 'mayor' -and $dif -gt 0)) { $veredicto = 'mejor' }
        else { $veredicto = 'peor' }
    }
    $unidad = $(if ($m[2]) { " $($m[2])" } else { '' })
    $filas += [pscustomobject]@{
        Metrica = $m[0] + $(if ($m[2]) { " ($($m[2]))" } else { '' })
        Antes = $(if ($null -ne $va) { "$va$unidad" } else { '-' })
        Despues = $(if ($null -ne $vd) { "$vd$unidad" } else { '-' })
        Cambio = $delta
        Veredicto = $veredicto
    }
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Comparacion antes / despues')
$md.Add('')
$md.Add(('Antes: {0} | Despues: {1}' -f $a.meta.fecha, $d.meta.fecha))
$md.Add('')
$md.Add('| Metrica | Antes | Despues | Cambio | Veredicto |')
$md.Add('|---|---|---|---|---|')
foreach ($f in $filas) { $md.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $f.Metrica, $f.Antes, $f.Despues, $f.Cambio, $f.Veredicto)) }
$md.Add('')
$md.Add('Notas: cambios menores al 5 % (o al minimo de cada metrica) se consideran "igual": es ruido normal entre mediciones.')
$md.Add('Las metricas de reposo solo son comparables si ambas se tomaron en condiciones similares (recien reiniciado, 2-3 minutos de espera, sin juegos ni navegador abiertos).')
$md.Add('El tiempo de arranque lo registra Windows por su cuenta y puede no actualizarse en cada reinicio.')

$utf8SinBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($Salida, $md, $utf8SinBom)

$filas | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
Write-Host "COMPARACION_MD=$Salida"
