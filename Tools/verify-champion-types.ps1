# 勇士类型分配的一致性校验。
#
# 校验目标（全部是「文档 / 数据 / 代码三者必须一致」的交叉检查）：
#   1. ChampionTypes.java 的映射表 vs DESIGN.md 第 5 节归类表（逐行）
#   2. 家族标签 JSON 的成员 vs DESIGN.md 第 3.2 节家族表
#   3. 下界栖息地标签 vs DESIGN.md 第 4.1 节
#   4. 被动生物不会进入分配路径（Enemy 闸门存在）
#   5. 刷怪蛋的 lang 键、创造标签页收录、ChampionType 三种齐全
#
# 退出码 0 = 全部通过。
#
# 为什么要有这个脚本：类型表和归类表是两份独立的表示（md 散文 vs Java 代码），
# 人工同步迟早会漂移。附魔谓词里写死了数字（ChampionType:0/1/2），
# 所以类型一旦错位，表现是「附魔静默失效」，不会有任何报错——
# 只能靠这种静态交叉比对提前发现。

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'DESIGN.md'))) {
    # 兼容从项目根或 Tools 目录两种调用方式
    $root = $PSScriptRoot
    if (-not (Test-Path (Join-Path $root 'DESIGN.md'))) {
        Write-Output "找不到 DESIGN.md（尝试过 $root）"
        exit 1
    }
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$fails = New-Object System.Collections.ArrayList
$checks = 0

function Add-Fail([string]$msg) { [void]$fails.Add($msg) }
function Check([string]$msg, [bool]$ok) {
    $script:checks++
    if (-not $ok) { Add-Fail $msg }
}

$designPath = Join-Path $root 'DESIGN.md'
$typesPath  = Join-Path $root 'src\main\java\beiwu\pantheon_champions\champion\ChampionTypes.java'
$tagDir     = Join-Path $root 'src\main\resources\data\pantheon_champions\tags\entity_type'
$langZh     = Join-Path $root 'src\main\resources\assets\pantheon_champions\lang\zh_cn.json'
$langEn     = Join-Path $root 'src\main\resources\assets\pantheon_champions\lang\en_us.json'
$itemsPath  = Join-Path $root 'src\main\java\beiwu\pantheon_champions\item\ChampionsItems.java'
$tabPath    = Join-Path $root 'src\main\java\beiwu\pantheon_champions\creativetab\ChampionsCreativeTabs.java'

foreach ($p in @($designPath, $typesPath, $tagDir, $langZh, $langEn, $itemsPath, $tabPath)) {
    if (-not (Test-Path $p)) { Write-Output "缺少必需文件: $p"; exit 1 }
}

$design = [System.IO.File]::ReadAllText($designPath, $utf8)
$java   = [System.IO.File]::ReadAllText($typesPath, $utf8)
$lines  = $design -split "`r?`n"

Write-Output "=== 1. 解析 DESIGN.md 第 5 节归类表 ==="

# 归类表行形如：| 骷髅 | `minecraft:skeleton` | 远程·弓 | ✓ | | |
$doc = @{}
$inTable = $false
foreach ($ln in $lines) {
    if ($ln -match '^##\s*5\.\s*勇士归类表') { $inTable = $true; continue }
    if ($inTable -and $ln -match '^\*\*分布\*\*') { break }
    if (-not $inTable) { continue }
    if ($ln -match '^\|\s*[^|]+\|\s*`(minecraft:[a-z_]+)`\s*\|(.*)$') {
        $id = $Matches[1]
        $cols = $Matches[2] -split '\|'
        $types = @()
        if ($cols.Count -ge 4) {
            if ($cols[1] -match ([char]0x2713)) { $types += 'BARRIER' }
            if ($cols[2] -match ([char]0x2713)) { $types += 'OVERLOAD' }
            if ($cols[3] -match ([char]0x2713)) { $types += 'UNSTOPPABLE' }
        }
        $doc[$id] = $types
    }
}
Write-Output ("  归类表实体数: " + $doc.Count)
Check "第 5 节应解析出 37 行实体，实际 $($doc.Count)" ($doc.Count -eq 37)

Write-Output "=== 2. 解析 ChampionTypes.java 的映射 ==="

$javaSingle = @{}
foreach ($m in [regex]::Matches($java, 'Map\.entry\(EntityType\.([A-Z_0-9]+),\s*ChampionType\.([A-Z]+)\)')) {
    $javaSingle[$m.Groups[1].Value] = $m.Groups[2].Value
}
function Parse-Set([string]$name) {
    $out = @()
    $m = [regex]::Match($java, ($name + '\s*=\s*Set\.of\(([^)]*)\)'), 'Singleline')
    if ($m.Success) {
        foreach ($x in [regex]::Matches($m.Groups[1].Value, 'EntityType\.([A-Z_0-9]+)')) { $out += $x.Groups[1].Value }
    }
    return $out
}
$dual     = Parse-Set 'DUAL_STATE'
$deferred = Parse-Set 'DEFERRED'
$excluded = Parse-Set 'EXCLUDED'

Write-Output ("  单态 $($javaSingle.Count) / 双态 $($dual.Count) / 暂缓 $($deferred.Count) / 排除 $($excluded.Count)")
Check "双态应为 2 个（drowned, piglin），实际 $($dual.Count)" ($dual.Count -eq 2)
Check "暂缓应为 3 个（illusioner, slime, magma_cube），实际 $($deferred.Count)" ($deferred.Count -eq 3)

Write-Output "=== 3. Java 表 vs DESIGN 第 5 节 逐行比对 ==="

# 有意偏离文档的名单：史莱姆族（用户要求机制另行设计后暂缓）。
# 这两只在文档里归过载，但实现上放进 DEFERRED，属于已知且经确认的偏离。
$intentionalDefer = @('slime', 'magma_cube')

foreach ($id in $doc.Keys) {
    $short = $id -replace '^minecraft:', ''
    $upper = $short.ToUpper()
    $docTypes = @($doc[$id])

    if ($docTypes.Count -eq 0) {
        # 文档标「—」：必须落在暂缓或排除里
        Check "$short 在文档中标「—」，但 Java 未归入暂缓/排除" `
              (($deferred -contains $upper) -or ($excluded -contains $upper))
        continue
    }

    if ($docTypes.Count -ge 2) {
        # 双态：必须在 DUAL_STATE 且不在单态表
        Check "$short 在文档中是双态，但 Java 未列入 DUAL_STATE" ($dual -contains $upper)
        Check "$short 是双态，却出现在单态映射表里" (-not $javaSingle.ContainsKey($upper))
        continue
    }

    if ($intentionalDefer -contains $short) {
        Check "$short 本应有意暂缓，但 Java 未放进 DEFERRED" ($deferred -contains $upper)
        Check "$short 已暂缓，却又出现在单态映射表里" (-not $javaSingle.ContainsKey($upper))
        continue
    }

    if (-not $javaSingle.ContainsKey($upper)) {
        Add-Fail "$short : 文档为 $($docTypes -join '/')，但 Java 单态表里没有"
        $checks++
    } else {
        Check "$short : 文档=$($docTypes[0])  Java=$($javaSingle[$upper])" ($javaSingle[$upper] -eq $docTypes[0])
    }
}

# 反向：Java 里不该出现文档查不到的实体
foreach ($k in $javaSingle.Keys) {
    Check "$($k.ToLower()) : Java 有映射，但 DESIGN 第 5 节查无此实体" ($doc.ContainsKey("minecraft:" + $k.ToLower()))
}
foreach ($k in $dual) {
    Check "$($k.ToLower()) : Java 标为双态，但 DESIGN 第 5 节查无此实体" ($doc.ContainsKey("minecraft:" + $k.ToLower()))
}

Write-Output "=== 4. 家族标签 vs DESIGN 第 3.2 节 ==="

# 家族表行形如：| **亡灵** `undead` | 10 | 13 | zombie, husk, ... |
$docFamilies = @{}
$inFam = $false
foreach ($ln in $lines) {
    if ($ln -match '^###\s*3\.2') { $inFam = $true; continue }
    if ($inFam -and $ln -match '^###\s*3\.3') { break }
    if (-not $inFam) { continue }
    if ($ln -match '`([a-z_]+)`\s*\|[^|]*\|[^|]*\|\s*(.+?)\s*\|\s*$') {
        $fam = $Matches[1]
        $membersRaw = $Matches[2]
        $members = @()
        foreach ($t in ($membersRaw -split ',')) {
            $t = $t.Trim()
            if ($t -match '^[a-z_]+$') { $members += $t }
        }
        if ($members.Count -gt 0) { $docFamilies[$fam] = $members }
    }
}
Write-Output ("  文档家族数: " + $docFamilies.Count)

$tagFiles = Get-ChildItem -Path $tagDir -Filter '*.json' -File | Where-Object { $_.Name -ne 'nether.json' }
Write-Output ("  标签文件数: " + $tagFiles.Count + " (不含 habitat 子目录)")

Check "家族标签数应与文档家族数一致" ($tagFiles.Count -eq $docFamilies.Count)

foreach ($f in $tagFiles) {
    $fam = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    Check "标签 $fam.json 在 DESIGN 第 3.2 节里没有对应家族" ($docFamilies.ContainsKey($fam))
    if (-not $docFamilies.ContainsKey($fam)) { continue }

    $json = [System.IO.File]::ReadAllText($f.FullName, $utf8) | ConvertFrom-Json
    $tagMembers = @()
    foreach ($v in $json.values) { $tagMembers += ($v -replace '^minecraft:', '') }
    $docMembers = @($docFamilies[$fam])

    $onlyTag = @($tagMembers | Where-Object { $docMembers -notcontains $_ })
    $onlyDoc = @($docMembers | Where-Object { $tagMembers -notcontains $_ })
    Check "$fam.json 多出成员: $($onlyTag -join ', ')" ($onlyTag.Count -eq 0)
    Check "$fam.json 缺少成员: $($onlyDoc -join ', ')" ($onlyDoc.Count -eq 0)
    Check "$fam.json 的 replace 必须是 false（允许他人扩展）" ($json.replace -eq $false)
}

Write-Output "=== 5. 下界栖息地 vs DESIGN 第 4.1 节 ==="

$docNether = @()
$inHb = $false
foreach ($ln in $lines) {
    if ($ln -match '^###\s*4\.1') { $inHb = $true; continue }
    if ($inHb -and $ln -match '^>\s*\*\*注意\*\*') { break }
    if (-not $inHb) { continue }
    # 第 4.1 节的写法与第 5 节不同：实体 ID **不带 minecraft: 前缀**
    # （形如 `magma_cube` 岩浆怪），且一行可能写多个
    # （`piglin` / `piglin_brute`）。所以取该行全部反引号小写 token。
    foreach ($m in [regex]::Matches($ln, '`([a-z_]+)`')) {
        $docNether += $m.Groups[1].Value
    }
}
$netherJson = [System.IO.File]::ReadAllText((Join-Path $tagDir 'habitat\nether.json'), $utf8) | ConvertFrom-Json
$tagNether = @()
foreach ($v in $netherJson.values) { $tagNether += ($v -replace '^minecraft:', '') }
$nOnlyDoc = @($docNether | Where-Object { $tagNether -notcontains $_ })
$nOnlyTag = @($tagNether | Where-Object { $docNether -notcontains $_ })
Check "下界标签缺少: $($nOnlyDoc -join ', ')" ($nOnlyDoc.Count -eq 0)
Check "下界标签多出: $($nOnlyTag -join ', ')" ($nOnlyTag.Count -eq 0)
Write-Output ("  文档下界成员 $($docNether.Count) / 标签 $($tagNether.Count)")

Write-Output "=== 6. 被动生物闸门（Enemy）必须存在 ==="

# 家族标签里有意含被动成员（鱼、海龟、马、蜜蜂），
# 若分配路径少了 Enemy 判断，它们就会变成勇士。
$eligibleFn = [regex]::Match($java, 'public static boolean isEligible\(Mob mob\)\s*\{(.*?)\n    \}', 'Singleline')
Check "isEligible 方法不存在" $eligibleFn.Success
if ($eligibleFn.Success) {
    Check "isEligible 里没有 Enemy 判断——被动生物会变成勇士" ($eligibleFn.Groups[1].Value -match 'instanceof Enemy')
}
$assignPath = Join-Path $root 'src\main\java\beiwu\pantheon_champions\champion\ChampionAssignment.java'
$assign = [System.IO.File]::ReadAllText($assignPath, $utf8)
Check "分配路径未调用 isEligible" ($assign -match 'ChampionTypes\.isEligible')

Write-Output "=== 7. 刷怪蛋：三个类型齐全 + lang 键 + 创造标签页 ==="

$items = [System.IO.File]::ReadAllText($itemsPath, $utf8)
$eggNames = @()
foreach ($m in [regex]::Matches($items, 'registerEgg\("([a-z_]+)"')) { $eggNames += $m.Groups[1].Value }
Check "刷怪蛋应为 3 个，实际 $($eggNames.Count)" ($eggNames.Count -eq 3)
Check "刷怪蛋未覆盖全部三种勇士类型" ($items -match 'ChampionType\.BARRIER' -and $items -match 'ChampionType\.OVERLOAD' -and $items -match 'ChampionType\.UNSTOPPABLE')

$zh = [System.IO.File]::ReadAllText($langZh, $utf8)
$en = [System.IO.File]::ReadAllText($langEn, $utf8)
foreach ($n in $eggNames) {
    Check "zh_cn.json 缺 item.pantheon_champions.$n" ($zh -match [regex]::Escape("item.pantheon_champions.$n"))
    Check "en_us.json 缺 item.pantheon_champions.$n" ($en -match [regex]::Escape("item.pantheon_champions.$n"))
}
foreach ($t in @('barrier', 'overload', 'unstoppable')) {
    Check "zh_cn.json 缺 champion.pantheon_champions.$t" ($zh -match [regex]::Escape("champion.pantheon_champions.$t"))
    Check "en_us.json 缺 champion.pantheon_champions.$t" ($en -match [regex]::Escape("champion.pantheon_champions.$t"))
}

$tab = [System.IO.File]::ReadAllText($tabPath, $utf8)
Check "创造标签页没有收录刷怪蛋" ($tab -match 'ChampionsItems\.spawnEggs')

Write-Output "=== 8. ChampionType 的三色与附魔 ID 对应 ==="

$typePath = Join-Path $root 'src\main\java\beiwu\pantheon_champions\champion\ChampionType.java'
$typeJava = [System.IO.File]::ReadAllText($typePath, $utf8)
# 附魔谓词里写死了 0/1/2，枚举里的 id 必须与之一致，否则附魔静默失效
$expect = @{ 'BARRIER' = 0; 'OVERLOAD' = 1; 'UNSTOPPABLE' = 2 }
foreach ($k in $expect.Keys) {
    $m = [regex]::Match($typeJava, "$k\((\d+),\s*""([a-z]+)"",\s*ChatFormatting\.([A-Z_]+)\)")
    Check "ChampionType.$k 的声明格式不符预期" $m.Success
    if ($m.Success) {
        Check "ChampionType.$k 的 id 应为 $($expect[$k])，实际 $($m.Groups[1].Value)" ([int]$m.Groups[1].Value -eq $expect[$k])
        Check "ChampionType.$k 的 key 应为 $($k.ToLower())，实际 $($m.Groups[2].Value)" ($m.Groups[2].Value -eq $k.ToLower())
    }
}
# 用户指定：过载蓝 / 势不可挡红 / 屏障黄
Check "屏障应为黄色描边"  ($typeJava -match 'BARRIER\(0,\s*"barrier",\s*ChatFormatting\.YELLOW\)')
Check "过载应为蓝色描边"  ($typeJava -match 'OVERLOAD\(1,\s*"overload",\s*ChatFormatting\.BLUE\)')
Check "势不可挡应为红色描边" ($typeJava -match 'UNSTOPPABLE\(2,\s*"unstoppable",\s*ChatFormatting\.RED\)')

Write-Output ""
Write-Output "================ 结果 ================"
Write-Output ("检查项: " + $checks)
if ($fails.Count -eq 0) {
    Write-Output "PASS - 类型表 / 家族标签 / 刷怪蛋 / 附魔 ID 全部一致"
    exit 0
} else {
    Write-Output ("FAIL - " + $fails.Count + " 项不一致:")
    foreach ($f in $fails) { Write-Output ("  - " + $f) }
    exit 1
}
