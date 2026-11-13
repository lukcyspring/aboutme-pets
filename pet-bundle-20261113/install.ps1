# install.ps1 -- 把三个桌宠动作包装进本机的 DSH 宠物目录
#
# 目标目录默认是 %USERPROFILE%\.dsh\dsh-pet\pet
# （如果设了 DSH_HOME 环境变量，就跟着走 %DSH_HOME%\dsh-pet\pet）
# 想装到别处：powershell -File install.ps1 -Target "D:\某个目录"
#
# 只做复制，不删任何东西；同名文件会被覆盖。

param(
    [string]$Target,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$packDir = Join-Path $here 'pet-packs'

if (-not (Test-Path $packDir)) {
    Write-Host "找不到 pet-packs 目录，别单独移动这个脚本。" -ForegroundColor Red
    exit 1
}

if (-not $Target) {
    if ($env:DSH_HOME) {
        $Target = Join-Path $env:DSH_HOME 'dsh-pet\pet'
    }
    else {
        $Target = Join-Path $env:USERPROFILE '.dsh\dsh-pet\pet'
    }
}
$Target = $Target.TrimEnd('\')

# ---------- 清点要装的东西 ----------
$packs = @()
foreach ($d in (Get-ChildItem $packDir -Directory | Sort-Object Name)) {
    $root = $d.Name
    $cfg = Join-Path $d.FullName "$root-config.json"
    $anim = Join-Path $d.FullName "$root-animation"
    $avatar = Join-Path $d.FullName "$root-avatar.webp"
    $memes = Join-Path $d.FullName "$root-memes"
    if (-not (Test-Path $cfg) -or -not (Test-Path $anim)) {
        Write-Host ("跳过 {0}：配置或动画目录不全" -f $root) -ForegroundColor Yellow
        continue
    }
    $files = @(Get-ChildItem $anim -File)
    $memeFiles = @()
    if (Test-Path $memes) { $memeFiles = @(Get-ChildItem $memes -File -Filter *.png) }
    $all = $files + $memeFiles
    $mb = [math]::Round((($all | Measure-Object Length -Sum).Sum) / 1MB, 1)
    $name = $root
    try {
        $j = Get-Content $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($j.pets -and @($j.pets).Count -gt 0 -and $j.pets[0].name) { $name = $j.pets[0].name }
    }
    catch { }
    $packs += [pscustomobject]@{
        Root   = $root
        Name   = $name
        Cfg    = $cfg
        Anim   = $anim
        Avatar = $avatar
        Memes  = $memes
        Count  = $files.Count
        MemeN  = $memeFiles.Count
        MB     = $mb
    }
}

if ($packs.Count -eq 0) {
    Write-Host "pet-packs 里没有可安装的角色包。" -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '准备装到：' -NoNewline
Write-Host $Target -ForegroundColor Cyan
Write-Host ''
foreach ($p in $packs) {
    $mark = ''
    if (Test-Path (Join-Path $Target "$($p.Root)-config.json")) { $mark = '  （本机已有同名的，会被覆盖）' }
    Write-Host ("  {0,-8} {1,-14} {2,4} 段  {3,2} 张配图  {4,6} MB{5}" -f $p.Root, $p.Name, $p.Count, $p.MemeN, $p.MB, $mark)
}
$total = [math]::Round((($packs | Measure-Object MB -Sum).Sum), 1)
Write-Host ("  合计 {0} 段动画，{1} 张碎碎念配图，{2} MB" -f (($packs | Measure-Object Count -Sum).Sum), (($packs | Measure-Object MemeN -Sum).Sum), $total)
Write-Host ''

if (-not $Force) {
    $ok = Read-Host '现在装进去？[y/N]'
    if ($ok -notmatch '^(y|Y|yes|是)$') {
        Write-Host '没动任何文件。'
        exit 0
    }
}

# ---------- 复制 ----------
New-Item -ItemType Directory -Force -Path $Target | Out-Null
foreach ($p in $packs) {
    Write-Host ("装 {0} ..." -f $p.Root) -NoNewline
    $t0 = Get-Date
    Copy-Item $p.Cfg (Join-Path $Target "$($p.Root)-config.json") -Force
    if (Test-Path $p.Avatar) { Copy-Item $p.Avatar (Join-Path $Target "$($p.Root)-avatar.webp") -Force }
    $dstAnim = Join-Path $Target "$($p.Root)-animation"
    New-Item -ItemType Directory -Force -Path $dstAnim | Out-Null
    $n = 0
    foreach ($f in (Get-ChildItem $p.Anim -File)) {
        Copy-Item $f.FullName (Join-Path $dstAnim $f.Name) -Force
        $n++
    }
    $nm = 0
    if ($p.MemeN -gt 0) {
        $dstMemes = Join-Path $Target "$($p.Root)-memes"
        New-Item -ItemType Directory -Force -Path $dstMemes | Out-Null
        foreach ($f in (Get-ChildItem $p.Memes -File -Filter *.png)) {
            Copy-Item $f.FullName (Join-Path $dstMemes $f.Name) -Force
            $nm++
        }
    }
    Write-Host ("  {0} 个动画 + {1} 张配图，{2:N0} 秒" -f $n, $nm, ((Get-Date) - $t0).TotalSeconds) -ForegroundColor Green
}

Write-Host ''
Write-Host '装完了。' -ForegroundColor Green
Write-Host ''
Write-Host '接下来：'
Write-Host '  1. 回到 DSH 的宠物设置页，看「种类」里是不是多了 猫耳娘 / GPT 动作包 / Claude 动作包'
Write-Host '     （插件每次读配置，通常不用重启 DSH；没有就重启一次）'
Write-Host '  2. 想同时控制全部宠物：进 pet-sync 目录，双击 一起做动作.cmd'
Write-Host ''
Write-Host '卸载：删掉 pet 目录下的 <名字>-config.json、<名字>-animation 文件夹、<名字>-avatar.webp、<名字>-memes 文件夹四样即可。'
Write-Host ("当前 pet 目录：{0}" -f $Target) -ForegroundColor DarkGray
Write-Host ''
