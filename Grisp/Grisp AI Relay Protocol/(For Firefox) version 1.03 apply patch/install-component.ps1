param(
    [Parameter(Mandatory = $true)]
    [string]$FirefoxRoot
)

$ErrorActionPreference = "Stop"
$source = Join-Path $PSScriptRoot "browser\components\aistarter"
$target = Join-Path $FirefoxRoot "browser\components\aistarter"

if (-not (Test-Path (Join-Path $FirefoxRoot "mach"))) {
    throw "FirefoxRoot does not appear to be a Firefox source checkout: $FirefoxRoot"
}

if (Test-Path $target) {
    Write-Host "Target already exists: $target"
    Write-Host "Rename or remove the old aistarter directory before installing this GARP/1.01 implementation."
    exit 2
}

New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
Copy-Item -Path $source -Destination $target -Recurse -Force
Write-Host "Installed GARP/1.01 Firefox component to: $target"
Write-Host "Manual integration is still required for browser/components/moz.build, BrowserGlue.sys.mjs, and DesktopActorRegistry.sys.mjs."
