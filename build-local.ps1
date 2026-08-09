param(
  [switch]$SkipBuild = $false,
  [switch]$SkipInstall = $false,
  [switch]$CleanInstall = $false,
  [switch]$SkipLint = $true
)

$ErrorActionPreference = 'Stop'

function Invoke-NpmScript {
  param(
    [string]$WorkingDirectory,
    [string[]]$Arguments
  )

  Push-Location $WorkingDirectory
  try {
    & npm @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "npm $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
  }
  finally {
    Pop-Location
  }
}

function Clear-InstallDirectoryExceptUninstaller {
  param(
    [string]$InstallDirectory
  )

  if (-not (Test-Path -LiteralPath $InstallDirectory)) {
    New-Item -ItemType Directory -Path $InstallDirectory | Out-Null
    return
  }

  Get-ChildItem -LiteralPath $InstallDirectory -Force |
    Where-Object { $_.Name -ne 'Uninstall Awakened PoE Trade.exe' } |
    Remove-Item -Recurse -Force
}

function Copy-UnpackedBuild {
  param(
    [string]$SourceDirectory,
    [string]$InstallDirectory
  )

  if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "Unpacked build directory not found: $SourceDirectory"
  }

  Clear-InstallDirectoryExceptUninstaller $InstallDirectory
  Get-ChildItem -LiteralPath $SourceDirectory -Force |
    Copy-Item -Destination $InstallDirectory -Recurse -Force
}

function Select-BuildOutputAction {
  param(
    [string]$DistDirectory,
    [string]$InstallerPath
  )

  $options = @(
    [pscustomobject]@{ Key = '1'; Label = 'Copy output to "%localappdata%\Programs\Awakened PoE Trade"' }
    [pscustomobject]@{ Key = '2'; Label = 'Copy output to "%programfiles%\Awakened PoE Trade"' }
    [pscustomobject]@{ Key = '3'; Label = "Run installer (`"$InstallerPath`")" }
    [pscustomobject]@{ Key = 'q'; Label = 'Close this script and do nothing else' }
  )
  $selectedIndex = 0
  Write-Host ''
  $menuLines = @("Build completed under `"$DistDirectory`", would you like to:")
  $menuLines += $options | ForEach-Object { "  $($_.Key)) $($_.Label)" }
  $consoleWidth = $Host.UI.RawUI.WindowSize.Width
  $menuHeight = 0
  foreach ($line in $menuLines) {
    $menuHeight += [Math]::Max(1, [Math]::Ceiling(($line.Length + 1) / $consoleWidth))
  }
  $escape = [char]27
  $hasRenderedMenu = $false

  while ($true) {
    if ($hasRenderedMenu) {
      Write-Host -NoNewline "${escape}[${menuHeight}F${escape}[0J"
    }

    Write-Host "Build completed under `"$DistDirectory`", would you like to:"

    for ($index = 0; $index -lt $options.Count; $index++) {
      $selectionMarker = if ($index -eq $selectedIndex) { '> ' } else { '  ' }
      Write-Host "$selectionMarker$($options[$index].Key)) $($options[$index].Label)"
    }
    $hasRenderedMenu = $true

    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    switch ($key.VirtualKeyCode) {
      38 { $selectedIndex = ($selectedIndex - 1 + $options.Count) % $options.Count; continue }
      40 { $selectedIndex = ($selectedIndex + 1) % $options.Count; continue }
      13 { return $options[$selectedIndex].Key }
    }

    $pressedKey = $key.Character.ToString().ToLowerInvariant()
    if ($pressedKey -in $options.Key) {
      return $pressedKey
    }
  }
}

$root = $PSScriptRoot
$renderer = Join-Path $root 'renderer'
$main = Join-Path $root 'main'
$dist = Join-Path $main 'dist'
$unpackedBuild = Join-Path $dist 'win-unpacked'
$localInstallDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Awakened PoE Trade'
$programFilesInstallDirectory = Join-Path $env:ProgramFiles 'Awakened PoE Trade'
$installCommand = if ($CleanInstall) { @('ci') } else { @('install') }

try {
  if (-not $SkipBuild) {
    if (Test-Path -LiteralPath $dist) {
      Remove-Item -LiteralPath $dist -Recurse -Force
    }

    if (-not $SkipInstall) {
      Invoke-NpmScript $renderer $installCommand
    }

    Invoke-NpmScript $renderer @('run', 'make-index-files')

    if (-not $SkipLint) {
      Invoke-NpmScript $renderer @('run', 'lint')
    }

    Invoke-NpmScript $renderer @('run', 'build')

    if (-not $SkipInstall) {
      Invoke-NpmScript $main $installCommand
    }

    Invoke-NpmScript $main @('run', 'build')
    Invoke-NpmScript $main @('run', 'package', '--', '--publish', 'never')
  }

  $installer = Get-ChildItem -LiteralPath $dist -Filter '* Setup *.exe' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  $installerPath = if ($null -eq $installer) { '<installer not found>' } else { $installer.FullName }
  $choice = Select-BuildOutputAction $dist $installerPath

  switch ($choice) {
    '1' {
      Copy-UnpackedBuild $unpackedBuild $localInstallDirectory
      Write-Host "Copied unpacked build to $localInstallDirectory."
    }
    '2' {
      Copy-UnpackedBuild $unpackedBuild $programFilesInstallDirectory
      Write-Host "Copied unpacked build to $programFilesInstallDirectory."
    }
    '3' {
    if ($null -eq $installer) {
      throw "Installer not found in $dist"
    }

    Start-Process -FilePath $installer.FullName -Wait
    }
    'q' { return }
  }
}
catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  Read-Host 'Build failed. Press Enter to close'
  exit 1
}