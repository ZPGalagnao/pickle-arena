# Builds the Pickle Arena APK. Safe to re-run: downloads resume where they stopped.
#   powershell -ExecutionPolicy Bypass -File build_apk.ps1
$ErrorActionPreference = 'Continue'
$env:Path = "C:\Users\admin\dev\flutter\bin;" + $env:Path
$env:JAVA_HOME = "C:\Users\admin\dev\jdk-21.0.13+9"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
Set-Location $PSScriptRoot

# 1. Gradle 9.5 (resumable download into the folder the Gradle wrapper uses)
$dist = "$env:USERPROFILE\.gradle\wrapper\dists\gradle-9.5.0-bin\bvnork1r7n8i6kp5cnkibsc9q"
$zip = "$dist\gradle-9.5.0-bin.zip"
if (-not (Test-Path $zip)) {
    New-Item -ItemType Directory -Force $dist | Out-Null
    Write-Host "Downloading Gradle 9.5 (140 MB, resumable)..."
    for ($i = 1; $i -le 50; $i++) {
        curl.exe -L --retry 5 --retry-delay 3 --retry-all-errors -C - -o "$zip.dl" `
            https://services.gradle.org/distributions/gradle-9.5.0-bin.zip
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host "  connection dropped, resuming (attempt $i)..."
        Start-Sleep -Seconds 5
    }
    Move-Item "$zip.dl" $zip -Force
}

# 2. Build (Gradle downloads the Android plugins/libraries; retried on network errors)
for ($i = 1; $i -le 5; $i++) {
    Write-Host "Building APK (attempt $i)..."
    flutter build apk --release
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "DONE: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
        exit 0
    }
    Start-Sleep -Seconds 10
}
Write-Host "Build failed. Check your internet connection and run this script again." -ForegroundColor Red
exit 1
