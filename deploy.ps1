<#
.SYNOPSIS
    R2 Image Host 一键部署脚本
.DESCRIPTION
    从 .env 加载凭证，设置 Cloudflare Secret，部署 Worker，并可选推送到 GitHub。
.PARAMETER SkipSecret
    跳过设置 APP_PASSWORD Secret（已设置过时使用）
.PARAMETER PushGit
    部署完成后自动提交并推送到 GitHub
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

# ============================================================
# 工具函数
# ============================================================

function Write-Step($msg) {
    Write-Host "`n==> $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "    OK  $msg" -ForegroundColor Green
}

function Write-Fail($msg) {
    Write-Host "    FAIL  $msg" -ForegroundColor Red
    exit 1
}

# 获取 Git 可执行文件路径（兼容 PATH 未配置的情况）
function Get-GitExe {
    $gitInPath = Get-Command git -ErrorAction SilentlyContinue
    if ($gitInPath) { return $gitInPath.Source }

    $localGit = "C:\Program Files\Git\cmd\git.exe"
    if (Test-Path $localGit) { return $localGit }

    Write-Fail "未找到 git，请安装 Git 或将其添加到 PATH"
}

# ============================================================
# 1. 加载 .env
# ============================================================

Write-Step "加载 .env 配置"

$envFile = Join-Path $scriptDir ".env"
if (!(Test-Path $envFile)) {
    Write-Fail ".env 文件不存在，请先创建并填入 cloudflare_api_token 和 app_secret"
}

$envVars = @{}
Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and !$line.StartsWith("#") -and $line.Contains("=")) {
        $key, $value = $line.Split("=", 2)
        $envVars[$key.Trim()] = $value.Trim()
    }
}

$apiToken = $envVars["cloudflare_api_token"]
$appSecret = $envVars["app_secret"]

if (!$apiToken) { Write-Fail ".env 中缺少 cloudflare_api_token" }
if (!$appSecret) { Write-Fail ".env 中缺少 app_secret" }

$env:CLOUDFLARE_API_TOKEN = $apiToken
Write-Ok "API Token 已加载"

# ============================================================
# 2. 安装依赖
# ============================================================

Write-Step "检查 npm 依赖"

$nodeModules = Join-Path $scriptDir "node_modules"
if (!(Test-Path $nodeModules)) {
    Write-Host "    安装中..." -ForegroundColor Yellow
    npm install --silent
    if ($LASTEXITCODE -ne 0) { Write-Fail "npm install 失败" }
}
Write-Ok "依赖已就绪"

# ============================================================
# 3. 设置 APP_PASSWORD Secret
# ============================================================

if (!$SkipSecret) {
    Write-Step "设置 APP_PASSWORD Secret"
    $appSecret | npx wrangler secret put APP_PASSWORD
    if ($LASTEXITCODE -ne 0) { Write-Fail "设置 Secret 失败" }
    Write-Ok "APP_PASSWORD Secret 已更新"
} else {
    Write-Step "跳过 Secret 设置（-SkipSecret）"
}

# ============================================================
# 4. 部署 Worker
# ============================================================

Write-Step "部署 Worker 到 Cloudflare"

npx wrangler deploy
if ($LASTEXITCODE -ne 0) { Write-Fail "wrangler deploy 失败" }
Write-Ok "部署完成"

# ============================================================
# 5. Git 提交与推送（可选）
# ============================================================

if ($PushGit) {
    Write-Step "Git 提交并推送"

    $gitExe = Get-GitExe

    # 检查是否有变更
    $status = & $gitExe status --porcelain
    if ($status) {
        & $gitExe add -A
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm"
        & $gitExe commit -m "deploy: $timestamp 自动部署提交"
        if ($LASTEXITCODE -ne 0) { Write-Fail "git commit 失败" }
        Write-Ok "已提交"
    } else {
        Write-Host "    无变更，跳过提交" -ForegroundColor Yellow
    }

    & $gitExe push origin master
    if ($LASTEXITCODE -ne 0) { Write-Fail "git push 失败" }
    Write-Ok "已推送到 GitHub"
}

# ============================================================
# 完成
# ============================================================

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  部署完成！" -ForegroundColor Green
Write-Host "  Worker: https://r2-image-host.wqy214.workers.dev" -ForegroundColor Green
Write-Host "  域名:   https://image.surl.vip" -ForegroundColor Green
Write-Host "============================================`n" -ForegroundColor Green
