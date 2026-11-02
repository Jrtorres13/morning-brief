# Morning Brief installer: copies the app to your user folder and adds
# Desktop, Start Menu and "open at sign-in" shortcuts. No admin needed.
# -Update: run by the one-click updater; skips opening the app (its window refreshes itself).
param([switch]$Update)
$ErrorActionPreference = 'Stop'
$src  = Join-Path $PSScriptRoot 'app'
$dest = Join-Path $env:LOCALAPPDATA 'MorningBrief'
if (-not (Test-Path -LiteralPath (Join-Path $src 'index.html'))) {
  throw 'Unzip the download first (right-click > Extract All), then run Install.bat from the unzipped folder.'
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Get-ChildItem -LiteralPath $src -Recurse | Unblock-File -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath $src | Copy-Item -Destination $dest -Recurse -Force

$candidates = @(
  "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
  "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
  "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
foreach ($exe in 'msedge.exe','chrome.exe') {
  foreach ($hive in 'HKCU:','HKLM:') {
    $reg = Get-ItemProperty "$hive\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$exe" -ErrorAction SilentlyContinue
    if ($reg) { $candidates += $reg.'(default)' }
  }
}
$browser = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $browser) { throw 'Microsoft Edge or Google Chrome is required and was not found.' }

$url     = ([System.Uri](Join-Path $dest 'index.html')).AbsoluteUri
$profileDir = Join-Path $dest 'profile'
$appArgs    = "--app=`"$url`" --user-data-dir=`"$profileDir`" --window-size=1200,860 --no-first-run --no-default-browser-check"

$shell = New-Object -ComObject WScript.Shell
$places = @(
  [Environment]::GetFolderPath('Desktop'),
  (Join-Path ([Environment]::GetFolderPath('StartMenu')) 'Programs'),
  [Environment]::GetFolderPath('Startup')
)
foreach ($dir in $places) {
  $lnk = $shell.CreateShortcut((Join-Path $dir 'Morning Brief.lnk'))
  $lnk.TargetPath  = $browser
  $lnk.Arguments   = $appArgs
  $lnk.WorkingDirectory = $dest
  $lnk.IconLocation = (Join-Path $dest "icon.ico")
  $lnk.Description = 'Plan your workday'
  $lnk.Save()
}

Write-Host ''
Write-Host 'Morning Brief is installed.' -ForegroundColor Green
Write-Host '- It opens every time you sign in to Windows.'
Write-Host '- Desktop and Start Menu shortcuts were added.'
Write-Host ''
# One-click updates: the app's "Update now" button opens jrtapp://update/<app>, which runs updater.ps1.
$updDir = Join-Path $env:LOCALAPPDATA 'JrtApps'
New-Item -ItemType Directory -Force -Path $updDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'updater.ps1') -Destination $updDir -Force
$cls = 'HKCU:\Software\Classes\jrtapp'
foreach ($k in $cls, "$cls\shell", "$cls\shell\open", "$cls\shell\open\command") { if (-not (Test-Path $k)) { New-Item -Path $k | Out-Null } }
Set-ItemProperty -Path $cls -Name '(default)' -Value 'URL:App updates'
Set-ItemProperty -Path $cls -Name 'URL Protocol' -Value ''
Set-ItemProperty -Path "$cls\shell\open\command" -Name '(default)' -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$updDir\updater.ps1`" `"%1`""
if (-not $Update) { Start-Process -FilePath $browser -ArgumentList $appArgs }
