# devenv-device's installer for Windows (published with every release, the release key filled in). In PowerShell
# opened with "Run as administrator":
#   & ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/vidklopcic/devenv-artifacts/main/install.ps1))) <url> <code> [--user U] [--code XXXX-...]
#   & ([scriptblock]::Create((iwr -useb .../install.ps1)))   (no arguments, on a computer linked already: the newest
#                                                             release, and its service installed again)
# The same steps as install.sh: the newest release, release.json's signature checked with the release key (ssh-keygen
# -Y verify: Windows' own OpenSSH client), the build's hash checked against it, the build put in
# %ProgramFiles%\devenv-device and this computer linked (devenv-device link <url> <code>): the link asks, in this
# window, whether the passkeys' code it prints is the one the page shows (--code: given instead).
# ASCII only: Windows PowerShell reads a file without a BOM in the system's code page.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # (Windows PowerShell's progress bar makes downloads crawl)
$Base = 'https://raw.githubusercontent.com/vidklopcic/devenv-artifacts/main'
$ReleaseKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBfK5mNIPSH6cOdjZdlJk0w9qz9sXGkl2B6bXCScThat devenv-device-release'
function Die([string]$Msg) { throw "devenv-device install: $Msg" }

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Die 'run it in PowerShell opened with "Run as administrator"'
}
$data = Join-Path $env:ProgramData 'devenv-device'
$linked = ($args.Count -eq 0) -and (Test-Path (Join-Path $data 'etc\config.json'))
if (($args.Count -lt 2) -and -not $linked) {
  Die 'usage: & ([scriptblock]::Create((iwr -useb .../install.ps1))) <url> <code> [--user U]   (the command Resources -> Devices shows)'
}
$cpu = $env:PROCESSOR_ARCHITEW6432
if (-not $cpu) { $cpu = $env:PROCESSOR_ARCHITECTURE }
switch ($cpu) {
  'AMD64' { $arch = 'amd64' }
  'ARM64' { $arch = 'arm64' }
  default { Die "$cpu isn't supported (64-bit Intel/AMD or ARM only)" }
}
$keygen = (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue).Source
if (-not $keygen) {
  $keygen = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe'
  if (-not (Test-Path $keygen)) {
    Die ("ssh-keygen.exe (Windows' OpenSSH client) is needed to check the release's signature: " +
      'Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0  (or Settings -> Optional features -> OpenSSH Client)')
  }
}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('devenv-device-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  function Fetch([string]$Name) {
    try {
      Invoke-WebRequest -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache' } -Uri "$Base/$Name" -OutFile (Join-Path $tmp $Name)
    } catch { Die "couldn't download ${Name}: $($_.Exception.Message)" }
  }
  # ssh-keygen gets the files' bytes as they are: through Start-Process's redirection, never PowerShell's pipeline
  # (which re-encodes text)
  [IO.File]::WriteAllText((Join-Path $tmp 'allowed'), "devenv-device $ReleaseKey`n", (New-Object Text.ASCIIEncoding))
  $q = { param($p) '"' + $p + '"' }
  # release.json and its .sig are cached apart by GitHub's CDN (minutes): just after a release one may be the new and
  # the other the old (2026-11-06: "incorrect signature"). A mismatch is fetched again, both, for up to 6 min.
  for ($try = 1; ; $try++) {
    Fetch 'release.json'
    Fetch 'release.json.sig'
    $verify = Start-Process -FilePath $keygen -NoNewWindow -Wait -PassThru `
      -ArgumentList @('-Y', 'verify', '-f', (& $q (Join-Path $tmp 'allowed')), '-I', 'devenv-device', '-n', 'devenv-device',
        '-s', (& $q (Join-Path $tmp 'release.json.sig'))) `
      -RedirectStandardInput (Join-Path $tmp 'release.json') `
      -RedirectStandardOutput (Join-Path $tmp 'verify.out') -RedirectStandardError (Join-Path $tmp 'verify.err')
    $err = Get-Content -Raw (Join-Path $tmp 'verify.err') -ErrorAction SilentlyContinue
    if ($verify.ExitCode -eq 0 -or $try -ge 12 -or $err -notmatch 'incorrect signature') { break }
    Write-Host "release.json and its signature don't match yet (GitHub's cache, just after a release): again in 30 s ($try of 12)"
    Start-Sleep -Seconds 30
  }
  if ($verify.ExitCode -ne 0) {
    $why = (Get-Content -Raw (Join-Path $tmp 'verify.err') -ErrorAction SilentlyContinue) + (Get-Content -Raw (Join-Path $tmp 'verify.out') -ErrorAction SilentlyContinue)
    if ($why -match 'unknown option|illegal option|usage:') {
      Die ("this computer's ssh-keygen is too old to check signatures (OpenSSH 8.1 or later is needed; " +
        'Windows Server 2019 and early Windows 10 have 7.7): install a newer OpenSSH (winget install Microsoft.OpenSSH.Preview), then run this again')
    }
    Die "release.json isn't signed with the release key: not installing ($($why.Trim()))"
  }
  $release = Get-Content -Raw (Join-Path $tmp 'release.json') | ConvertFrom-Json
  $name = "devenv-device-windows-$arch.exe"
  $want = $release.files.$name
  if (-not $want) { Die "the release has no build for windows/$arch" }
  Fetch $name
  $got = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $tmp $name)).Hash.ToLower()
  if ($got -ne $want.ToLower()) { Die "$name isn't the build the signed release names: not installing" }

  # its folders: the program's (Administrators and SYSTEM write, users run it: a shell's sftp runs it as the user) and
  # its data's (SYSTEM and Administrators alone: the device key, the pinned passkeys)
  $dir = Join-Path $env:ProgramFiles 'devenv-device'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  & icacls.exe $dir /inheritance:r /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
  if ($LASTEXITCODE -ne 0) { Die "couldn't set who may write $dir" }
  New-Item -ItemType Directory -Force -Path $data | Out-Null
  & icacls.exe $data /inheritance:r /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
  if ($LASTEXITCODE -ne 0) { Die "couldn't set who may read $data" }
  # a running devenv-device.exe can't be written over, but it can be renamed: the service starts the new one
  $exe = Join-Path $dir 'devenv-device.exe'
  $old = Join-Path $dir 'devenv-device.old.exe'
  if (Test-Path $old) { Remove-Item -Force $old -ErrorAction SilentlyContinue }
  if (Test-Path $exe) { Move-Item -Force $exe $old }
  Copy-Item (Join-Path $tmp $name) $exe
  $v = & $exe version
  Write-Host "devenv-device $v installed (signature checked)."
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($linked) {
  & $exe service   # (linked already: its service, on this release)
} else {
  & $exe link @args   # (it asks in this window; --code for none)
}
if ($LASTEXITCODE -ne 0) { Die "devenv-device $(if ($linked) { 'service' } else { 'link' }) failed" }
