# Funciones compartidas por los scripts de optimizacion.
# Se carga con:  . "$PSScriptRoot\comun.ps1"
# Compatible con Windows PowerShell 5.1 y PowerShell 7+.
# Archivo en ASCII a proposito: PowerShell 5.1 lee los .ps1 sin BOM como ANSI.

# Salida en UTF-8 para que Claude Code lea bien el texto de la consola.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:RaizRepo = Split-Path -Parent $PSScriptRoot
$script:RutaCatalogo = Join-Path $script:RaizRepo 'config\catalogo.json'

function Test-EsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-EsAdmin)) {
        Write-Host 'ERROR: este script necesita permisos de administrador.' -ForegroundColor Red
        Write-Host 'Cierra Claude Code, abre "Terminal (Administrador)" y vuelve a ejecutar "claude" en la carpeta del repositorio.'
        exit 2
    }
}

# Ejecuta un programa externo (reg.exe, sc.exe, powercfg...) sin que la salida
# de error se convierta en excepcion (comportamiento de PowerShell 5.1 con
# $ErrorActionPreference = 'Stop'). Devuelve @{ codigo; salida }.
function Invoke-Nativo([string]$Exe, [string[]]$Argumentos) {
    $ErrorActionPreference = 'Continue'
    $salida = & $Exe @Argumentos 2>&1 | ForEach-Object { [string]$_ }
    return [ordered]@{ codigo = $LASTEXITCODE; salida = (@($salida) -join [Environment]::NewLine) }
}

# Get-AppxPackage falla en algunas versiones de PowerShell 7: se reintenta
# cargando el modulo Appx en modo compatibilidad.
function Get-AppxPaquetes([string]$Nombre = '*') {
    try { return @(Get-AppxPackage -Name $Nombre -ErrorAction Stop) }
    catch {
        Import-Module Appx -UseWindowsPowerShell -ErrorAction Stop 3>$null
        return @(Get-AppxPackage -Name $Nombre -ErrorAction Stop)
    }
}

function Write-Paso([string]$Texto) {
    Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Texto) -ForegroundColor Cyan
}

function Write-Aviso([string]$Texto) {
    Write-Host ('AVISO: {0}' -f $Texto) -ForegroundColor Yellow
}

function New-CarpetaReporte([string]$Ruta) {
    if (-not $Ruta) {
        $Ruta = Join-Path $script:RaizRepo ('reportes\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }
    if (-not (Test-Path $Ruta)) { New-Item -ItemType Directory -Path $Ruta -Force | Out-Null }
    return (Resolve-Path $Ruta).Path
}

function Write-Json($Objeto, [string]$Ruta) {
    $json = $Objeto | ConvertTo-Json -Depth 10
    $utf8SinBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Ruta, $json, $utf8SinBom)
}

function Read-Json([string]$Ruta) {
    if (-not (Test-Path $Ruta)) { throw "No existe el archivo: $Ruta" }
    return (Get-Content -Path $Ruta -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-Catalogo { return (Read-Json $script:RutaCatalogo) }

# Lee un valor del registro sin lanzar error si no existe.
# Devuelve @{ existe; datos; tipo; claveExiste }.
function Get-RegValor([string]$Ruta, [string]$Nombre) {
    $r = [ordered]@{ existe = $false; datos = $null; tipo = $null; claveExiste = $false }
    if (-not (Test-Path $Ruta)) { return $r }
    $r.claveExiste = $true
    $clave = Get-Item -Path $Ruta
    if ($clave.GetValueNames() -contains $Nombre) {
        $r.existe = $true
        $r.datos = $clave.GetValue($Nombre, $null, 'DoNotExpandEnvironmentNames')
        $r.tipo = $clave.GetValueKind($Nombre).ToString()
    }
    return $r
}

function Get-RegDato([string]$Ruta, [string]$Nombre) {
    return (Get-RegValor $Ruta $Nombre).datos
}

# Ubicaciones de programas de inicio y su clave StartupApproved
# (la misma que usa el Administrador de tareas para habilitar/deshabilitar).
$script:UbicacionesInicio = [ordered]@{
    'HKCU-Run'     = @{ Tipo = 'registro'; Ruta = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Aprobado = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    'HKLM-Run'     = @{ Tipo = 'registro'; Ruta = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprobado = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' }
    'HKLM-Run32'   = @{ Tipo = 'registro'; Ruta = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprobado = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    'HKCU-Carpeta' = @{ Tipo = 'carpeta';  Ruta = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup');      Aprobado = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    'HKLM-Carpeta' = @{ Tipo = 'carpeta';  Ruta = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp'); Aprobado = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
}

# StartupApproved: primer byte par (02/06) = habilitado, impar (03) = deshabilitado.
# Si el valor no existe, la entrada esta habilitada.
function Test-InicioHabilitado([string]$Ubicacion, [string]$Nombre) {
    $v = Get-RegValor $script:UbicacionesInicio[$Ubicacion].Aprobado $Nombre
    if (-not $v.existe -or $null -eq $v.datos -or $v.datos.Length -lt 1) { return $true }
    return (($v.datos[0] -band 1) -eq 0)
}

function Get-BytesInicioDeshabilitado {
    $bytes = New-Object byte[] 12
    $bytes[0] = 3
    $ft = [BitConverter]::GetBytes([DateTime]::Now.ToFileTimeUtc())
    [Array]::Copy($ft, 0, $bytes, 4, 8)
    return ,$bytes
}

# Extrae la ruta del ejecutable de una linea de comando.
function Get-RutaEjecutable([string]$Comando) {
    if (-not $Comando) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($c.StartsWith('"')) {
        $fin = $c.IndexOf('"', 1)
        if ($fin -gt 1) { return $c.Substring(1, $fin - 1) }
    }
    $m = [regex]::Match($c, '^(.+?\.(exe|com|bat|cmd|vbs|js|ps1|scr|dll))(\s|,|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ($c -split '\s+')[0]
}

# Estado de firma digital de un archivo: @{ estado; firmante }.
function Get-Firmante([string]$Ruta) {
    $r = [ordered]@{ estado = 'desconocido'; firmante = $null }
    if (-not $Ruta -or -not (Test-Path -LiteralPath $Ruta -PathType Leaf)) { $r.estado = 'no-encontrado'; return $r }
    try {
        $s = Get-AuthenticodeSignature -LiteralPath $Ruta -ErrorAction Stop
        $r.estado = $s.Status.ToString()
        if ($s.SignerCertificate) {
            $m = [regex]::Match($s.SignerCertificate.Subject, 'O=("[^"]+"|[^,]+)')
            if (-not $m.Success) { $m = [regex]::Match($s.SignerCertificate.Subject, 'CN=("[^"]+"|[^,]+)') }
            if ($m.Success) { $r.firmante = $m.Groups[1].Value.Trim('"') }
        }
    } catch { $r.estado = 'error' }
    return $r
}

# Planes de energia conocidos (GUID estandar de Windows).
$script:PlanesEnergia = @{
    'equilibrado'        = '381b4222-f694-41f0-9685-ff5bb260df2e'
    'alto-rendimiento'   = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    'maximo-rendimiento' = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
}

function Get-PlanEnergiaActivo {
    $txt = (Invoke-Nativo 'powercfg.exe' @('/getactivescheme')).salida
    $m = [regex]::Match($txt, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($m.Success) { return $m.Value.ToLower() }
    return $null
}

function Get-PlanesEnergia {
    $lista = @()
    foreach ($linea in ((Invoke-Nativo 'powercfg.exe' @('/list')).salida -split "`r?`n")) {
        $m = [regex]::Match($linea, '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s+\((.+?)\)(\s*\*)?')
        if ($m.Success) {
            $lista += [ordered]@{ guid = $m.Groups[1].Value.ToLower(); nombre = $m.Groups[2].Value; activo = $m.Groups[3].Success }
        }
    }
    return ,$lista
}

# Traduce Start/DelayedAutostart del registro a los modos de sc.exe.
function Get-ModoInicioServicio([string]$Nombre) {
    $ruta = "HKLM:\SYSTEM\CurrentControlSet\Services\$Nombre"
    $start = Get-RegDato $ruta 'Start'
    $delayed = Get-RegDato $ruta 'DelayedAutostart'
    switch ($start) {
        2 { if ($delayed -eq 1) { return 'delayed-auto' } else { return 'auto' } }
        3 { return 'demand' }
        4 { return 'disabled' }
        0 { return 'boot' }
        1 { return 'system' }
        default { return $null }
    }
}

$script:ModosServicio = @{
    'Automatic'        = 'auto'
    'AutomaticDelayed' = 'delayed-auto'
    'Manual'           = 'demand'
    'Disabled'         = 'disabled'
}

function Test-Coincide([string]$Texto, $Patrones) {
    foreach ($p in @($Patrones)) {
        if ($Texto -like $p) { return $true }
    }
    return $false
}

function Get-TamanoCarpetaMB([string]$Ruta) {
    if (-not (Test-Path -LiteralPath $Ruta)) { return 0 }
    $suma = (Get-ChildItem -LiteralPath $Ruta -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if (-not $suma) { return 0 }
    return [math]::Round($suma / 1MB, 1)
}
