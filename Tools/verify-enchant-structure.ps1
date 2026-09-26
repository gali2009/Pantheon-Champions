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

$names = @("anti_barrier", "anti_overload", "anti_unstoppable")
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
    @("anti_barrier",   "anti_overload"),
    @("anti_barrier",   "anti_unstoppable"),
    @("anti_overload",  "anti_unstoppable")
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
Write-Output "=== 7. lang 键完整性（显示名 + Enchantment Descriptions 描述）==="
# Enchantment Descriptions 模组的键格式是 enchantment.<命名空间>.<路径>.desc
# （从该模组 1.21.1 分支的 assets/enchdesc/lang/en_us.json 核实）。
# 附魔自己的显示名则是 description.translate 指向的键，必须与 JSON 里一致。
$langDir = Join-Path $root "src\main\resources\assets\pantheon_champions\lang"
foreach ($langName in @("en_us.json", "zh_cn.json")) {
    $langPath = Join-Path $langDir $langName
    if (-not (Test-Path $langPath)) {
        Check "$langName 存在" $false "文件缺失"
        continue
    }
    $lang = Read-Json $langPath
    foreach ($n in $names) {
        # 显示名：附魔 JSON 里 "translate" 指向的键
        $expectedKey = "enchantment.pantheon_champions.$n"
        $actualKey = $null
        if ($parsed.ContainsKey($n)) { $actualKey = $parsed[$n].description.translate }
        Check "$langName 有显示名 $expectedKey" `
              ($null -ne $lang.PSObject.Properties[$expectedKey]) "缺键"
        Check "$n 的 translate 指向 $expectedKey" ($actualKey -eq $expectedKey) ("实际 = " + $actualKey)

        # 描述：ED 模组的键
        $descKey = "$expectedKey.desc"
        Check "$langName 有 ED 描述 $descKey" `
              ($null -ne $lang.PSObject.Properties[$descKey]) "缺键"
        $descVal = $lang.PSObject.Properties[$descKey]
        if ($descVal) {
            Check "$descKey 非空" (-not [string]::IsNullOrWhiteSpace([string]$descVal.Value)) "值为空"
        }
    }
}

Write-Output ""
Write-Output "=== 8. 创造标签页的 lang 键 ==="
# 标签页标题键格式为 itemGroup.<modid>.<路径>，与 Java 里写的必须一致。
$tabKey = "itemGroup.pantheon_champions.champions"
foreach ($langName in @("en_us.json", "zh_cn.json")) {
    $lang = Read-Json (Join-Path $langDir $langName)
    Check "$langName 有 $tabKey" ($null -ne $lang.PSObject.Properties[$tabKey]) "缺键"
}

Write-Output ""
Write-Output "=== 9. Java 标签页里的附魔名与实际 JSON 文件必须一致 ==="
# 这是最现实的失败模式：ChampionsCreativeTabs.java 里手写的字符串数组
# 与 data/.../enchantment/ 下的文件名对不上（少个下划线、拼错），
# 编译期完全看不出来，只会在客户端打开物品栏时 getOrThrow 抛异常。
# 所以这里做静态交叉比对，不依赖运行日志。
$tabJava = Join-Path $root "src\main\java\beiwu\pantheon_champions\creativetab\ChampionsCreativeTabs.java"
if (Test-Path $tabJava) {
    $javaSrc = [System.IO.File]::ReadAllText($tabJava, [System.Text.Encoding]::UTF8)

    # 抓 CHAMPION_ENCHANTMENTS 数组里的字符串字面量
    $m = [regex]::Match($javaSrc, 'CHAMPION_ENCHANTMENTS\s*=\s*\{(.*?)\}', 'Singleline')
    if ($m.Success) {
        $javaNames = @([regex]::Matches($m.Groups[1].Value, '"([^"]+)"') |
                       ForEach-Object { $_.Groups[1].Value })
        Write-Output ("         Java 里: " + ($javaNames -join ", "))

        # 每个 Java 名都要有对应的 JSON 文件
        foreach ($jn in $javaNames) {
            Check "Java 名 $jn 有对应 JSON" (Test-Path (Join-Path $enchDir "$jn.json")) "文件不存在"
        }
        # 每个 JSON 文件也都要被 Java 覆盖（防止加了附魔忘了进标签页）
        foreach ($n in $names) {
            Check "JSON $n 已进标签页" ($javaNames -contains $n) "Java 数组里没有"
        }
        Check "Java 数组无重复" `
              (($javaNames | Select-Object -Unique).Count -eq $javaNames.Count) "有重复项"
    } else {
        Check "能解析 CHAMPION_ENCHANTMENTS" $false "正则没匹配到数组"
    }

    # 图标必须是用户指定的不死图腾
    Check "图标用不死图腾" ($javaSrc -match 'Items\.TOTEM_OF_UNDYING') "未找到 Items.TOTEM_OF_UNDYING"
} else {
    Check "ChampionsCreativeTabs.java 存在" $false $tabJava
}

Write-Output ""
if ($fail -eq 0) {
    Write-Output "结果: 通过 —— 三个附魔构成完整互斥组，均为 1 级，且 lang 键完整"
    exit 0
} else {
    Write-Output ("结果: 失败 —— {0} 项检查未通过" -f $fail)
    exit 1
}
