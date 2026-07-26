param(
  [switch]$SkipInstall = $true,
  [switch]$CleanInstall = $false,
  [switch]$SkipLint = $false
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

$root = $PSScriptRoot
$renderer = Join-Path $root 'renderer'
$main = Join-Path $root 'main'
$installCommand = if ($CleanInstall) { @('ci') } else { @('install') }

try {
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

  Write-Host "Build complete. Packages are in $main\dist."
}
catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  Read-Host 'Build failed. Press Enter to close'
  exit 1
}