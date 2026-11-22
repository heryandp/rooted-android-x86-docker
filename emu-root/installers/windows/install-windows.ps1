#Requires -Version 5.1
<#
.SYNOPSIS
  Automated installer for emu-root (Android 12 Play Store + Magisk Root AVD) on Windows.

.DESCRIPTION
  Installs/verifies Android SDK command-line tools, platform-tools, emulator, and
  Android 12 (API 31) Google Play x86_64 system image, creates the Pixel_7_API_31_Rooted
  AVD, patches ramdisk.img with Magisk via rootAVD, and installs emu-root.cmd into
  %USERPROFILE%\bin on your User PATH.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -SkipRoot
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -AvdName "My_Pixel_Root" -RamMB 4096 -Cores 4
#>
[CmdletBinding()]
param(
    [string]$SdkRoot = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }),
    [string]$AvdName = "Pixel_7_API_31_Rooted",
    [int]$ApiLevel = 31,
    [int]$RamMB = 4096,
    [int]$Cores = 4,
    [string]$DataSize = "8G",
    [string]$BinDir = $(Join-Path $env:USERPROFILE "bin"),
    [switch]$SkipRoot,
    [switch]$ForceRecreateAvd
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Ensure-UserPath([string]$Dir) {
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) {
        $parts = $current -split ";" | Where-Object { $_ -and $_.Trim() -ne "" }
    }
    if (-not ($parts | Where-Object { $_.TrimEnd("\") -ieq $Dir.TrimEnd("\") })) {
        $newPath = ($parts + $Dir) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$Dir;$env:Path"
        Write-Ok "Added '$Dir' to User PATH"
    } else {
        Write-Ok "'$Dir' is already in User PATH"
    }
}

function Get-LatestCmdlineToolsUrl {
    $fallback = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
    try {
        $xmlText = (Invoke-WebRequest -Uri "https://dl.google.com/android/repository/repository2-3.xml" -UseBasicParsing -TimeoutSec 20).Content
        $matches = [regex]::Matches($xmlText, "commandlinetools-win-\d+_latest\.zip")
        if ($matches.Count -gt 0) {
            $latest = $matches[$matches.Count - 1].Value
            return "https://dl.google.com/android/repository/$latest"
        }
    } catch {
        Write-Warn "Could not query Google SDK XML index; using fallback commandlinetools build."
    }
    return $fallback
}

function Ensure-Java {
    Write-Step "Checking Java (JDK 17+ required by sdkmanager)"
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        Write-Ok "Java found: $($javaCmd.Source)"
        return
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing Microsoft OpenJDK 17 via winget..."
        winget install --id Microsoft.OpenJDK.17 --exact --accept-source-agreements --accept-package-agreements
        $jdkDir = Get-ChildItem "C:\Program Files\Microsoft\jdk-17*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
        if ($jdkDir) {
            $env:JAVA_HOME = $jdkDir.FullName
            $env:Path = "$(Join-Path $jdkDir.FullName 'bin');$env:Path"
            Write-Ok "Installed JDK 17 at $($jdkDir.FullName)"
            return
        }
    }
    throw "Java (JDK 17+) is not installed. Please install OpenJDK 17 and re-run this script."
}

function Ensure-CmdlineTools([string]$Root) {
    $sdkmanager = Join-Path $Root "cmdline-tools\latest\bin\sdkmanager.bat"
    if (Test-Path $sdkmanager) {
        Write-Ok "Android cmdline-tools found: $sdkmanager"
        return $sdkmanager
    }

    Write-Step "Downloading Android SDK Command-Line Tools"
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $url = Get-LatestCmdlineToolsUrl
    $zipPath = Join-Path $env:TEMP "android-cmdline-tools-win.zip"
    $extractTmp = Join-Path $env:TEMP "android-cmdline-tools-extract"

    Write-Host "Downloading: $url"
    Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
    if (Test-Path $extractTmp) { Remove-Item $extractTmp -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extractTmp -Force

    $destBase = Join-Path $Root "cmdline-tools"
    $destLatest = Join-Path $destBase "latest"
    New-Item -ItemType Directory -Path $destBase -Force | Out-Null
    if (Test-Path $destLatest) { Remove-Item $destLatest -Recurse -Force }
    Move-Item -Path (Join-Path $extractTmp "cmdline-tools") -Destination $destLatest

    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $sdkmanager)) {
        throw "Failed to install sdkmanager at $sdkmanager"
    }
    Write-Ok "Installed Android cmdline-tools at $destLatest"
    return $sdkmanager
}

function Set-IniKey([string]$Path, [string]$Key, [string]$Value) {
    $lines = @()
    if (Test-Path $Path) {
        $lines = Get-Content -Path $Path
    }
    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*="
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Key = $Value"
            $found = $true
        }
    }
    if (-not $found) {
        $lines += "$Key = $Value"
    }
    Set-Content -Path $Path -Value $lines -Encoding ASCII
}

# ------------------------------------------------------------------------------
# Main Installation Flow
# ------------------------------------------------------------------------------
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  emu-root Windows Installer (Android $ApiLevel Play Store + Magisk)" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Ensure-Java

$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
[Environment]::SetEnvironmentVariable("ANDROID_HOME", $SdkRoot, "User")

$sdkmanager = Ensure-CmdlineTools -Root $SdkRoot
$avdmanager = Join-Path $SdkRoot "cmdline-tools\latest\bin\avdmanager.bat"
$adbExe = Join-Path $SdkRoot "platform-tools\adb.exe"
$emuExe = Join-Path $SdkRoot "emulator\emulator.exe"
$sysImagePkg = "system-images;android-$ApiLevel;google_apis_playstore;x86_64"

Write-Step "Accepting Android SDK licenses and installing packages"
("y`n" * 20) | & $sdkmanager --sdk_root="$SdkRoot" --licenses | Out-Null
& $sdkmanager --sdk_root="$SdkRoot" "platform-tools" "emulator" "platforms;android-$ApiLevel" $sysImagePkg

Write-Step "Configuring User PATH and environment variables"
Ensure-UserPath (Join-Path $SdkRoot "platform-tools")
Ensure-UserPath (Join-Path $SdkRoot "emulator")
Ensure-UserPath (Join-Path $SdkRoot "cmdline-tools\latest\bin")
[Environment]::SetEnvironmentVariable("ADB_PATH", $adbExe, "User")

Write-Step "Creating AVD '$AvdName'"
$avdHome = if ($env:ANDROID_AVD_HOME) { $env:ANDROID_AVD_HOME } else { Join-Path $env:USERPROFILE ".android\avd" }
$avdDir = Join-Path $avdHome "$AvdName.avd"

if ((Test-Path $avdDir) -and (-not $ForceRecreateAvd)) {
    Write-Ok "AVD '$AvdName' already exists at $avdDir (use -ForceRecreateAvd to recreate)"
} else {
    $createArgs = @("create", "avd", "-n", $AvdName, "-k", $sysImagePkg, "-d", "pixel_7")
    if ($ForceRecreateAvd) { $createArgs += "--force" }
    "no" | & $avdmanager @createArgs
    Write-Ok "Created AVD '$AvdName'"
}

$configIni = Join-Path $avdDir "config.ini"
if (Test-Path $configIni) {
    Set-IniKey -Path $configIni -Key "PlayStore.enabled" -Value "true"
    Set-IniKey -Path $configIni -Key "hw.cpu.ncore" -Value "$Cores"
    Set-IniKey -Path $configIni -Key "hw.ramSize" -Value "$RamMB"
    Set-IniKey -Path $configIni -Key "vm.heapSize" -Value "512"
    Set-IniKey -Path $configIni -Key "disk.dataPartition.size" -Value $DataSize
    Set-IniKey -Path $configIni -Key "hw.gpu.enabled" -Value "yes"
    Set-IniKey -Path $configIni -Key "hw.gpu.mode" -Value "host"
    Set-IniKey -Path $configIni -Key "hw.keyboard" -Value "yes"
    Set-IniKey -Path $configIni -Key "fastboot.forceColdBoot" -Value "yes"
    Set-IniKey -Path $configIni -Key "fastboot.forceFastBoot" -Value "no"
    Set-IniKey -Path $configIni -Key "avd.ini.displayname" -Value "Pixel 7 API $ApiLevel (Android 12 PlayStore Rooted)"
    Write-Ok "Updated AVD hardware configuration in $configIni"
}

Write-Step "Installing emu-root.cmd into '$BinDir'"
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
$scriptSource = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "bin\emu-root.cmd"
$targetCmd = Join-Path $BinDir "emu-root.cmd"

if (Test-Path $scriptSource) {
    Copy-Item -Path $scriptSource -Destination $targetCmd -Force
} else {
    $rawUrl = "https://raw.githubusercontent.com/heryandp/rooted-android-x86-docker/main/emu-root/bin/emu-root.cmd"
    Invoke-WebRequest -Uri $rawUrl -OutFile $targetCmd -UseBasicParsing
}
Ensure-UserPath $BinDir
Write-Ok "Installed launcher: $targetCmd"

if (-not $SkipRoot) {
    Write-Step "Rooting AVD ramdisk.img with Magisk via rootAVD"
    $ramdiskRel = "system-images\android-$ApiLevel\google_apis_playstore\x86_64\ramdisk.img"
    $ramdiskBackup = Join-Path $SdkRoot ($ramdiskRel + ".backup")

    if (Test-Path $ramdiskBackup) {
        Write-Ok "Backup detected ($ramdiskBackup) — ramdisk.img appears already patched with Magisk. Skipping re-patch."
    } else {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Warn "git is not installed. Skipping automatic rootAVD patching; install git and run rootAVD manually."
        } else {
            $rootAvdDir = Join-Path $env:USERPROFILE "AndroidTools\rootAVD"
            if (-not (Test-Path $rootAvdDir)) {
                New-Item -ItemType Directory -Path (Split-Path -Parent $rootAvdDir) -Force | Out-Null
                git clone --depth 1 https://gitlab.com/newbit/rootAVD.git $rootAvdDir
            }

            Write-Host "Booting '$AvdName' temporarily so rootAVD can patch ramdisk.img..."
            $emuProc = Start-Process -FilePath $emuExe -ArgumentList "-avd", $AvdName, "-no-snapshot", "-no-metrics" -PassThru

            $waited = 0
            while ($waited -lt 180) {
                $boot = (& $adbExe -e shell getprop sys.boot_completed 2>$null)
                if ($boot -and $boot.Trim() -eq "1") { break }
                Start-Sleep -Seconds 3
                $waited += 3
            }

            if ($waited -ge 180) {
                Write-Warn "Timed out waiting for AVD boot. Run rootAVD manually once the emulator is booted."
            } else {
                Push-Location $rootAvdDir
                try {
                    & cmd /c "rootAVD.bat $ramdiskRel"
                    Write-Ok "rootAVD patching finished! Waiting for emulator shutdown..."
                } finally {
                    Pop-Location
                }
                Start-Sleep -Seconds 5
                & $adbExe -e emu kill 2>$null | Out-Null
            }
        }
    }
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "  Open a new terminal and run:  emu-root" -ForegroundColor Green
Write-Host "  Root shell:                   emu-root --root" -ForegroundColor Green
Write-Host "  Stop emulator:                emu-root --stop" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
