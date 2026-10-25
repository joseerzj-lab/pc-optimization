<#
.SYNOPSIS
    Diagnostico de SOLO LECTURA del equipo. No modifica nada.

.DESCRIPTION
    Recopila hardware, uso de recursos en reposo, procesos, programas de inicio,
    servicios, tareas programadas, aplicaciones, seguridad, ajustes de juego,
    red y estabilidad. Guarda todo en diagnostico-<etiqueta>.json y un
    resumen-<etiqueta>.txt dentro de la carpeta de reporte.

.PARAMETER Salida
    Carpeta del reporte. Por defecto: reportes\<fecha-hora>.

.PARAMETER Etiqueta
    'antes' (linea base) o 'despues' (verificacion).

.PARAMETER Rapido
    Omite los pasos lentos: firmas digitales, ping y tamano de carpetas.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/diagnostico.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/diagnostico.ps1 -Salida reportes/20260101-120000 -Etiqueta despues
#>
[CmdletBinding()]
param(
    [string]$Salida,
    [ValidateSet('antes', 'despues')][string]$Etiqueta = 'antes',
    [switch]$Rapido
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"

if (-not (Test-EsAdmin)) {
    Write-Aviso 'Sin permisos de administrador: algunas secciones quedaran incompletas (arranque, servicios, Defender).'
}

$carpeta = New-CarpetaReporte $Salida
$catalogo = Get-Catalogo
$errores = New-Object System.Collections.Generic.List[object]
$diag = [ordered]@{
    meta = [ordered]@{
        version   = 1
        etiqueta  = $Etiqueta
        fecha     = (Get-Date).ToString('s')
        admin     = (Test-EsAdmin)
        rapido    = [bool]$Rapido
        nota      = 'Solo lectura. Las metricas de reposo son validas si no habia juegos ni navegador abiertos.'
    }
}

function Invoke-Seccion([string]$Nombre, [scriptblock]$Bloque) {
    Write-Paso "Recopilando: $Nombre"
    try {
        $diag[$Nombre] = & $Bloque
    } catch {
        $errores.Add([ordered]@{ seccion = $Nombre; error = $_.Exception.Message })
        $diag[$Nombre] = $null
    }
}

function Test-RutaUsuario([string]$Ruta) {
    if (-not $Ruta) { return $false }
    $zonas = @($env:USERPROFILE, $env:TEMP, (Join-Path $env:SystemDrive 'Users\Public'))
    foreach ($z in $zonas) {
        if ($z -and $Ruta.StartsWith($z, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$patronesComandoOculto = @('*-enc *', '*-encodedcommand*', '*-w hidden*', '*-windowstyle hidden*', '*frombase64string*', '*downloadstring*', '*iex(*', '*invoke-expression*')

# ---------------------------------------------------------------- sistema
Invoke-Seccion 'sistema' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $enc = @(Get-CimInstance Win32_SystemEnclosure)
    $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $chasisPortatil = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    $esPortatil = ($bat.Count -gt 0) -or (@($enc | ForEach-Object { $_.ChassisTypes } | Where-Object { $chasisPortatil -contains $_ }).Count -gt 0)
    $nt = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [ordered]@{
        fabricante        = $cs.Manufacturer
        modelo            = $cs.Model
        so                = $os.Caption
        version           = Get-RegDato $nt 'DisplayVersion'
        build             = $os.BuildNumber
        arquitectura      = $os.OSArchitecture
        esPortatil        = $esPortatil
        enBateria         = ($bat.Count -gt 0 -and $bat[0].BatteryStatus -eq 1)
        ultimoArranque    = $os.LastBootUpTime.ToString('s')
        diasEncendido     = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 1)
        inicioRapido      = ((Get-RegDato 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 1)
        reinicioPendiente = ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                             (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'))
        powershell        = $PSVersionTable.PSVersion.ToString()
    }
}

# ---------------------------------------------------------------- hardware
Invoke-Seccion 'hardware' {
    $cs = Get-CimInstance Win32_ComputerSystem
    $arr = @(Get-CimInstance Win32_PhysicalMemoryArray)
    [ordered]@{
        cpu = @(Get-CimInstance Win32_Processor | ForEach-Object {
            [ordered]@{ nombre = $_.Name.Trim(); nucleos = $_.NumberOfCores; hilos = $_.NumberOfLogicalProcessors; mhzMax = $_.MaxClockSpeed }
        })
        ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        ramModulos = @(Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
            [ordered]@{ capacidadGB = [math]::Round($_.Capacity / 1GB, 1); mhz = $_.Speed; mhzConfigurada = $_.ConfiguredClockSpeed; ranura = $_.DeviceLocator }
        })
        ramRanurasTotales = ($arr | Measure-Object -Property MemoryDevices -Sum).Sum
        gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object {
            $fecha = $null; $dias = $null
            if ($_.DriverDate) { $fecha = $_.DriverDate.ToString('yyyy-MM-dd'); $dias = [int]((Get-Date) - $_.DriverDate).TotalDays }
            [ordered]@{
                nombre      = $_.Name
                driver      = $_.DriverVersion
                fechaDriver = $fecha
                diasDriver  = $dias
                resolucion  = ('{0}x{1}' -f $_.CurrentHorizontalResolution, $_.CurrentVerticalResolution)
                hzActual    = $_.CurrentRefreshRate
                hzMax       = $_.MaxRefreshRate
            }
        })
    }
}

# ---------------------------------------------------------------- discos
Invoke-Seccion 'discos' {
    $fisicos = @(Get-PhysicalDisk | ForEach-Object {
        [ordered]@{ numero = [string]$_.DeviceId; nombre = $_.FriendlyName; tipo = [string]$_.MediaType; bus = [string]$_.BusType; capacidadGB = [math]::Round($_.Size / 1GB); salud = [string]$_.HealthStatus }
    })
    $letraSistema = $env:SystemDrive.TrimEnd(':')
    $discoSistema = $null
    try {
        $num = [string](Get-Partition -DriveLetter $letraSistema).DiskNumber
        $discoSistema = $fisicos | Where-Object { $_.numero -eq $num } | Select-Object -First 1
    } catch { }
    [ordered]@{
        fisicos = $fisicos
        volumenes = @(Get-Volume | Where-Object { $_.DriveLetter -and [string]$_.DriveType -eq 'Fixed' -and $_.Size -gt 0 } | ForEach-Object {
            [ordered]@{
                letra       = [string]$_.DriveLetter
                capacidadGB = [math]::Round($_.Size / 1GB, 1)
                libreGB     = [math]::Round($_.SizeRemaining / 1GB, 1)
                librePct    = [math]::Round(100 * $_.SizeRemaining / $_.Size, 1)
            }
        })
        tipoDiscoSistema = $(if ($discoSistema) { $discoSistema.tipo } else { 'desconocido' })
    }
}

# ---------------------------------------------------------------- metricas en reposo
Invoke-Seccion 'metricas' {
    $cpu = @(); $disco = @()
    for ($i = 0; $i -lt 5; $i++) {
        $cpu += [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
        $disco += [double](100 - (Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'").PercentIdleTime)
        Start-Sleep -Seconds 1
    }
    $os = Get-CimInstance Win32_OperatingSystem
    $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    $totalKB = [double]$os.TotalVisibleMemorySize
    $libreKB = [double]$os.FreePhysicalMemory
    [ordered]@{
        cpuPromedioPct     = [math]::Round(($cpu | Measure-Object -Average).Average, 1)
        discoOcupadoPct    = [math]::Round(($disco | Measure-Object -Average).Average, 1)
        ramUsoGB           = [math]::Round(($totalKB - $libreKB) / 1MB, 2)
        ramUsoPct          = [math]::Round(100 * ($totalKB - $libreKB) / $totalKB, 1)
        comprometidaGB     = [math]::Round([double]$mem.CommittedBytes / 1GB, 2)
        limiteCompromisoGB = [math]::Round([double]$mem.CommitLimit / 1GB, 2)
        paginasPorSeg      = [double]$mem.PagesPersec
        procesos           = @(Get-Process).Count
    }
}

# ---------------------------------------------------------------- arranque
Invoke-Seccion 'arranque' {
    $log = 'Microsoft-Windows-Diagnostics-Performance/Operational'
    $eventos = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 100 } -MaxEvents 5 -ErrorAction SilentlyContinue | ForEach-Object {
        $d = @{}
        ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object { $d[$_.Name] = $_.'#text' }
        [ordered]@{ fecha = $_.TimeCreated.ToString('s'); arranqueMs = $d['BootTime']; postArranqueMs = $d['BootPostBootTime'] }
    })
    $degradaciones = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Id = 101, 102, 103, 106, 109 } -MaxEvents 40 -ErrorAction SilentlyContinue | ForEach-Object {
        $d = [ordered]@{ id = $_.Id; fecha = $_.TimeCreated.ToString('s') }
        ([xml]$_.ToXml()).Event.EventData.Data | Where-Object { $_.Name -match '^(Name|FileName|FriendlyName|TotalTime|DegradationTime)$' } |
            ForEach-Object { $d[$_.Name] = $_.'#text' }
        $d
    })
    [ordered]@{ eventos = $eventos; degradaciones = $degradaciones }
}

# ---------------------------------------------------------------- procesos
Invoke-Seccion 'procesos' {
    $hilos = [Environment]::ProcessorCount
    $t1 = @{}
    Get-Process | ForEach-Object { try { $t1[$_.Id] = $_.TotalProcessorTime.TotalSeconds } catch { } }
    Start-Sleep -Seconds 3
    $wmi = @{}
    Get-CimInstance Win32_Process | ForEach-Object { $wmi[[int]$_.ProcessId] = $_ }
    $empresas = @{}
    $lista = @(Get-Process | ForEach-Object {
        $cpuPct = 0
        try { if ($t1.ContainsKey($_.Id)) { $cpuPct = [math]::Round(100 * ($_.TotalProcessorTime.TotalSeconds - $t1[$_.Id]) / (3 * $hilos), 1) } } catch { }
        $w = $wmi[$_.Id]
        $ruta = $null; $cmd = $null
        if ($w) { $ruta = $w.ExecutablePath; $cmd = $w.CommandLine }
        $empresa = $null
        if ($ruta) {
            if (-not $empresas.ContainsKey($ruta)) {
                try { $empresas[$ruta] = (Get-Item -LiteralPath $ruta -ErrorAction Stop).VersionInfo.CompanyName } catch { $empresas[$ruta] = $null }
            }
            $empresa = $empresas[$ruta]
        }
        if ($cmd -and $cmd.Length -gt 300) { $cmd = $cmd.Substring(0, 300) + '...' }
        [pscustomobject]@{ pid = $_.Id; nombre = $_.ProcessName; cpuPct = $cpuPct; memoriaMB = [math]::Round($_.WorkingSet64 / 1MB, 1); ruta = $ruta; empresa = $empresa; comando = $cmd }
    })
    $sinComando = { $_ | Select-Object pid, nombre, cpuPct, memoriaMB, ruta, empresa }
    [ordered]@{
        total       = $lista.Count
        topCpu      = @($lista | Sort-Object cpuPct -Descending | Select-Object -First 20 | ForEach-Object $sinComando)
        topMemoria  = @($lista | Sort-Object memoriaMB -Descending | Select-Object -First 20 | ForEach-Object $sinComando)
        agrupados   = @($lista | Group-Object nombre | ForEach-Object {
            [ordered]@{
                nombre    = $_.Name
                instancias = $_.Count
                memoriaMB = [math]::Round(($_.Group | Measure-Object memoriaMB -Sum).Sum, 1)
                cpuPct    = [math]::Round(($_.Group | Measure-Object cpuPct -Sum).Sum, 1)
            }
        } | Sort-Object { $_.memoriaMB } -Descending | Select-Object -First 25)
        fueraDeWindows = @($lista | Where-Object { $_.ruta -and -not $_.ruta.StartsWith($env:WINDIR, [StringComparison]::OrdinalIgnoreCase) } |
            Sort-Object ruta -Unique | Select-Object nombre, ruta, empresa, comando)
    }
}

# ---------------------------------------------------------------- procesos sospechosos
Invoke-Seccion 'sospechosos' {
    $nombresSistema = @('svchost', 'csrss', 'lsass', 'winlogon', 'services', 'smss', 'wininit', 'dwm', 'conhost', 'rundll32', 'taskhostw', 'spoolsv', 'explorer', 'sihost', 'ctfmon')
    $resultado = @()
    foreach ($p in @(Get-CimInstance Win32_Process)) {
        $ruta = $p.ExecutablePath
        $nombre = [IO.Path]::GetFileNameWithoutExtension([string]$p.Name)
        $motivos = @()
        if ($ruta -and ($nombresSistema -contains $nombre.ToLower())) {
            $enWindows = $ruta.StartsWith($env:WINDIR, [StringComparison]::OrdinalIgnoreCase)
            if (-not $enWindows) { $motivos += 'nombre de proceso de sistema fuera de C:\Windows' }
        }
        if ($p.CommandLine -and (Test-Coincide $p.CommandLine.ToLower() $patronesComandoOculto)) {
            $motivos += 'linea de comando oculta u ofuscada'
        }
        if (-not $Rapido -and $ruta -and (Test-RutaUsuario $ruta)) {
            $f = Get-Firmante $ruta
            if ($f.estado -ne 'Valid') { $motivos += ('ejecutable sin firma valida en carpeta de usuario ({0})' -f $f.estado) }
        }
        if ($motivos.Count -gt 0) {
            $cmd = $p.CommandLine
            if ($cmd -and $cmd.Length -gt 300) { $cmd = $cmd.Substring(0, 300) + '...' }
            $resultado += [ordered]@{ pid = [int]$p.ProcessId; nombre = $p.Name; ruta = $ruta; comando = $cmd; motivos = $motivos }
        }
    }
    ,$resultado
}

# ---------------------------------------------------------------- programas de inicio
Invoke-Seccion 'inicio' {
    $entradas = @()
    $shell = $null
    foreach ($ub in $script:UbicacionesInicio.Keys) {
        $def = $script:UbicacionesInicio[$ub]
        if ($def.Tipo -eq 'registro') {
            if (-not (Test-Path $def.Ruta)) { continue }
            $clave = Get-Item $def.Ruta
            foreach ($n in $clave.GetValueNames()) {
                if (-not $n) { continue }
                $cmd = [string]$clave.GetValue($n)
                $entradas += [ordered]@{ ubicacion = $ub; nombre = $n; comando = $cmd; ejecutable = (Get-RutaEjecutable $cmd) }
            }
        } else {
            if (-not (Test-Path -LiteralPath $def.Ruta)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $def.Ruta -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
                $destino = $f.FullName
                if ($f.Extension -eq '.lnk') {
                    try {
                        if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                        $destino = $shell.CreateShortcut($f.FullName).TargetPath
                    } catch { }
                }
                $entradas += [ordered]@{ ubicacion = $ub; nombre = $f.Name; comando = $destino; ejecutable = $destino }
            }
        }
    }
    foreach ($e in $entradas) {
        $e.habilitado = Test-InicioHabilitado $e.ubicacion $e.nombre
        if (-not $Rapido) {
            $f = Get-Firmante $e.ejecutable
            $e.firma = $f.estado; $e.firmante = $f.firmante
        }
    }
    [ordered]@{
        habilitadas = @($entradas | Where-Object { $_.habilitado }).Count
        entradas    = $entradas
        nota        = 'No incluye apps de la Microsoft Store con inicio automatico: revisar en Configuracion > Aplicaciones > Inicio.'
    }
}

# ---------------------------------------------------------------- servicios
Invoke-Seccion 'servicios' {
    $todos = @(Get-CimInstance Win32_Service)
    $nombresCatalogo = @($catalogo.acciones | ForEach-Object { $_.pasos } | Where-Object { $_.tipo -eq 'servicio' } | ForEach-Object { $_.nombre })
    $terceros = @($todos | Where-Object { $_.PathName -and $_.PathName -notmatch '\\Windows\\(System32|SysWOW64|servicing|WinSxS)\\' -and $_.PathName -notmatch 'Windows Defender|Microsoft\\Windows Defender' } | ForEach-Object {
        $exe = Get-RutaEjecutable $_.PathName
        $o = [ordered]@{ nombre = $_.Name; mostrar = $_.DisplayName; inicio = $_.StartMode; estado = $_.State; modo = (Get-ModoInicioServicio $_.Name); ejecutable = $exe }
        if (-not $Rapido) { $f = Get-Firmante $exe; $o.firma = $f.estado; $o.firmante = $f.firmante }
        $o
    })
    [ordered]@{
        total                  = $todos.Count
        enEjecucion            = @($todos | Where-Object { $_.State -eq 'Running' }).Count
        automaticosEnEjecucion = @($todos | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -eq 'Running' } | ForEach-Object { $_.Name })
        terceros               = $terceros
        catalogo               = @($todos | Where-Object { $nombresCatalogo -contains $_.Name } | ForEach-Object {
            [ordered]@{ nombre = $_.Name; mostrar = $_.DisplayName; inicio = $_.StartMode; estado = $_.State; modo = (Get-ModoInicioServicio $_.Name) }
        })
    }
}

# ---------------------------------------------------------------- tareas programadas
Invoke-Seccion 'tareas' {
    $todas = @(Get-ScheduledTask)
    $rutasCatalogo = @($catalogo.acciones | ForEach-Object { $_.pasos } | Where-Object { $_.tipo -eq 'tarea' } | ForEach-Object { $_.ruta + $_.nombre })
    [ordered]@{
        terceros = @($todas | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
            $acciones = @($_.Actions | ForEach-Object { ('{0} {1}' -f $_.Execute, $_.Arguments).Trim() } | Where-Object { $_ })
            $motivos = @()
            foreach ($a in $acciones) {
                $al = $a.ToLower()
                if (Test-Coincide $al $patronesComandoOculto) { $motivos += 'comando oculto u ofuscado' }
                if ($al -match '\\appdata\\|\\temp\\|\\users\\public\\') { $motivos += 'ejecuta desde carpeta de usuario o temporal' }
            }
            [ordered]@{
                ruta = $_.TaskPath; nombre = $_.TaskName; estado = [string]$_.State; autor = $_.Author
                acciones = $acciones
                disparadores = @($_.Triggers | ForEach-Object { $_.CimClass.CimClassName -replace '^MSFT_Task', '' -replace 'Trigger$', '' })
                motivosSospecha = @($motivos | Select-Object -Unique)
            }
        })
        catalogo = @($todas | Where-Object { $rutasCatalogo -contains ($_.TaskPath + $_.TaskName) } | ForEach-Object {
            [ordered]@{ ruta = $_.TaskPath; nombre = $_.TaskName; estado = [string]$_.State }
        })
    }
}

# ---------------------------------------------------------------- aplicaciones
Invoke-Seccion 'aplicaciones' {
    $claves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $win32 = @(Get-ItemProperty -Path $claves -ErrorAction SilentlyContinue | Where-Object {
        $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -and
        -not ($_.PSObject.Properties['SystemComponent'] -and $_.SystemComponent -eq 1) -and
        -not $_.PSObject.Properties['ParentKeyName']
    } | Sort-Object DisplayName -Unique | ForEach-Object {
        $mb = 0
        if ($_.PSObject.Properties['EstimatedSize'] -and $_.EstimatedSize) { $mb = [math]::Round($_.EstimatedSize / 1024) }
        [ordered]@{
            nombre    = $_.DisplayName
            editor    = $(if ($_.PSObject.Properties['Publisher']) { $_.Publisher } else { $null })
            version   = $(if ($_.PSObject.Properties['DisplayVersion']) { $_.DisplayVersion } else { $null })
            instalado = $(if ($_.PSObject.Properties['InstallDate']) { $_.InstallDate } else { $null })
            mb        = $mb
        }
    })
    $appx = @()
    try {
        $appx = @(Get-AppxPaquetes | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and [string]$_.SignatureKind -eq 'Store' } |
            ForEach-Object { [ordered]@{ nombre = $_.Name; version = [string]$_.Version } })
    } catch {
        $errores.Add([ordered]@{ seccion = 'aplicaciones.appx'; error = $_.Exception.Message })
    }
    [ordered]@{ win32 = $win32; store = $appx }
}

# ---------------------------------------------------------------- seguridad
Invoke-Seccion 'seguridad' {
    $r = [ordered]@{ defender = $null; amenazas = @(); antivirus = @(); firewall = @(); integridadMemoria = $null }
    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        $r.defender = [ordered]@{
            servicioActivo       = $mp.AMServiceEnabled
            antivirusActivo      = $mp.AntivirusEnabled
            tiempoReal           = $mp.RealTimeProtectionEnabled
            firmasActualizadas   = $(if ($mp.AntivirusSignatureLastUpdated) { $mp.AntivirusSignatureLastUpdated.ToString('s') } else { $null })
            diasDesdeAnalisisRapido = $mp.QuickScanAge
            proteccionManipulacion  = $mp.IsTamperProtected
        }
        $r.amenazas = @(Get-MpThreat -ErrorAction SilentlyContinue | ForEach-Object {
            [ordered]@{ nombre = $_.ThreatName; severidad = $_.SeverityID; activa = $_.IsActive; seEjecuto = $_.DidThreatExecute }
        })
    } catch { $r.defender = [ordered]@{ error = $_.Exception.Message } }
    try {
        $r.antivirus = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
            $hex = '{0:X6}' -f [int]$_.productState
            [ordered]@{ nombre = $_.displayName; activo = (@('10', '11') -contains $hex.Substring(2, 2)); actualizado = ($hex.Substring(4, 2) -eq '00'); estadoHex = $hex }
        })
    } catch { }
    try { $r.firewall = @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object { [ordered]@{ perfil = $_.Name; activo = [bool]$_.Enabled } }) } catch { }
    $r.integridadMemoria = Get-RegDato 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    $r
}

# ---------------------------------------------------------------- ajustes de juego, visuales y navegador
Invoke-Seccion 'ajustes' {
    $cs = Get-CimInstance Win32_ComputerSystem
    $pagina = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{ archivo = $_.Name; asignadoMB = $_.AllocatedBaseSize; usoActualMB = $_.CurrentUsage; picoMB = $_.PeakUsage }
    })
    $compresion = $null
    try { $compresion = (Get-MMAgent -ErrorAction Stop).MemoryCompression } catch { }
    $desfrag = $null
    try { $desfrag = [string](Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction Stop).State } catch { }
    [ordered]@{
        planEnergiaActivo   = Get-PlanEnergiaActivo
        planesEnergia       = Get-PlanesEnergia
        modoJuego           = Get-RegDato 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
        gameDvr             = Get-RegDato 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
        capturaApps         = Get-RegDato 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
        hags                = Get-RegDato 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
        efectosVisuales     = Get-RegDato 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting'
        transparencia       = Get-RegDato 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency'
        appsSegundoPlanoOff = Get-RegDato 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled'
        paginacionAutomatica = $cs.AutomaticManagedPagefile
        archivoPaginacion   = $pagina
        compresionMemoria   = $compresion
        desfragProgramada   = $desfrag
        politicasNavegador  = [ordered]@{
            edgeArranqueRapido = Get-RegDato 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled'
            edgeSegundoPlano   = Get-RegDato 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled'
            chromeSegundoPlano = Get-RegDato 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'BackgroundModeEnabled'
        }
    }
}

# ---------------------------------------------------------------- red
function Measure-Ping([string]$Destino, [int]$Veces = 10) {
    $ping = New-Object System.Net.NetworkInformation.Ping
    $tiempos = @()
    for ($i = 0; $i -lt $Veces; $i++) {
        try {
            $resp = $ping.Send($Destino, 1000)
            if ($resp.Status -eq 'Success') { $tiempos += [double]$resp.RoundtripTime }
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    $r = [ordered]@{ destino = $Destino; enviados = $Veces; recibidos = $tiempos.Count; perdidaPct = [math]::Round(100 * ($Veces - $tiempos.Count) / $Veces, 1) }
    if ($tiempos.Count -gt 0) {
        $m = $tiempos | Measure-Object -Minimum -Maximum -Average
        $jit = 0
        if ($tiempos.Count -gt 1) {
            $difs = for ($j = 1; $j -lt $tiempos.Count; $j++) { [math]::Abs($tiempos[$j] - $tiempos[$j - 1]) }
            $jit = ($difs | Measure-Object -Average).Average
        }
        $r.minMs = $m.Minimum; $r.promMs = [math]::Round($m.Average, 1); $r.maxMs = $m.Maximum; $r.jitterMs = [math]::Round($jit, 1)
    }
    return $r
}

Invoke-Seccion 'red' {
    $adaptadores = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
        [ordered]@{ nombre = $_.Name; descripcion = $_.InterfaceDescription; velocidad = $_.LinkSpeed; inalambrico = ([string]$_.PhysicalMediaType -match '802\.11|Wireless') }
    })
    $gw = $null
    try { $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1).NextHop } catch { }
    $r = [ordered]@{ adaptadores = $adaptadores; puertaEnlace = $gw; ping = @() }
    if (-not $Rapido) {
        if ($gw) { $r.ping += Measure-Ping $gw }
        $r.ping += Measure-Ping '1.1.1.1'
    }
    $r
}

# ---------------------------------------------------------------- temporales y volcados
Invoke-Seccion 'temporales' {
    $r = [ordered]@{}
    if (-not $Rapido) {
        $r.tempUsuarioMB  = Get-TamanoCarpetaMB $env:TEMP
        $r.tempWindowsMB  = Get-TamanoCarpetaMB (Join-Path $env:WINDIR 'Temp')
        $r.descargasWindowsUpdateMB = Get-TamanoCarpetaMB (Join-Path $env:WINDIR 'SoftwareDistribution\Download')
    }
    $mini = Join-Path $env:WINDIR 'Minidump'
    $r.pantallazosAzules = @(Get-ChildItem -LiteralPath $mini -Filter '*.dmp' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
        Select-Object -First 10 | ForEach-Object { $_.LastWriteTime.ToString('s') })
    $r
}

# ---------------------------------------------------------------- estabilidad
Invoke-Seccion 'estabilidad' {
    $desde = (Get-Date).AddDays(-14)
    $sistema = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = $desde } -MaxEvents 1000 -ErrorAction SilentlyContinue)
    $apps = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $desde } -MaxEvents 300 -ErrorAction SilentlyContinue)
    [ordered]@{
        dias                 = 14
        erroresSistema       = $sistema.Count
        apagadosInesperados  = @($sistema | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41 }).Count
        erroresHardwareWhea  = @($sistema | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' }).Count
        principalesOrigenes  = @($sistema | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { [ordered]@{ origen = $_.Name; eventos = $_.Count } })
        appsQueFallan        = @($apps | ForEach-Object { if ($_.Properties.Count -gt 0) { [string]$_.Properties[0].Value } } |
            Group-Object | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { [ordered]@{ app = $_.Name; fallos = $_.Count } })
    }
}

# ---------------------------------------------------------------- guardar
$diag.errores = @($errores)
$rutaJson = Join-Path $carpeta "diagnostico-$Etiqueta.json"
Write-Json $diag $rutaJson

$res = New-Object System.Collections.Generic.List[string]
$res.Add("RESUMEN DEL DIAGNOSTICO ($Etiqueta) - $($diag.meta.fecha)")
if ($diag.sistema) { $res.Add(('Sistema: {0} {1} (build {2}) | Portatil: {3} | Dias encendido: {4}' -f $diag.sistema.so, $diag.sistema.version, $diag.sistema.build, $diag.sistema.esPortatil, $diag.sistema.diasEncendido)) }
if ($diag.hardware) {
    $res.Add(('CPU: {0} | RAM: {1} GB en {2} modulo(s) de {3} ranura(s)' -f ($diag.hardware.cpu | Select-Object -First 1).nombre, $diag.hardware.ramGB, @($diag.hardware.ramModulos).Count, $diag.hardware.ramRanurasTotales))
    foreach ($g in $diag.hardware.gpu) { $res.Add(('GPU: {0} | Driver {1} ({2}) | {3} @ {4} Hz (max {5})' -f $g.nombre, $g.driver, $g.fechaDriver, $g.resolucion, $g.hzActual, $g.hzMax)) }
}
if ($diag.discos) {
    $res.Add('Disco del sistema: ' + $diag.discos.tipoDiscoSistema)
    foreach ($v in $diag.discos.volumenes) { $res.Add(('  {0}: {1} GB libres de {2} GB ({3}%)' -f $v.letra, $v.libreGB, $v.capacidadGB, $v.librePct)) }
}
if ($diag.metricas) { $res.Add(('Reposo: CPU {0}% | RAM {1}% ({2} GB) | Disco ocupado {3}% | Procesos {4}' -f $diag.metricas.cpuPromedioPct, $diag.metricas.ramUsoPct, $diag.metricas.ramUsoGB, $diag.metricas.discoOcupadoPct, $diag.metricas.procesos)) }
if ($diag.inicio) { $res.Add(('Programas de inicio habilitados: {0}' -f $diag.inicio.habilitadas)) }
if ($diag.servicios) { $res.Add(('Servicios automaticos en ejecucion: {0} | de terceros: {1}' -f @($diag.servicios.automaticosEnEjecucion).Count, @($diag.servicios.terceros).Count)) }
if ($null -ne $diag.sospechosos) { $res.Add(('Procesos con indicios de sospecha: {0}' -f @($diag.sospechosos).Count)) }
if ($diag.seguridad -and $diag.seguridad.defender -and $diag.seguridad.defender.Contains('tiempoReal')) { $res.Add(('Defender tiempo real: {0} | Antivirus detectados: {1}' -f $diag.seguridad.defender.tiempoReal, @($diag.seguridad.antivirus).Count)) }
if ($diag.arranque -and @($diag.arranque.eventos).Count -gt 0) { $res.Add(('Ultimo arranque medido: {0} ms' -f $diag.arranque.eventos[0].arranqueMs)) }
if ($errores.Count -gt 0) { $res.Add(('Secciones con error: {0}' -f (($errores | ForEach-Object { $_.seccion }) -join ', '))) }
$rutaResumen = Join-Path $carpeta "resumen-$Etiqueta.txt"
$utf8SinBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($rutaResumen, $res, $utf8SinBom)

Write-Host ''
$res | ForEach-Object { Write-Host $_ }
Write-Host ''
Write-Host "CARPETA_REPORTE=$carpeta"
Write-Host "DIAGNOSTICO_JSON=$rutaJson"
