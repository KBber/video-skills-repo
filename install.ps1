#Requires -Version 5.1
<#
.SYNOPSIS
    视频 Skills 一键部署器（Windows / PowerShell 5.1+）。
.DESCRIPTION
    两种运行模式自动识别：
      · 本地模式  —— 本脚本同目录下存在 skills\ 与 plugins\，直接从磁盘安装
      · 远程模式  —— 本地没有（例如通过 irm ... | iex 触发），自动从 GitHub 下载仓库 zip 再安装

    安装内容：
      1) 把 skills\ 与 plugins\ 同构复制到 <DataDir>\skills\
      2) 调用 verify.ps1 按 MiniMax Code 运行时规则体检
      3) 检查 Node >= 22 / FFmpeg / Python，并为 video-use 建独立 venv 装依赖
      4) 安装 Bun >= 1.2 并激活 chengfeng-videocut Runtime

    常用参数：
      -DataDir <路径>        数据目录，默认 $env:USERPROFILE\.minimax
      -Repo <owner/name>     远程模式使用的仓库，默认见脚本内 $DefaultRepo
      -Branch <分支>         默认 main
      -SkipDeps              跳过依赖装配
      -SkipRuntime           跳过 Bun 与 Video Cut Runtime
      -SkipBun               只跳过 Bun 安装（仍尝试激活 Runtime）
      -NoVerify              跳过体检

    环境变量：
      VIDEO_SKILLS_DATA_DIR  同 -DataDir
      VIDEO_SKILLS_REPO      同 -Repo
      VIDEO_SKILLS_BRANCH    同 -Branch
      VIDEO_SKILLS_ZIP_URL   直接指定仓库 zip 地址（内网镜像 / 离线部署），优先级最高
      GITHUB_TOKEN / VIDEO_SKILLS_TOKEN  私有仓库令牌（会带上 Authorization 头）
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
.EXAMPLE
    iwr -useb https://raw.githubusercontent.com/KBber/video-skills-repo/main/install.ps1 | iex
#>
[CmdletBinding()]
param(
    [string]$DataDir = "",
    [string]$Repo = "",
    [string]$Branch = "",
    [switch]$SkipDeps,
    [switch]$SkipRuntime,
    [switch]$SkipBun,
    [switch]$NoVerify
)

$ErrorActionPreference = 'Stop'
$DefaultRepo   = 'KBber/video-skills-repo'
$DefaultBranch = 'main'

# 环境变量优先（便于 irm | iex 传参）
if (-not $DataDir) { $DataDir = $env:VIDEO_SKILLS_DATA_DIR }
if (-not $Repo)    { $Repo    = $env:VIDEO_SKILLS_REPO }
if (-not $Branch)  { $Branch  = $env:VIDEO_SKILLS_BRANCH }
if (-not $Repo)    { $Repo    = $DefaultRepo }
if (-not $Branch)  { $Branch  = $DefaultBranch }
if (-not $DataDir) { $DataDir = Join-Path $env:USERPROFILE '.minimax' }

$skillsDir = Join-Path $DataDir 'skills'
$repoRoot  = $null
$tempRoot  = $null

function Write-Step($name, $status, $detail) {
    $color = switch ($status) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } default { 'Gray' } }
    Write-Host ("[{0,-4}] {1}  {2}" -f $status, $name, $detail) -ForegroundColor $color
}

# 优先用 curl.exe 下载：PowerShell 5.1 的 HttpWebRequest 在部分网络/代理环境下
# 会 TLS 握手中断（"基础连接已经关闭"），curl 的 schannel 后端更稳。
# --retry-all-errors 需要 curl >= 7.71。
function Get-CurlExtras {
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { return $null }
    try {
        $v = (& curl.exe --version 2>$null | Select-Object -First 1)
        if ($v -match 'curl (\d+)\.(\d+)') {
            $maj = [int]$Matches[1]; $min = [int]$Matches[2]
            if ($maj -gt 7 -or ($maj -eq 7 -and $min -ge 71)) { return @('--retry', '3', '--retry-all-errors') }
        }
    }
    catch { }
    return @('--retry', '3')
}

Write-Host ""
Write-Host "=== 视频 Skills 一键部署 ===" -ForegroundColor Cyan
Write-Host "数据目录: $DataDir"
Write-Host "仓库:     $Repo ($Branch)"
Write-Host ""

# ---------- 0. 定位仓库内容（本地模式 or 远程模式） ----------
# 只有当脚本本身是一个真实文件、且同目录下同时存在 skills\ 与 manifest.json 时，
# 才算「本地模式」；`iwr ... | iex` 这种管道执行一律走远程模式。
$scriptDir = ''
try { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { }
if ($scriptDir -and (Test-Path -LiteralPath (Join-Path $scriptDir 'skills')) -and (Test-Path -LiteralPath (Join-Path $scriptDir 'manifest.json'))) {
    $repoRoot = $scriptDir
    Write-Step '获取仓库内容' 'OK' "本地模式: $repoRoot"
}
else {
    Write-Step '获取仓库内容' 'INFO' "远程模式：从 GitHub 下载 $Repo@$Branch"
    $tempRoot = Join-Path $env:TEMP ("video-skills-" + [guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    $zip = Join-Path $tempRoot 'repo.zip'
    $urls = @(
        "https://github.com/$Repo/archive/refs/heads/$Branch.zip",
        "https://codeload.github.com/$Repo/zip/refs/heads/$Branch"
    )
    # 自定义压缩包地址（内网镜像 / 离线部署 / 自测），优先级最高
    if ($env:VIDEO_SKILLS_ZIP_URL) { $urls = @($env:VIDEO_SKILLS_ZIP_URL) + $urls }

    $dlHeaders = @{}
    $token = $env:GITHUB_TOKEN
    if (-not $token) { $token = $env:VIDEO_SKILLS_TOKEN }
    if ($token) { $dlHeaders['Authorization'] = "Bearer $token" }

    $ok = $false
    $curlExtras = Get-CurlExtras
    foreach ($u in $urls) {
        for ($try = 1; $try -le 3; $try++) {
            try {
                Write-Host "  · 下载 $u （第 $try 次）" -ForegroundColor DarkGray
                if ($curlExtras) {
                    $curlArgs = @('-fsSL') + $curlExtras + @('--connect-timeout', '20', '-o', $zip)
                    if ($dlHeaders.Count -gt 0) { $curlArgs += @('-H', "Authorization: $($dlHeaders['Authorization'])") }
                    $curlArgs += $u
                    & curl.exe @curlArgs
                    if ($LASTEXITCODE -ne 0) { throw "curl 退出码 $LASTEXITCODE" }
                }
                elseif ($dlHeaders.Count -gt 0) { Invoke-WebRequest -Uri $u -OutFile $zip -TimeoutSec 300 -UseBasicParsing -Headers $dlHeaders }
                else { Invoke-WebRequest -Uri $u -OutFile $zip -TimeoutSec 300 -UseBasicParsing }
                if ((Get-Item -LiteralPath $zip).Length -gt 1000) { $ok = $true; break }
            }
            catch {
                Write-Host "    失败: $($_.Exception.Message)" -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
            }
        }
        if ($ok) { break }
    }
    if (-not $ok) {
        Write-Step '获取仓库内容' 'FAIL' "无法下载仓库 $Repo@$Branch"
        Write-Host ""
        Write-Host "若仓库是私有的，请先设置令牌再重试：" -ForegroundColor Yellow
        Write-Host "  `$env:GITHUB_TOKEN = 'ghp_xxx'   # 之后 install.ps1 会带上 Authorization 头" -ForegroundColor DarkGray
        Write-Host "  `$env:VIDEO_SKILLS_REPO = 'owner/repo'" -ForegroundColor DarkGray
        exit 1
    }
    Expand-Archive -LiteralPath $zip -DestinationPath $tempRoot -Force
    # 取解压后的仓库根：优先含 skills\ 且含 manifest.json 的那一层
    # （GitHub 的归档会多套一层 <repo>-<branch>/，镜像站可能直接是仓库根，两种都要认）
    $repoRoot = ''
    $cands = @($tempRoot) + @(Get-ChildItem -LiteralPath $tempRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($c in $cands) {
        if ((Test-Path -LiteralPath (Join-Path $c 'skills')) -and (Test-Path -LiteralPath (Join-Path $c 'manifest.json'))) { $repoRoot = $c; break }
    }
    if (-not $repoRoot) {
        foreach ($c in $cands) {
            if (Test-Path -LiteralPath (Join-Path $c 'skills')) { $repoRoot = $c; break }
        }
    }
    if (-not $repoRoot) { Write-Step '获取仓库内容' 'FAIL' '解压后未找到仓库目录'; exit 1 }
    Write-Step '获取仓库内容' 'OK' "已解压到 $repoRoot"
}

$payloadSkills  = Join-Path $repoRoot 'skills'
$payloadPlugins = Join-Path $repoRoot 'plugins'
if (-not (Test-Path -LiteralPath $payloadSkills)) {
    Write-Step '校验仓库结构' 'FAIL' "缺少 skills 目录: $payloadSkills"
    exit 1
}

# ---------- 1. 复制到目标数据目录 ----------
if (-not (Test-Path -LiteralPath $skillsDir)) { New-Item -ItemType Directory -Force -Path $skillsDir | Out-Null }
$robocopy = Get-Command robocopy -ErrorAction SilentlyContinue
foreach ($group in @(@{ Src = $payloadSkills; Name = 'skills' }, @{ Src = $payloadPlugins; Name = 'plugins' })) {
    if (-not (Test-Path -LiteralPath $group.Src)) { continue }
    foreach ($item in (Get-ChildItem -LiteralPath $group.Src -Directory)) {
        $dest = Join-Path $skillsDir $item.Name
        if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
        if ($robocopy) {
            & robocopy $item.FullName $dest /E /NFL /NDL /NJH /NJS /NP | Out-Null
            $rc = $LASTEXITCODE
            if ($rc -ge 8) { Write-Step "复制 $($item.Name)" 'FAIL' "robocopy 退出码 $rc"; continue }
        }
        else {
            Copy-Item -Path (Join-Path $item.FullName '*') -Destination $dest -Recurse -Force
        }
        $n = (Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Step "复制 $($item.Name)" 'OK' "$n 个文件 -> $dest"
    }
}

# ---------- 2. 体检 ----------
if (-not $NoVerify) {
    $v = Join-Path $repoRoot 'verify.ps1'
    if (Test-Path -LiteralPath $v) {
        & $v -DataDir $DataDir | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Step '技能体检' 'OK' '清单内技能全部就位' }
        else { Write-Step '技能体检' 'WARN' '有缺失项，运行 verify.ps1 查看详情' }
    }
}

# ---------- 3. 基础依赖 ----------
if (-not $SkipDeps) {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { Write-Step 'Node.js' 'FAIL' '未安装，HyperFrames 需要 >= 22（https://nodejs.org）' }
    else {
        $nv = (node --version).TrimStart('v'); $major = [int]($nv -split '\.')[0]
        if ($major -ge 22) { Write-Step 'Node.js' 'OK' $nv } else { Write-Step 'Node.js' 'WARN' "$nv 低于 22，HyperFrames 需升级" }
    }
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue; $fp = Get-Command ffprobe -ErrorAction SilentlyContinue
    if ($ff -and $fp) { Write-Step 'FFmpeg' 'OK' ((ffmpeg -version 2>&1 | Select-Object -First 1) -replace '\s+$','') }
    else { Write-Step 'FFmpeg' 'FAIL' '未找到 ffmpeg / ffprobe，视频处理必需（winget install Gyan.FFmpeg）' }

    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { Write-Step 'Python' 'FAIL' '未安装，video-use 需要 >= 3.10' }
    else {
        $vu = Join-Path $skillsDir 'video-use'
        $venvPy = Join-Path $vu '.venv\Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $venvPy)) {
            Write-Host '  · 为 video-use 创建虚拟环境（首次约 1-3 分钟）...' -ForegroundColor DarkGray
            & python -m venv (Join-Path $vu '.venv')
        }
        if (Test-Path -LiteralPath $venvPy) {
            & $venvPy -m pip install --quiet --upgrade pip 2>&1 | Out-Null
            & $venvPy -m pip install --quiet -e $vu 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                & $venvPy -c "import requests,numpy,librosa,matplotlib,PIL" 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Write-Step 'video-use 依赖' 'OK' "venv: $venvPy" }
                else { Write-Step 'video-use 依赖' 'WARN' '部分依赖导入失败，可稍后手动 pip install -e' }
            }
            else { Write-Step 'video-use 依赖' 'FAIL' "pip install -e 失败，退出码 $LASTEXITCODE" }
        }
        else { Write-Step 'video-use 依赖' 'FAIL' 'venv 创建失败' }
    }
}

# ---------- 4. Bun + Video Cut Runtime ----------
if (-not $SkipRuntime -and -not $SkipBun) {
    $bunExe = Join-Path $bunDir 'bun.exe'
    if (-not (Test-Path -LiteralPath $bunExe)) {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if ($winget) {
            Write-Host '  · 通过 winget 安装 Bun ...' -ForegroundColor DarkGray
            & winget install --id Oven-sh.Bun -e --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-Null
        }
        if (-not (Test-Path -LiteralPath $bunExe)) {
            $npm = Get-Command npm -ErrorAction SilentlyContinue
            if ($npm) {
                Write-Host '  · 通过 npm 官方平台包安装 Bun ...' -ForegroundColor DarkGray
                & npm install -g @oven/bun-windows-x64 2>&1 | Out-Null
                $root = (& npm root -g 2>&1 | Select-Object -First 1)
                $cand = Join-Path $root '@oven\bun-windows-x64\bin\bun.exe'
                if (Test-Path -LiteralPath $cand) {
                    New-Item -ItemType Directory -Force -Path $bunDir | Out-Null
                    Copy-Item -LiteralPath $cand -Destination $bunExe -Force
                }
            }
        }
        if (-not (Test-Path -LiteralPath $bunExe)) {
            $ver = '1.4.4'
            $url = "https://github.com/oven-sh/bun/releases/download/bun-v$ver/bun-windows-x64.zip"
            $zip2 = Join-Path $env:TEMP 'bun-windows-x64.zip'
            Write-Host "  · 从 GitHub Release 下载 Bun $ver ..." -ForegroundColor DarkGray
            try {
                Invoke-WebRequest -Uri $url -OutFile $zip2 -TimeoutSec 300 -UseBasicParsing
                $stage = Join-Path $env:TEMP 'bun-stage'
                if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
                Expand-Archive -LiteralPath $zip2 -DestinationPath $stage -Force
                $found = Get-ChildItem -LiteralPath $stage -Recurse -Filter 'bun.exe' | Select-Object -First 1
                if ($found) {
                    New-Item -ItemType Directory -Force -Path $bunDir | Out-Null
                    Copy-Item -LiteralPath $found.FullName -Destination $bunExe -Force
                }
            }
            catch { Write-Step 'Bun' 'FAIL' "下载失败: $($_.Exception.Message)" }
        }
        if (Test-Path -LiteralPath $bunExe) {
            $userPath = [Environment]::GetEnvironmentVariable('Path','User')
            if ($null -eq $userPath) { $userPath = '' }
            if ($userPath -notlike "*$bunDir*") {
                [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $bunDir).TrimStart(';'), 'User')
            }
            if ($env:Path -notlike "*$bunDir*") { $env:Path = $env:Path + ';' + $bunDir }
            Write-Step 'Bun' 'OK' "$((& $bunExe --version 2>&1 | Select-Object -First 1)) -> $bunExe"
        }
        else { Write-Step 'Bun' 'FAIL' '未能安装 Bun，Video Cut Runtime 将无法激活' }
    }
    else {
        Write-Step 'Bun' 'OK' "$((& $bunExe --version 2>&1 | Select-Object -First 1)) -> $bunExe"
    }
}

$bunDir = Join-Path $env:USERPROFILE '.bun\bin'
$pluginRoot = Join-Path $skillsDir 'chengfeng-videocut'
$ensure = Join-Path $pluginRoot 'scripts\ensure-runtime.cjs'
if (-not $SkipRuntime) {
    if (Test-Path -LiteralPath $ensure) {
        if ($env:Path -notlike "*$bunDir*") { $env:Path = $env:Path + ';' + $bunDir }
        Write-Host '  · 激活 chengfeng-videocut Runtime ...' -ForegroundColor DarkGray
        $out = & node $ensure --install-if-missing --json 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Step 'Video Cut Runtime' 'OK' '已安装并激活' }
        else { Write-Step 'Video Cut Runtime' 'FAIL' (($out | Select-Object -Last 1) | Out-String).Trim() }
    }
    else { Write-Step 'Video Cut Runtime' 'FAIL' "找不到 $ensure" }
}

# ---------- 5. 收尾 ----------
if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "完成。下一步：" -ForegroundColor Cyan
Write-Host "  1. 重开一个会话 —— 技能目录在会话启动时扫描，新装技能才可调用"
Write-Host "  2. 配密钥：video-use 需要 ELEVENLABS_API_KEY（写入 skills\video-use\.env）"
Write-Host "             videocut 需要火山引擎 key：node '<插件根>\scripts\videocut-cli.cjs' config set transcription.apiKey <key>"
Write-Host "  3. 随时体检：powershell -ExecutionPolicy Bypass -File verify.ps1"
Write-Host ""
exit 0
