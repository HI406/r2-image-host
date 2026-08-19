<#
.SYNOPSIS
    R2 Image Host 一键部署脚本
.DESCRIPTION
    Load credentials from .env, set Cloudflare Secret, deploy Worker, and optionally push to GitHub.
.PARAMETER SkipSecret
    Skip setting APP_PASSWORD Secret (use when already configured)
.PARAMETER PushGit
    Auto commit and push to GitHub after deployment
.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -SkipSecret -PushGit
#>
param(
    [switch]$SkipSecret,
    [switch]$PushGit
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$NL = "`n"

function Write-Step([string]$msg) {
    Write-Host ($NL + "==> " + $msg) -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host ("    OK  " + $msg) -ForegroundColor Green
}

function Write-Fail([string]$msg) {
    Write-Host ("    FAIL  " + $msg) -ForegroundColor Red
    exit 1
}

function Get-GitExe {
    $gitInPath = Get-Command git -ErrorAction SilentlyContinue
    if ($gitInPath) { return $gitInPath.Source }
    $localGit = "C:\Program Files\Git\cmd\git.exe"
    if (Test-Path $localGit) { return $localGit }
    Write-Fail "Git not found. Please install Git or add it to PATH."
}

# ============================================================
# 1. Load .env
# ============================================================

Write-Step "Loading .env"

$envFile = Join-Path $scriptDir ".env"
if (!(Test-Path $envFile)) {
    Write-Fail ".env file not found. Create it with cloudflare_api_token and app_secret."
}

$envVars = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and !$line.StartsWith("#") -and $line.Contains("=")) {
        $parts = $line.Split("=", 2)
        $envVars[$parts[0].Trim()] = $parts[1].Trim()
    }
}

$apiToken = $envVars["cloudflare_api_token"]
$appSecret = $envVars["app_secret"]

if (!$apiToken) { Write-Fail ".env missing cloudflare_api_token" }
if (!$appSecret) { Write-Fail ".env missing app_secret" }

$env:CLOUDFLARE_API_TOKEN = $apiToken
Write-Ok "API Token loaded"

# ============================================================
# 2. Install dependencies
# ============================================================

Write-Step "Checking npm dependencies"

$nodeModules = Join-Path $scriptDir "node_modules"
if (!(Test-Path $nodeModules)) {
    Write-Host "    Installing..." -ForegroundColor Yellow
    npm install --silent
    if ($LASTEXITCODE -ne 0) { Write-Fail "npm install failed" }
}
Write-Ok "Dependencies ready"

# ============================================================
# 3. Set APP_PASSWORD Secret
# ============================================================

if (!$SkipSecret) {
    Write-Step "Setting APP_PASSWORD Secret"
    $appSecret | npx wrangler secret put APP_PASSWORD
    if ($LASTEXITCODE -ne 0) { Write-Fail "Failed to set Secret" }
    Write-Ok "APP_PASSWORD Secret updated"
} else {
    Write-Step "Skipping Secret setup (-SkipSecret)"
}

# ============================================================
# 4. Deploy Worker
# ============================================================

Write-Step "Deploying Worker to Cloudflare"

npx wrangler deploy
if ($LASTEXITCODE -ne 0) { Write-Fail "wrangler deploy failed" }
Write-Ok "Deployment complete"

# ============================================================
# 5. Git commit and push (optional)
# ============================================================

if ($PushGit) {
    Write-Step "Git commit and push"

    $gitExe = Get-GitExe

    $status = & $gitExe status --porcelain
    if ($status) {
        & $gitExe add -A
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
        & $gitExe commit -m ("deploy: " + $ts)
        if ($LASTEXITCODE -ne 0) { Write-Fail "git commit failed" }
        Write-Ok "Committed"
    } else {
        Write-Host "    No changes, skipping commit" -ForegroundColor Yellow
    }

    & $gitExe push origin master
    if ($LASTEXITCODE -ne 0) { Write-Fail "git push failed" }
    Write-Ok "Pushed to GitHub"
}

# ============================================================
# Done
# ============================================================

$border = "============================================"
Write-Host ""
Write-Host $border -ForegroundColor Green
Write-Host "  Deploy complete!" -ForegroundColor Green
Write-Host "  Worker: https://r2-image-host.wqy214.workers.dev" -ForegroundColor Green
Write-Host "  Domain: https://image.surl.vip" -ForegroundColor Green
Write-Host $border -ForegroundColor Green
Write-Host ""
