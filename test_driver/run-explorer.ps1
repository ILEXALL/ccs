param([int]$Seed = 1701, [ValidateRange(1,200)][int]$Steps = 40, [ValidateRange(1,1000)][int]$Rounds = 1,
  [ValidateSet('all','spots','explore','profile','garage','settings','chats','saved','submissions','notifications','friends','xp')][string]$Section = 'spots', [switch]$Choose)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$sections = @('spots','explore','profile','garage','settings','chats','saved','submissions','notifications','friends','xp')
if ($Choose) {
  $choices = @('all') + $sections
  for ($i = 0; $i -lt $choices.Count; $i++) { Write-Host "$($i + 1). $($choices[$i])" }
  $choice = 0
  if (![int]::TryParse((Read-Host 'Section number'), [ref]$choice) -or $choice -lt 1 -or $choice -gt $choices.Count) { throw 'Invalid section' }
  $Section = $choices[$choice - 1]
}
$sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
if (!(Test-Path $adb)) { throw 'Android SDK not found.' }
$devices = & $adb devices
$device = ($devices | Where-Object { $_ -match '^emulator-\d+\s+device$' } | Select-Object -First 1) -replace '\s+device$', ''
if (!$device) {
  Start-Process -FilePath $emulator -ArgumentList '-avd','Pixel_7_Pro','-no-snapshot-load' -WindowStyle Hidden
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    Start-Sleep -Seconds 2
    $device = ((& $adb devices) | Where-Object { $_ -match '^emulator-\d+\s+device$' } | Select-Object -First 1) -replace '\s+device$', ''
    if ($device -and ((& $adb -s $device shell getprop sys.boot_completed) -match '1')) { break }
  }
}
if (!$device) { throw 'Android emulator did not start.' }
$env:CCS_UI_SANDBOX = '1'
& $adb -s $device shell svc wifi disable
& $adb -s $device shell svc data disable
& $adb -s $device shell cmd connectivity airplane-mode enable
Start-Sleep -Seconds 2
$routes = & $adb -s $device shell ip route show table all
if ($routes | Where-Object { $_ -match '^default ' -and $_ -notmatch '\bdev dummy0\b' }) {
  throw 'Emulator still has a default network route; refusing UI exploration.'
}
$logs = New-Item -ItemType Directory -Force 'build\ui-explorer'
$selectedSections = if ($Section -eq 'all') { $sections } else { @($Section) }
$results = @()
foreach ($currentSection in $selectedSections) {
for ($round = 0; $round -lt $Rounds; $round++) {
  $runSeed = $Seed + $round
  Write-Host "Offline UI pilot: $currentSection. Seed=$runSeed Steps=$Steps Round=$($round + 1)/$Rounds"
  $log = Join-Path $logs.FullName ("run-{0}-{1}.log" -f $runSeed, (Get-Date -Format 'yyyyMMdd-HHmmss'))
  $ErrorActionPreference = 'Continue'
  & flutter.bat build apk --debug --target=integration_test/spot_explorer_test.dart "--dart-define=CCS_SEED=$runSeed" "--dart-define=CCS_STEPS=$Steps" "--dart-define=CCS_SECTION=$currentSection" 2>&1 | Tee-Object -FilePath $log
  if ($LASTEXITCODE -ne 0) { exit 1 }
  $aapt = Get-ChildItem (Join-Path $sdk 'build-tools') -Filter aapt.exe -Recurse | Select-Object -First 1 -ExpandProperty FullName
  $package = (& $aapt dump badging build/app/outputs/flutter-apk/app-debug.apk | Select-String '^package:').ToString()
  if ($package -notmatch "name='com.example.ccs_app.uitest'") { throw 'Refusing to install a non-sandbox APK.' }
  & flutter.bat drive --driver=test_driver/explorer_driver.dart --target=integration_test/spot_explorer_test.dart --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk --keep-app-running -d $device 2>&1 | Tee-Object -FilePath $log -Append
  $testExit = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  $results += [pscustomobject]@{ section = $currentSection; seed = $runSeed; exitCode = $testExit; log = $log; coverage = 'offline screen pilot' }
  if ($testExit -ne 0) {
    Write-Host "Stopped: inspect build\ui-explorer for the report and screenshots. Log: $log"
    break
  }
}
}
$results | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $logs.FullName 'latest-summary.json')
if ($results | Where-Object { $_.exitCode -ne 0 }) { exit 1 }
