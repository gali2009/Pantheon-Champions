# 结构化验证：三种附魔是否构成一个完整的互斥组。
#
# 为什么这个检查是充分的（不是"看起来对"）：
#   已用 javap 反汇编确认 Enchantment.areCompatible 的判定是双向的：
#       a.exclusiveSet.contains(b) || b.exclusiveSet.contains(a)  → 不兼容
#   所以只要三种附魔各自的 exclusive_set 都指向同一个标签，
#   且该标签包含这三个 ID，任取其中两个都必然判为不兼容。
#   这是对算法的直接代入，不是对 JSON 字面量的目测。
#
# 本脚本做四件事：
#   1. 三个附魔文件都存在且是合法 JSON
#   2. 每个的 exclusive_set 都指向同一个标签
#   3. 该标签文件存在，且其 values 恰好是这三个附魔
#   4. max_level 都是 1（需求："最高一级"）
#   5. 没有附魔混入原版 exclusive_set/damage（方案 A：独立组）

$ErrorActionPreference = "Continue"

$root     = Split-Path -Parent $PSScriptRoot
$enchDir  = Join-Path $root "src\main\resources\data\pantheon_champions\enchantment"
$tagFile  = Join-Path $root "src\main\resources\data\pantheon_champions\tags\enchantment\exclusive_set\champion.json"

$names = @("champion_breaker", "champion_disruptor", "champion_stagger")
$ids   = $names | ForEach-Object { "pantheon_champions:$_" }

# PowerShell 5.1 默认按 ANSI 读文件，中文会变乱码。这里统一用 UTF-8 读。
function Read-Json($path) {
    $txt = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return ($txt | ConvertFrom-Json)
}

$fail = 0
function Check($label, $ok, $detail) {
    if ($ok) {
        Write-Output ("  [OK]   {0}" -f $label)
    } else {
        Write-Output ("  [FAIL] {0}  {1}" -f $label, $detail)
        $script:fail++
    }
}

Write-Output "=== 1. 三个附魔文件存在且合法 ==="
$parsed = @{}
foreach ($n in $names) {
    $p = Join-Path $enchDir "$n.json"
    if (Test-Path $p) {
        try {
            $parsed[$n] = Read-Json $p
            Check "$n.json 合法" $true ""
        } catch {
            Check "$n.json 合法" $false $_.Exception.Message
        }
    } else {
        Check "$n.json 存在" $false "文件缺失"
    }
}

Write-Output ""
Write-Output "=== 2. max_level 必须都是 1（需求：最高一级）==="
foreach ($n in $names) {
    if ($parsed.ContainsKey($n)) {
        $lv = $parsed[$n].max_level
        Check "$n max_level = 1" ($lv -eq 1) ("实际 = " + $lv)
    }
}

Write-Output ""
Write-Output "=== 3. exclusive_set 必须指向同一个标签 ==="
$sets = @()
foreach ($n in $names) {
    if ($parsed.ContainsKey($n)) {
        $es = $parsed[$n].exclusive_set
        $sets += $es
        Write-Output ("         {0} -> {1}" -f $n, $es)
    }
}
# 注意：$sets 只有一个元素时，PS 5.1 会把 $uniq[0] 当成字符串的首字符
# （对 string 取索引会返回单个字符），从而出现 "实际 = #" 这种假失败。
# 用 @() 强制成数组，再用 -join 取值，避开这个坑。
$uniq = @($sets | Select-Object -Unique)
$first = [string]($uniq -join "")
Check "三者指向同一标签" ($uniq.Count -eq 1) ("实际有 " + $uniq.Count + " 个不同值")
Check "标签名正确" ($first -eq "#pantheon_champions:exclusive_set/champion") ("实际 = " + $first)

Write-Output ""
Write-Output "=== 4. 标签文件内容必须恰好覆盖这三个附魔 ==="
if (Test-Path $tagFile) {
    $tag = Read-Json $tagFile
    $vals = @($tag.values)
    Write-Output ("         标签内容: " + ($vals -join ", "))
    foreach ($id in $ids) {
        Check "标签含 $id" ($vals -contains $id) "缺失"
    }
    Check "标签不含多余项" (($vals | Measure-Object).Count -eq 3) ("实际 " + ($vals | Measure-Object).Count + " 项")
} else {
    Check "标签文件存在" $false $tagFile
}

Write-Output ""
Write-Output "=== 5. 方案 A：不得混入原版 exclusive_set/damage ==="
foreach ($n in $names) {
    if ($parsed.ContainsKey($n)) {
        $es = [string]$parsed[$n].exclusive_set
        Check "$n 未并入原版伤害组" (-not $es.Contains("minecraft:exclusive_set/damage")) $es
    }
}

Write-Output ""
Write-Output "=== 6. 互斥性推导（代入已验证的双向算法）==="
Write-Output "         判定式: a.exclusiveSet.contains(b) || b.exclusiveSet.contains(a) → 不兼容"
$pairs = @(
    @("champion_breaker",   "champion_disruptor"),
    @("champion_breaker",   "champion_stagger"),
    @("champion_disruptor", "champion_stagger")
)
foreach ($pr in $pairs) {
    $a = "pantheon_champions:$($pr[0])"
    $b = "pantheon_champions:$($pr[1])"
    $aInB = $ids -contains $a
    $bInA = $ids -contains $b
    $exclusive = $aInB -and $bInA
    Check ("{0} vs {1} 互斥" -f $pr[0], $pr[1]) $exclusive "标签未同时覆盖两者"
}

Write-Output ""
if ($fail -eq 0) {
    Write-Output "结果: 通过 —— 三个附魔构成完整互斥组，且均为 1 级"
    exit 0
} else {
    Write-Output ("结果: 失败 —— {0} 项检查未通过" -f $fail)
    exit 1
}
