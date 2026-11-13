# petsync.ps1 -- 让所有桌宠同时做同一个动作
#
# 走插件自己的点播接口 POST /dsh-pet-7340/anim?pet=<id>&surface=any，
# 和右键「动作」菜单是同一个处理函数，所以不存在“脚本能点、界面不认”的偏差。
#
# 用法（在 cmd 里）：
#   powershell -File petsync.ps1 list
#   powershell -File petsync.ps1 舞狮头
#   powershell -File petsync.ps1 舞狮头 --loop
#   powershell -File petsync.ps1 舞狮头 --repeat 5 --interval 3000
#   powershell -File petsync.ps1 吃 --loop --random
#   powershell -File petsync.ps1 舞狮头 --only main,claude1
#   powershell -File petsync.ps1 舞狮头 --facing right
#
# 只用 PowerShell 5.1 自带的东西，不依赖 node / 第三方模块。

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cacheFile = Join-Path $here '.base.txt'

# ---------- 解析参数：位置参数是动作名，--key value 是选项 ----------
$Action = $null
$opt = @{}
$argv = @($args)
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if ($a -like '--*') {
        $k = $a.Substring(2).ToLower()
        $v = 'true'
        if ($i + 1 -lt $argv.Count -and -not ([string]$argv[$i + 1]).StartsWith('--')) {
            $v = [string]$argv[$i + 1]
            $i++
        }
        $opt[$k] = $v
    }
    else {
        if (-not $Action) { $Action = $a }
    }
}
if (-not $Action) { $Action = 'menu' }

$OnlyPets = $opt['only']
$Facing = $opt['facing']
$Loop = $opt.ContainsKey('loop')
$Random = $opt.ContainsKey('random')
$Repeat = 0
if ($opt.ContainsKey('repeat')) { [void][int]::TryParse($opt['repeat'], [ref]$Repeat) }
$Interval = 10000
if ($opt.ContainsKey('interval')) {
    $tmp = 0
    if ([int]::TryParse($opt['interval'], [ref]$tmp) -and $tmp -ge 200) { $Interval = $tmp }
}

# ---------- 找宿主地址 ----------
function Test-Base([string]$u) {
    try {
        $c = Invoke-RestMethod -Uri "$u/dsh-pet-7340/config" -TimeoutSec 2
    }
    catch { return $false }
    if (-not $c) { return $false }
    foreach ($p in $c.PSObject.Properties) {
        if (@($p.Value.pets).Count -gt 0) { return $true }
    }
    return $false
}

function Test-Port([int]$port) {
    $c = New-Object Net.Sockets.TcpClient
    try {
        $ar = $c.BeginConnect('127.0.0.1', $port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(150)
        if ($ok) { $c.EndConnect($ar) }
        return $ok
    }
    catch { return $false }
    finally { $c.Close() }
}

function Resolve-Base {
    if ($opt.ContainsKey('base')) { return $opt['base'].TrimEnd('/') }
    if ($env:DSH_WEB_URL) { return $env:DSH_WEB_URL.TrimEnd('/') }

    $cands = New-Object System.Collections.Generic.List[string]
    if (Test-Path $cacheFile) {
        $c = (Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue)
        if ($c) { $cands.Add($c.Trim().TrimEnd('/')) }
    }
    $ports = New-Object System.Collections.Generic.List[int]
    try {
        & netstat -ano -p tcp 2>$null | ForEach-Object {
            if ($_ -match 'LISTENING\s+\d+\s*$') {
                $parts = @(($_ -split '\s+') | Where-Object { $_ -ne '' })
                if ($parts.Count -ge 4 -and $parts[1] -match ':(\d+)$') {
                    $pt = [int]$Matches[1]
                    if (-not $ports.Contains($pt)) { $ports.Add($pt) }
                }
            }
        }
    }
    catch { }
    $ports | Sort-Object -Descending | ForEach-Object {
        if (Test-Port $_) { $cands.Add("http://127.0.0.1:$_") }
    }

    foreach ($b in ($cands | Select-Object -Unique)) {
        if (Test-Base $b) {
            Set-Content -Path $cacheFile -Value $b -Encoding UTF8 -ErrorAction SilentlyContinue
            return $b
        }
    }
    return $null
}

$Base = Resolve-Base
if (-not $Base) {
    Write-Host ''
    Write-Host '  找不到 DSH 的端口。先把 DSH 界面开着，再跑一次；' -ForegroundColor Yellow
    Write-Host '  或者手动指定：--base http://127.0.0.1:端口' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
$API = "$Base/dsh-pet-7340"

# ---------- 读配置 ----------
try {
    $cfg = Invoke-RestMethod -Uri "$API/config" -TimeoutSec 8
}
catch {
    Write-Host "连不上 $API （$($_.Exception.Message)）" -ForegroundColor Red
    exit 1
}

function Get-AnimNames($anim) {
    $acc = New-Object System.Collections.ArrayList
    $add = {
        param($items)
        foreach ($it in $items) {
            if ($it -is [string] -and $it -ne '' -and -not ($acc -contains $it)) { [void]$acc.Add($it) }
        }
    }
    if ($anim) {
        & $add $anim.idle
        & $add $anim.turn
        & $add $anim.drag
        & $add $anim.clicks
        if ($anim.moves -and $anim.moves.actions) {
            & $add @($anim.moves.actions | ForEach-Object { $_.name })
        }
        if ($anim.categories) { foreach ($c in $anim.categories) { & $add $c.actions } }
        if ($anim.events) {
            foreach ($ev in $anim.events.PSObject.Properties) {
                $pool = $ev.Value
                if ($pool -is [array]) {
                    foreach ($slot in $pool) {
                        if ($slot -is [array]) { & $add $slot } else { & $add @($slot) }
                    }
                }
            }
        }
        & $add $anim.baifan
    }
    return , $acc.ToArray()
}

$pets = @()
foreach ($prop in $cfg.PSObject.Properties) {
    $root = $prop.Name
    $entry = $prop.Value
    $names = Get-AnimNames $entry.animations
    foreach ($p in @($entry.pets)) {
        if (-not $p) { continue }
        $nm = $p.id
        if ($p.name) { $nm = $p.name }
        $pets += [pscustomobject]@{ root = $root; petId = [string]$p.id; name = [string]$nm; names = $names }
    }
}
if ($OnlyPets) {
    $want = @($OnlyPets -split ',' | ForEach-Object { $_.Trim() })
    $pets = @($pets | Where-Object { ($want -contains $_.petId) -or ($want -contains $_.root) })
}
$pets = @($pets | Where-Object { $_.petId })
if ($pets.Count -eq 0) {
    Write-Host '没有匹配的宠物。' -ForegroundColor Red
    exit 1
}

function Get-Common {
    $common = @($pets[0].names)
    foreach ($p in $pets) { $common = @($common | Where-Object { $p.names -contains $_ }) }
    return , $common
}

function Resolve-Name($pet, [string]$want) {
    if ($pet.names -contains $want) { return $want }
    $hit = @($pet.names | Where-Object { $_.Contains($want) -or $want.Contains($_) })
    if ($hit.Count -eq 1) { return $hit[0] }
    if ($hit.Count -gt 1) {
        $hit = @($hit | Sort-Object { $_.Length })
        return $hit[0]
    }
    return $null
}

function Invoke-Anim($pet, [string]$name) {
    $q = 'pet=' + [uri]::EscapeDataString($pet.petId) + '&surface=any'
    $o = @{ name = $name }
    if ($Facing -eq 'left' -or $Facing -eq 'right') { $o['facing'] = $Facing }
    $json = $o | ConvertTo-Json -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    try {
        $r = Invoke-RestMethod -Uri "$API/anim?$q" -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 8
        $ok = ($r.ok -eq $true)
        $reason = $r.reason
        if (-not $reason) { $reason = '?' }
        return [pscustomobject]@{ ok = $ok; reason = $reason }
    }
    catch {
        $code = ''
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        return [pscustomobject]@{ ok = $false; reason = "HTTP $code" }
    }
}

function Show-List {
    Write-Host ("宿主：{0}" -f $Base)
    $rows = @()
    $rows += , @('实例', '素材根', '名字', '动作数')
    foreach ($p in $pets) { $rows += , @($p.petId, $p.root, $p.name, [string]$p.names.Count) }
    $w = @(0, 0, 0, 0)
    foreach ($r in $rows) { for ($i = 0; $i -lt 4; $i++) { if ($r[$i].Length -gt $w[$i]) { $w[$i] = $r[$i].Length } } }
    foreach ($r in $rows) {
        $line = ''
        for ($i = 0; $i -lt 4; $i++) { $line += $r[$i].PadRight($w[$i]) + '  ' }
        Write-Host $line.TrimEnd()
    }
    $common = Get-Common
    Write-Host ''
    Write-Host ("共有动作 {0} 个：" -f $common.Count)
    for ($i = 0; $i -lt $common.Count; $i += 5) {
        $end = [Math]::Min($i + 5, $common.Count)
        Write-Host ('  ' + (@($common[$i..($end - 1)]) -join ' / '))
    }
}

function Show-Numbers {
    $common = Get-Common
    Write-Host ("都会的动作（输入编号或名字）：共 {0} 个" -f $common.Count)
    for ($i = 0; $i -lt $common.Count; $i++) {
        Write-Host ('  {0}. {1}' -f ([string]($i + 1)).PadLeft(2), $common[$i])
    }
}

function Invoke-OneRound([string]$want, [bool]$loopMode, [int]$round) {
    $targets = @()
    $skipped = @()
    foreach ($p in $pets) {
        $n = Resolve-Name $p $want
        if ($n) { $targets += [pscustomobject]@{ pet = $p; anim = $n } } else { $skipped += $p.petId }
    }
    if ($targets.Count -eq 0) {
        Write-Host ("没有哪只宠物有这个动作：{0}" -f $want) -ForegroundColor Yellow
        Write-Host '先跑 list 看看共有的动作。'
        return $null
    }

    $t0 = Get-Date
    $results = @()
    foreach ($t in $targets) { $results += , (Invoke-Anim $t.pet $t.anim) }
    $ms = [int]((Get-Date) - $t0).TotalMilliseconds
    $okCount = @($results | Where-Object { $_.ok }).Count

    if ($loopMode) {
        $bad = @()
        for ($i = 0; $i -lt $targets.Count; $i++) {
            if (-not $results[$i].ok) { $bad += ($targets[$i].pet.petId + ':' + $results[$i].reason) }
        }
        $tail = ''
        if ($bad.Count -gt 0) { $tail = '  失败：' + ($bad -join ', ') }
        Write-Host ('[{0}] {1}  {2}  {3}/{4} ok  {5}ms{6}' -f ([string]$round).PadLeft(2), (Get-Date).ToString('HH:mm:ss'), $want, $okCount, $targets.Count, $ms, $tail)
        if ($skipped.Count -gt 0) { Write-Host ('     跳过：' + ($skipped -join ', ') + '（没这个动作）') }
        return $okCount
    }

    Write-Host ("一起做：{0}   （{1} 只，用时 {2}ms）" -f $want, $targets.Count, $ms)
    for ($i = 0; $i -lt $targets.Count; $i++) {
        $state = 'ok'
        if (-not $results[$i].ok) { $state = '失败：' + $results[$i].reason }
        Write-Host ('  {0,-10} {1,-14} {2}' -f $targets[$i].pet.petId, $targets[$i].anim, $state)
    }
    if ($skipped.Count -gt 0) {
        Write-Host ('  没这个动作、跳过了：' + ($skipped -join ', ')) -ForegroundColor DarkGray
    }
    return $okCount
}

function Invoke-Broadcast([string]$want) {
    $looped = $Loop -or ($Repeat -gt 0)
    if (-not $looped) {
        [void](Invoke-OneRound $want $false 0)
        return
    }
    if ($Random) { Write-Host ('循环开始：随机动作，每 {0} 秒一轮，Ctrl+C 停。' -f ($Interval / 1000.0)) }
    else { Write-Host ('循环开始：{0}，每 {1} 秒一轮，Ctrl+C 停。' -f $want, ($Interval / 1000.0)) }

    $round = 0
    while ($true) {
        $round++
        $name = $want
        if ($Random) {
            $all = Get-Common
            $pool = @($all | Where-Object { $_ -is [string] -and $_.Contains($want) })
            if ($pool.Count -eq 0) { $pool = @($all) }
            $name = $pool[(Get-Random -Minimum 0 -Maximum $pool.Count)]
        }
        $ok = Invoke-OneRound $name $true $round
        if ($null -eq $ok) { return }
        if ($Repeat -gt 0 -and $round -ge $Repeat) { break }
        Start-Sleep -Milliseconds $Interval
    }
}

# ---------- 主流程 ----------
switch ($Action.ToLower()) {
    'list' { Show-List; exit 0 }
    'common' { Show-List; exit 0 }
    'numbers' { Show-Numbers; exit 0 }
    'menu' {
        Show-Numbers
        Write-Host ''
        $pick = Read-Host '输入编号或动作名（直接回车退出）'
        if (-not $pick) { exit 0 }
        $n = 0
        if ([int]::TryParse($pick, [ref]$n)) {
            $common = Get-Common
            if ($n -ge 1 -and $n -le $common.Count) { $pick = $common[$n - 1] }
        }
        Invoke-Broadcast $pick
        exit 0
    }
    default {
        $n = 0
        if ([int]::TryParse($Action, [ref]$n)) {
            $common = Get-Common
            if ($n -ge 1 -and $n -le $common.Count) { $Action = $common[$n - 1] }
            else {
                Write-Host ("编号超范围了：一共 {0} 个" -f $common.Count) -ForegroundColor Red
                exit 1
            }
        }
        Invoke-Broadcast $Action
        exit 0
    }
}
