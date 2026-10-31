#Requires -Version 5.1
<#
.SYNOPSIS
    视频 Skills 体检：按 MiniMax Code 运行时的 skill 发现规则扫描技能目录。
.DESCRIPTION
    复刻运行时 loadSkillsFromDir 规则：
      - 目录内含 SKILL.md → 视为 skill 根，不再递归
      - 否则递归子目录查找 SKILL.md
      - 跳过点目录与 node_modules
      - 仅顶层目录的直接 .md 子文件会被当作 skill
    并用 manifest.json 比对缺失项与落地路径。
#>
[CmdletBinding()]
param(
    [string]$DataDir = "",
    [switch]$Json,
    [switch]$SkipManifest
)

$ErrorActionPreference = 'Stop'
$scriptDir = ''
try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { }

if (-not $DataDir) { $DataDir = $env:VIDEO_SKILLS_DATA_DIR }
if (-not $DataDir) { $DataDir = Join-Path $env:USERPROFILE '.minimax' }
$skillsDir = Join-Path $DataDir 'skills'

function Read-SkillMeta([string]$path) {
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($raw -notmatch '(?s)^---[ \t]*\r?\n(.*?)\r?\n---') { return $null }
    $meta = [ordered]@{}
    foreach ($line in (($Matches[1]) -split "`r?`n")) {
        if ($line -match '^([A-Za-z0-9_.-]+):[ \t]*(.*)$') {
            $key = $Matches[1]; $val = $Matches[2].Trim()
            if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
                $val = $val.Substring(1, $val.Length - 2)
            }
            $meta[$key] = $val
        }
    }
    return $meta
}

function Test-SkillName([string]$name) {
    $errs = @()
    if ($name.Length -gt 64) { $errs += "名称超长($($name.Length))" }
    if ($name -notmatch '^[a-z0-9-]+$') { $errs += "含非法字符(仅允许小写字母/数字/连字符)" }
    if ($name.StartsWith('-') -or $name.EndsWith('-')) { $errs += "首尾是连字符" }
    if ($name.Contains('--')) { $errs += "含连续连字符" }
    return $errs
}

$found = New-Object System.Collections.Generic.List[object]

function Find-Skills([string]$dir, [bool]$isTop) {
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $entries = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)
    $skillFile = $entries | Where-Object { $_.Name -eq 'SKILL.md' -and -not $_.PSIsContainer } | Select-Object -First 1
    if ($skillFile) {
        $meta = Read-SkillMeta $skillFile.FullName
        if ($meta -and $meta.Contains('description') -and -not [string]::IsNullOrWhiteSpace($meta['description'])) {
            $name = if ($meta.Contains('name') -and $meta['name']) { $meta['name'] } else { Split-Path $skillFile.DirectoryName -Leaf }
            $found.Add([pscustomobject]@{
                Name = $name; Description = $meta['description']; Path = $skillFile.FullName
                Warnings = (Test-SkillName $name)
            })
        }
        return
    }
    foreach ($e in $entries) {
        if ($e.Name.StartsWith('.')) { continue }
        if ($e.Name -eq 'node_modules') { continue }
        if ($e.PSIsContainer) { Find-Skills $e.FullName $false }
        elseif ($isTop -and $e.Name -like '*.md') {
            $meta = Read-SkillMeta $e.FullName
            if ($meta -and $meta.Contains('description') -and -not [string]::IsNullOrWhiteSpace($meta['description'])) {
                $name = if ($meta.Contains('name') -and $meta['name']) { $meta['name'] } else { [IO.Path]::GetFileNameWithoutExtension($e.Name) }
                $found.Add([pscustomobject]@{
                    Name = $name; Description = $meta['description']; Path = $e.FullName
                    Warnings = (Test-SkillName $name)
                })
            }
        }
    }
}

Find-Skills $skillsDir $true
$found = @($found | Sort-Object Name)

$expected = @(); $missing = @(); $pathMissing = @()
if (-not $SkipManifest -and $scriptDir) {
    $manifestPath = Join-Path $scriptDir 'manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        $m = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $expected = @($m.groups | ForEach-Object { $_.skills } | ForEach-Object { $_.name })
        $have = @($found | ForEach-Object { $_.Name })
        $missing = @($expected | Where-Object { $have -notcontains $_ })
        foreach ($g in $m.groups) {
            foreach ($s in $g.skills) {
                $p = Join-Path $skillsDir $s.installedPath
                if (-not (Test-Path -LiteralPath $p)) { $pathMissing += "$($s.name) -> $p" }
            }
        }
    }
}
$dups = @($found | Group-Object Name | Where-Object { $_.Count -gt 1 })

if ($Json) {
    [pscustomobject]@{
        skillsDir = $skillsDir; count = $found.Count; skills = $found
        expected = $expected; missing = $missing; pathsMissing = $pathMissing
        duplicates = @($dups | ForEach-Object { $_.Name })
    } | ConvertTo-Json -Depth 5
    exit 0
}

Write-Host ""
Write-Host "技能目录: $skillsDir" -ForegroundColor Cyan
Write-Host "发现技能: $($found.Count) 个" -ForegroundColor Cyan
if ($expected.Count -gt 0) {
    if ($missing.Count -eq 0) { Write-Host "清单比对: $($expected.Count)/$($expected.Count) 全部就位" -ForegroundColor Green }
    else { Write-Host "清单比对: 缺少 $($missing.Count) 个 -> $($missing -join ', ')" -ForegroundColor Yellow }
}
if ($pathMissing.Count -gt 0) {
    Write-Host "落地路径缺失 $($pathMissing.Count) 处:" -ForegroundColor Yellow
    $pathMissing | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
}
if ($dups.Count -gt 0) { Write-Host "重名警告: $(($dups | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Yellow }
Write-Host ""
$found | ForEach-Object {
    $flag = if ($_.Warnings.Count -gt 0) { " [$($_.Warnings -join '; ')]" } else { '' }
    Write-Host ("  {0}{1}" -f $_.Name, $flag) -ForegroundColor Green
    Write-Host ("    {0}" -f $_.Path) -ForegroundColor DarkGray
}
Write-Host ""
if ($missing.Count -gt 0 -or $pathMissing.Count -gt 0) { exit 1 } else { exit 0 }
