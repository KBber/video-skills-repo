#Requires -Version 5.1
<#
.SYNOPSIS
    卸载本合集安装的技能目录。
.DESCRIPTION
    只删除 manifest.json 中列出的顶层目录（installedPath 的第一段），不会碰 dataDir 下的其它内容。
    Video Cut 的 7 个技能共用顶层目录 chengfeng-videocut，会整块删除（含 scripts/、references/）。
    默认需要确认；加 -Force 跳过确认。
#>
[CmdletBinding()]
param(
    [string]$DataDir = "",
    [switch]$Force,
    [switch]$KeepRuntime
)

$ErrorActionPreference = 'Stop'
$scriptDir = ''
try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { }

if (-not $DataDir) { $DataDir = $env:VIDEO_SKILLS_DATA_DIR }
if (-not $DataDir) { $DataDir = Join-Path $env:USERPROFILE '.minimax' }
$skillsDir = Join-Path $DataDir 'skills'

$manifestPath = Join-Path $scriptDir 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Write-Host "找不到 manifest.json，无法确定要卸载的内容。" -ForegroundColor Red
    exit 1
}
$m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# 每个技能的 installedPath 第一段 = 该技能独占的顶层目录
$targets = @()
foreach ($g in $m.groups) {
    foreach ($s in $g.skills) {
        $rel = ($s.installedPath -replace '/', '\').Trim('\')
        if (-not $rel) { continue }
        $top = ($rel -split '\\')[0]
        if ($top) { $targets += (Join-Path $skillsDir $top) }
    }
}
$targets = @($targets | Sort-Object -Unique)

Write-Host ""
Write-Host "将删除以下顶层目录（位于 $skillsDir 下）：" -ForegroundColor Cyan
foreach ($t in $targets) {
    $n = 0
    if (Test-Path -LiteralPath $t) { $n = @(Get-ChildItem -LiteralPath $t -Recurse -File -ErrorAction SilentlyContinue).Count }
    Write-Host ("  {0}  ({1} 个文件)" -f $t, $n) -ForegroundColor DarkGray
}
Write-Host ""

if (-not $Force) {
    $ans = Read-Host "确认删除？输入 yes 继续"
    if ($ans -ne 'yes') { Write-Host "已取消。" -ForegroundColor Yellow; exit 0 }
}

foreach ($t in $targets) {
    if (Test-Path -LiteralPath $t) {
        try {
            Remove-Item -LiteralPath $t -Recurse -Force
            Write-Host "已删除 $t" -ForegroundColor Green
        }
        catch { Write-Host "删除失败 $t : $($_.Exception.Message)" -ForegroundColor Red }
    }
}

if (-not $KeepRuntime) {
    $rt = Join-Path $env:USERPROFILE '.chengfeng-videocut'
    if (Test-Path -LiteralPath $rt) {
        Write-Host ""
        Write-Host "Video Cut Runtime 仍保留在 $rt" -ForegroundColor Yellow
        Write-Host "如需一并删除：Remove-Item -LiteralPath '$rt' -Recurse -Force" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "卸载完成。重开一个会话后技能列表会刷新。" -ForegroundColor Cyan
exit 0
