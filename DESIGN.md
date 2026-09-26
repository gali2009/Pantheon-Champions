# Pantheon: Champions —— MC 1.21.1 勇士系统设计定稿

> 目标：把《命运2》的三种勇士（Champion）机制移植到 Minecraft 1.21.1。
> 本文档为**生物归类与分类体系**定稿，含实现所需的标签与 API 设计。

- 数据来源：本地 `neoforge-21.1.250-merged.jar` 与
  `neoforge-21.1.250-client-extra-aka-minecraft-resources.jar`
  （位于 `E:\ModDev\ThaumicEnergistics\build\moddev\artifacts\`）
- 游戏版本：Minecraft 1.21.1 / NeoForge 21.1.250
- 归属判定依据：**类继承关系**（`Enemy` 接口）+ **实体标签**（`EntityTypeTags`）+
  **攻击类型**（字节码中的 Goal 类），三者均为机器读取，非人工记忆

---

## 1. 三种勇士的机制定义

先明确要移植的到底是什么行为，归类才有依据。

| 勇士类型 | 《命运2》原始机制 | 核心动词 | 移植到 MC 的特征 |
| --- | --- | :---: | --- |
| **屏障** Barrier | 受伤后架盾，盾期间免伤并从盾后回血，需**反屏障**弹药破盾 | **破** | 周期性免伤护盾，必须在再生前破除 |
| **过载** Overload | 高速自愈、相位瞬移、闪避，需**过载**弹药持续干扰才能压制恢复 | **压** | 高自愈/相位机动，必须持续打断恢复 |
| **势不可挡** Unstoppable | 极高减伤 + 向前冲锋，需**势不可挡**弹药造成**震慑**打断 | **断** | 重装高减伤 + 冲锋，必须在时机内打断 |

这三个动词（**破 / 压 / 断**）是整套系统的设计核心，后文所有归类都以此为准。

### 《命运2》的设计意图与教训

**意图**：勇士随 Shadowkeep（2019）的 Nightfall: The Ordeal 加入，解决"一套配装吃遍所有内容"
的问题——强制玩家按敌人类型轮换装备。三种类型考的不是数值，而是三种操作节奏。

**教训**（社区批评集中于此，移植时应避开）：

1. **违背了 Bungie 自己的口号。** D1 宣传语是 "Play the game your way"，
   但勇士+赛季神器规定了必须用哪把枪（[Bungie 论坛](https://www.bungie.net/zh-CHT/Forums/Post/265223871)）。
2. **赛季轮换作废 build。** 反勇士模组每赛季轮换，刚配好的方案下赛季失效
   （[Destructoid](https://www.destructoid.com/destiny-2-brings-a-creative-comprehensive-fix-to-the-champion-problem-in-its-final-update/)）。
3. **它是清单，不是决策。** 知道类型后答案唯一，玩家没有选择空间。
4. **被道具门控。** 克制手段依赖背包里有没有那个模组。

Bungie 在 Edge of Fate 的补救是让武器**自带**反勇士特性，削弱被强制轮换的感觉
（[TheGamePost](https://thegamepost.com/updated-destiny-2-champion-stun-chart-edge-of-fate/)、
[GameRant](https://gamerant.com/destiny-2-edge-fate-artifact-perks-champion-counter-good/)）。

**对本项目的指导**：克制手段应表达**操作技巧**（破盾窗口、打断时机），
而不是**检验道具**。这是 MC 相对 D2 的结构性优势。

---

## 2. MC 的分类体系（关键前提）

MC **没有单一的"生物类型"体系**，而是四套互相独立的机制并行。
混淆它们是设计中最容易踩的坑。

| 体系 | 载体 | 作用 | 用于勇士系统？ |
| --- | --- | --- | --- |
| **生成类别** | `MobCategory` 枚举 | 刷怪、消失规则 | ✗ |
| **敌对性** | `Enemy` 接口 | 是否敌对 | ✓ 决定候选池 |
| **族类** | `EntityTypeTags` 标签 | 战斗克制关系 | ✓ 决定勇士类型 |
| **AI 基类** | `Monster` / `Raider` 等 | 行为逻辑 | ✗ |

### 2.1 生成类别 `MobCategory`

仅 8 个值，纯刷怪规则：`MONSTER`、`CREATURE`、`AMBIENT`、`AXOLOTLS`、
`UNDERGROUND_WATER_CREATURE`、`WATER_CREATURE`、`WATER_AMBIENT`、`MISC`。

### 2.2 敌对性 = `Enemy` 接口

全游戏 **39 个具体实体类**实现 `Enemy`，判定链为
`Monster` / `Slime` / `Ghast` / `Shulker` / `Phantom` / `Hoglin` / `Zoglin` / `EnderDragon`
直接实现，其余继承。

> **注意**：`Enemy` 包含行为中立的生物（末影人、猪灵、僵尸猪灵）。
> 代码意义上的"敌对"比"会主动打你"更宽。

### 2.3 族类 = 实体标签

1.21.1 共有 34 个 `entity_type` 标签。递归展开后与战斗相关的如下：

| 标签 | 数量 | 成员 |
| --- | ---: | --- |
| `#undead` 亡灵 | 14 | 骷髅系 5 + 僵尸系 7 + `phantom` + `wither` |
| ├ `#skeletons` | 5 | skeleton, stray, bogged, wither_skeleton, skeleton_horse |
| └ `#zombies` | 7 | zombie, husk, drowned, zombie_villager, zombified_piglin, zoglin, zombie_horse |
| `#arthropod` 节肢 | 5 | spider, cave_spider, silverfish, endermite, **bee** |
| `#illager` 灾厄 | 4 | evoker, illusioner, pillager, vindicator |
| `#raiders` 袭击者 | 6 | 上述 4 个 + **ravager** + **witch** |
| `#aquatic` 水生 | 12 | guardian, elder_guardian, 鱼类、鱿鱼、海龟、美西螈 |

### 2.4 三个必须知道的坑

**坑一：`MobType` 枚举已移除。** 旧教程里的 `MobType.UNDEAD` / `MobType.ARTHROPOD`
在 1.21.1 **已完全移除**（全 jar 扫描无 `MobType` 类，`Mob` 上也无 `getMobType`）。
现一律用标签查询 `entityType.is(EntityTypeTags.UNDEAD)`。

**坑二：标签 ≠ 敌对。** `#undead` 含 `skeleton_horse`、`zombie_horse`、`zombified_piglin`
（均不敌对）；`#arthropod` 含蜜蜂（中立）。**两套体系正交。**

**坑三：原版标签有"意外"。** `vex` **不在**任何灾厄标签里；`witch` 在 `#raiders` 但
**不在** `#illager`；`ravager` 同理。且 `#illager` ⊂ `#raiders` 是**嵌套关系**，
两者**不能同时作为互斥的第一层**。

### 2.5 标签驱动 6 个战斗后果

原版已有一套现成的"按族克制"系统：

| 后果标签 | 等于 | 效果 |
| --- | --- | --- |
| `sensitive_to_smite` | `#undead` | 亡灵杀手增伤 |
| `sensitive_to_bane_of_arthropods` | `#arthropod` | 节肢杀手增伤 |
| `sensitive_to_impaling` | `#aquatic` | 穿刺增伤 |
| `ignores_poison_and_regen` | `#undead` | 免疫中毒/再生 |
| `inverted_healing_and_harm` | `#undead` | 治疗伤害、伤害治疗 |
| `wither_friends` | `#undead` | 凋灵不攻击 |

> **设计含义**：MC 已有"按族固定克制"。勇士系统**不能只是它的一层皮**，
> 否则与现有附魔重复，且会精准命中 D2 的第 3 条批评（变成清单）。

---

## 3. 家族划分（互斥，已验证）

**核心决策：家族必须互斥**——一只生物只属于一个家族，
否则勇士类型不唯一，反制手段失效。

### 3.1 与原版标签的关系

我们**自建标签，不复用原版标签**。原因见 6.1。

### 3.2 家族表

| 家族 | 敌对 | 合计 | 成员 |
| --- | ---: | ---: | --- |
| **亡灵** `undead` | 10 | 13 | zombie, husk, drowned, zombie_villager, skeleton, stray, bogged, wither_skeleton, phantom, zoglin, zombified_piglin, skeleton_horse, zombie_horse |
| ├ **僵尸** `zombie` | 6 | 6 | zombie, husk, drowned, zombie_villager, zoglin, zombified_piglin |
| ├ **骷髅** `skeleton` | 4 | 4 | skeleton, stray, bogged, wither_skeleton |
| └ 直属 | 1 | 3 | phantom（+ skeleton_horse, zombie_horse） |
| **节肢** `arthropod` | 4 | 5 | spider, cave_spider, silverfish, endermite, bee |
| **水生** `aquatic` | 2 | 12 | guardian, elder_guardian, turtle, axolotl, cod, pufferfish, salmon, tropical_fish, dolphin, squid, glow_squid, tadpole |
| **灾厄** `illager` | 4 | 4 | evoker, illusioner, pillager, witch |
| **袭击者** `raider` | 3 | 3 | vindicator, ravager, vex |
| **猪灵** `piglin` | 2 | 3 | piglin, piglin_brute, hoglin |
| **史莱姆** `slime` | 2 | 2 | slime, magma_cube |
| **末影** `ender` | 0 | 1 | enderman |
| **无族** `factionless` | 7 | 7 | creeper, breeze, warden, giant, ghast, blaze, shulker |
| | **34** | | |

### 3.3 验证结果

| 检查项 | 结果 |
| --- | --- |
| 34 个敌对生物全部覆盖 | **PASS**（0 未分类） |
| 无双重归属 | **PASS**（0 冲突） |
| 子族无重叠 | **PASS**（zombie ∩ skeleton = ∅） |
| 与原版 `#undead` 的差异 | 仅差 `wither`（**有意排除**，见 5.1） |

### 3.4 为什么叫"灾厄"和"袭击者"两个名字

原版 `#illager` ⊂ `#raiders`，无法并列。按**战斗方式**拆分解决：

- **灾厄** = 施法 / 远程 → evoker（召唤）、illusioner（弓+致盲）、pillager（弩）、witch（投药水）
- **袭击者** = 兽 / 近战 → vindicator（斧）、ravager（冲撞）、vex（飞行冲撞）

这同时解决了原版的"意外"：`witch` 和 `vex` 原本归属混乱，现各有明确归宿。

---

## 4. 栖息地轴（独立，不与家族互斥）

**核心决策：下界是栖息地，不是家族。**

原因：**栖息地是"在哪"，家族是"是什么"，一只生物同时具备两者。**
若把下界做成家族，它会与史莱姆族、猪灵族、亡灵族争抢同一个槽位。
做成独立轴后，`magma_cube` 可以既是**史莱姆族**又是**下界**，两者不冲突。

### 4.1 下界栖息地成员

| 生物 | 家族 | 栖息地 |
| --- | --- | --- |
| `magma_cube` 岩浆怪 | 史莱姆 | 下界 |
| `hoglin` 疣猪兽 | 猪灵 | 下界 |
| `zoglin` 僵尸疣猪兽 | **亡灵**（僵尸族） | 下界 |
| `zombified_piglin` 僵尸猪灵 | **亡灵**（僵尸族） | 下界 |
| `wither_skeleton` 凋灵骷髅 | **亡灵**（骷髅族） | 下界 |
| `piglin` / `piglin_brute` | 猪灵 | 下界 |
| `blaze` / `ghast` | 无族 | 下界 |

> **注意**：原版**没有任何栖息地标签**（`nether`/`overworld`/`end`/`dimension`/`habitat`
> 全部不存在），必须自建。

**用途**：栖息地可做**修饰符**（如"下界勇士获得额外效果"），而不是和家族抢槽位。

---

## 5. 勇士归类表（定稿）

| 敌对生物 | MCID | 攻击类型 | 屏障 | 过载 | 势不可挡 |
| --- | --- | --- | :---: | :---: | :---: |
| **骷髅族** | | | | | |
| 骷髅 | `minecraft:skeleton` | 远程·弓 | ✓ | | |
| 流浪者 | `minecraft:stray` | 远程·弓 | ✓ | | |
| 沼骸 | `minecraft:bogged` | 远程·弓 | ✓ | | |
| **僵尸族** | | | | | |
| 僵尸 | `minecraft:zombie` | 近战 | | | ✓ |
| 尸壳 | `minecraft:husk` | 近战 | | | ✓ |
| 溺尸 | `minecraft:drowned` | **双态** | ✓ | | ✓ |
| 僵尸村民 | `minecraft:zombie_villager` | 近战 | | | ✓ |
| 僵尸疣猪兽 | `minecraft:zoglin` | 近战 | | | ✓ |
| 僵尸猪灵 | `minecraft:zombified_piglin` | 近战 | | | ✓ |
| **亡灵·直属** | | | | | |
| 幻翼 | `minecraft:phantom` | 俯冲 | | ✓ | |
| 凋灵骷髅 | `minecraft:wither_skeleton` | 近战 | | | ✓ |
| **节肢** | | | | | |
| 蜘蛛 | `minecraft:spider` | 近战·爬墙 | | ✓ | |
| 洞穴蜘蛛 | `minecraft:cave_spider` | 近战·中毒 | | ✓ | |
| 蠹虫 | `minecraft:silverfish` | 近战·成群 | | ✓ | |
| 末影螨 | `minecraft:endermite` | 近战·成群 | | ✓ | |
| **水生** | | | | | |
| 守卫者 | `minecraft:guardian` | 远程·激光 | ✓ | | |
| 远古守卫者 | `minecraft:elder_guardian` | 远程·激光 | ✓ | | |
| **灾厄** | | | | | |
| 掠夺者 | `minecraft:pillager` | 远程·弩 | ✓ | | |
| 唤魔者 | `minecraft:evoker` | 召唤·尖牙 | ✓ | | |
| 女巫 | `minecraft:witch` | 投药·治疗 | | ✓ | |
| 幻术师 | `minecraft:illusioner` | 弓·致盲·分身 | — | — | — |
| **袭击者** | | | | | |
| 卫道士 | `minecraft:vindicator` | 近战·斧 | | | ✓ |
| 劫掠兽 | `minecraft:ravager` | 冲撞·强击退 | | | ✓ |
| 恼鬼 | `minecraft:vex` | 飞行冲撞·穿墙 | | | ✓ |
| **猪灵** | | | | | |
| 猪灵 | `minecraft:piglin` | **双态** | ✓ | | ✓ |
| 猪灵蛮兵 | `minecraft:piglin_brute` | 近战 | | | ✓ |
| 疣猪兽 | `minecraft:hoglin` | 冲撞 | | | ✓ |
| **史莱姆** | | | | | |
| 史莱姆 | `minecraft:slime` | 近战·分裂 | | ✓ | |
| 岩浆怪 | `minecraft:magma_cube` | 近战·分裂 | | ✓ | |
| **末影** | | | | | |
| 末影人 | `minecraft:enderman` | 近战·瞬移 | | ✓ | |
| **无族** | | | | | |
| 苦力怕 | `minecraft:creeper` | 引信·爆炸 | | | ✓ |
| 监守者 | `minecraft:warden` | 近战·音波 | | | ✓ |
| 恶魂 | `minecraft:ghast` | 远程·火球 | ✓ | | |
| 烈焰人 | `minecraft:blaze` | 远程·火球连射 | ✓ | | |
| 旋风人 | `minecraft:breeze` | 远程·风弹·高机动 | ✓ | | |
| 潜影贝 | `minecraft:shulker` | 远程·瞬移·硬壳 | ✓ | | |
| 巨人 | `minecraft:giant` | 无攻击 AI | — | — | — |

**分布**（共 37 行，其中 34 个敌对 + 3 个非敌对）

按**标注数**（一只双态生物计两个）：

| 类型 | 数量 |
| --- | ---: |
| 屏障 | 13 |
| 过载 | 9 |
| 势不可挡 | 15 |
| **合计** | **37** |

按**生物数**（剔除双态生物的重复计数）：

| 类别 | 数量 |
| --- | ---: |
| 单态生物 | 33 |
| ├ 屏障 | 11 |
| ├ 过载 | 9 |
| └ 势不可挡 | 13 |
| **双态生物** | **2**（`drowned`、`piglin`） |
| 暂缓（`illusioner`） | 1 |
| 排除（`giant`） | 1 |

> **勾数(37) ≠ 生物数(35 可归类 + 2 不归类)**：双态生物各占两个勾，
> 因此标注总数比生物数多 2。这是双态机制的**直接后果**，不是统计错误。
>
> 两个口径都列出，是为了避免"分布表与归类表对不上"的误判——
> 判断依据分别是"标注数"和"生物数"，混用会得到不同结果。

---

## 6. 双态机制

**决策：双态 = 运行时决定，互斥性依然成立。**

一只溺尸 / 猪灵在**生成时**决定自己是屏障还是势不可挡，**不会同时是两种**。
这与《命运2》一致（D2 中不存在同时是两种勇士的敌人），也保证反制手段唯一。

### 6.1 判别依据：手持武器

| 生物 | 手持 | 勇士类型 |
| --- | --- | --- |
| 猪灵 `piglin` | 弩 | 屏障 |
| 猪灵 `piglin` | 近战武器（剑/斧） | 势不可挡 |
| 溺尸 `drowned` | 三叉戟 | 屏障 |
| 溺尸 `drowned` | 近战武器 | 势不可挡 |

### 6.2 实现警示（重要）

字节码分析发现：**原版猪灵同时持有弩与近战武器**，其逻辑是
"有弩就远程，近战武器只是备用"（`isHoldingMeleeWeapon` 与
`CrossbowAttackMob` / `CrossbowItem` 共存于同一类）。

因此**"看它手上拿什么"在实际游玩中几乎总是返回"弩"**，
「拿剑→势不可挡」的分支极少触发。

**推荐做法**：在**生成时**抽签决定勇士类型，然后**配发对应武器与装备**，
使武器跟随类型走。这样：

- 逻辑自洽，不存在"武器与类型不匹配"的状态
- 契合《命运2》"勇士是稀有精英变体"的定位
- 避免依赖原版武器的动态切换行为

---

## 7. 攻击类型证据

以下均为**字节码实测**，来自各类中的 Goal / Attack 标记，非人工推断。

| 生物 | 证据 | 结论 |
| --- | --- | --- |
| `AbstractSkeleton` | `RangedBowAttackGoal`, `BowItem`, `performRangedAttack` | 远程弓 |
| `Drowned` | `DrownedTridentAttackGoal`, `ThrownTrident` | 远程三叉戟（条件触发） |
| `Pillager` | `RangedCrossbowAttackGoal`, `CrossbowItem`, `isChargingCrossbow` | 远程弩 |
| `Witch` | `RangedAttackGoal`, `ThrownPotion`, `healRaidersGoal` | 远程投药 + 治疗他人 |
| `Evoker` | `EvokerSummonSpellGoal`, `EvokerAttackSpellGoal` | 召唤 + 尖牙 |
| `Illusioner` | `RangedBowAttackGoal`, `IllusionerMirrorSpellGoal`, `IllusionerBlindnessSpellGoal` | 弓 + 分身 + 致盲 |
| `Guardian` | `thorns`（激光为内置行为） | 远程激光 |
| `Ghast` | `GhastShootFireballGoal`, `LargeFireball`, `isCharging` | 远程火球 |
| `Shulker` | `ShulkerPeekGoal`, `teleportSomewhere`, `onEnderTeleport` | 远程弹 + 瞬移 |
| `Slime` | `onMobSplit`, `MobSplitEvent`, `resetHealth` | 分裂 |
| `EnderMan` | `teleport`, `teleportTowards`, `randomTeleport` | 瞬移 |
| `Warden` | `SonicBoom`, `sonicBoomAnimationState`, `attackAnimationState` | 近战 + 音波 |
| `Creeper` | `SwellGoal`, `Fuse`, `explodeCreeper` | 引信爆炸 |
| `Breeze` | `shoot`, `longJump`, `slide`, `jumpTrailStartedTick` | 远程风弹 + 高机动 |
| `Vex` | `VexChargeAttackGoal`, `noPhysics`, `isCharging` | 飞行冲撞 + 穿墙 |
| `Vindicator` / `Ravager` / `Silverfish` / `Endermite` / `EnderMan` | `MeleeAttackGoal` | 近战 |
| `Piglin` | `CrossbowAttackMob`, `CrossbowItem`, `isHoldingMeleeWeapon` | **双态** |
| `PiglinBrute` / `AbstractPiglin` | `isHoldingMeleeWeapon` | 近战 |
| `Hoglin` | `attackAnimationRemainingTicks` | 冲撞 |
| `Ravager` | `strongKnockback` | 冲撞 + 强击退 |

---

## 8. 已定决策汇总

| # | 决策 | 内容 |
| ---: | --- | --- |
| 1 | **家族互斥** | 一只生物只属于一个家族，保证勇士类型唯一 |
| 2 | **下界是栖息地** | 独立轴，不与家族争槽位；`magma_cube` 可两者兼具 |
| 3 | **灾厄 / 袭击者按战斗方式拆** | 施法远程 vs 兽近战 |
| 4 | **自建标签** | 不复用原版标签，显式列举成员 |
| 5 | **凋灵不做勇士** | 故亡灵族自建标签中排除 `wither` |
| 6 | **巨人排除** | 原版无攻击 AI，给任何类型都无意义 |
| 7 | **幻术师暂缓** | 机制特殊（分身/致盲），本期不做 |
| 8 | **双态 = 运行时决定** | 溺尸、猪灵生成时确定，非同时具备 |
| 9 | **僵尸疣猪兽归亡灵** | 家族＝亡灵/僵尸，栖息地＝下界 |
| 10 | **末影人单开一族** | 以纳入勇士候选池（家族敌对数为 0） |
| 11 | **骷髅族 = 屏障** | 由远程攻击类型直接决定 |
| 12 | **女巫 = 过载** | 因 `healRaidersGoal` 自愈/治疗能力 |
| 13 | **凋灵骷髅 = 势不可挡** | 破例：属骷髅族但无弓，纯近战 |
| 14 | **反制手段 = 附魔** | 三种勇士对应三种附魔，不用专用物品 |
| 15 | **三种附魔互斥** | 同一件武器只能拥有其中一种 |

---

## 9. 自建标签设计

### 9.1 为什么不复用原版标签

```java
// 错误示范 —— 会连凋灵一起抓进来，违反决策 5
public static final TagKey<EntityType<?>> UNDEAD = EntityTypeTags.UNDEAD;
```

两个原因：

1. **语义不符**：原版 `#undead` 含 `wither`，而我们不要它做勇士。
2. **稳定性**：若写成 `{"id": "#minecraft:undead"}`，
   **Mojang 更新时往原版标签加新怪，我们的家族划分会被动变形**，互斥性可能被破坏。

显式列举 + `"replace": false`（默认值）才能让其他 mod 通过数据包扩展——这正是 API 开放性所需。

### 9.2 标签文件

```json
// data/pantheon_champions/tags/entity_type/undead.json
{
  "replace": false,
  "values": [
    "minecraft:zombie",
    "minecraft:husk",
    "minecraft:drowned",
    "minecraft:zombie_villager",
    "minecraft:skeleton",
    "minecraft:stray",
    "minecraft:bogged",
    "minecraft:wither_skeleton",
    "minecraft:phantom",
    "minecraft:zoglin",
    "minecraft:zombified_piglin",
    "minecraft:skeleton_horse",
    "minecraft:zombie_horse"
  ]
}
```

其余家族同理：`arthropod` / `aquatic` / `illager` / `raider` / `piglin` /
`slime` / `ender` / `factionless`，以及独立的栖息地标签 `habitat/nether`。

### 9.3 Java 侧 API

```java
public final class ChampionFamilies {

    public static final TagKey<EntityType<?>> UNDEAD      = tag("undead");
    public static final TagKey<EntityType<?>> ARTHROPOD   = tag("arthropod");
    public static final TagKey<EntityType<?>> AQUATIC     = tag("aquatic");
    public static final TagKey<EntityType<?>> ILLAGER     = tag("illager");
    public static final TagKey<EntityType<?>> RAIDER      = tag("raider");
    public static final TagKey<EntityType<?>> PIGLIN      = tag("piglin");
    public static final TagKey<EntityType<?>> SLIME       = tag("slime");
    public static final TagKey<EntityType<?>> ENDER       = tag("ender");
    public static final TagKey<EntityType<?>> FACTIONLESS = tag("factionless");

    // 栖息地（独立轴）
    public static final TagKey<EntityType<?>> NETHER      = tag("habitat/nether");

    private ChampionFamilies() {}

    private static TagKey<EntityType<?>> tag(String name) {
        return TagKey.create(
                Registries.ENTITY_TYPE,
                ResourceLocation.fromNamespaceAndPath("pantheon_champions", name));
    }
}
```

**API 细节（1.21.1）**：

| 用途 | 正确写法 | 备注 |
| --- | --- | --- |
| 建 ResourceLocation | `ResourceLocation.fromNamespaceAndPath(ns, path)` | **`new ResourceLocation(...)` 已废弃** |
| 建标签键 | `TagKey.create(Registries.ENTITY_TYPE, rl)` | ✓ |

调用方（也是未来对外开放的部分）即一句 `entityType.is(ChampionFamilies.UNDEAD)`。
**因家族互斥，此判定安全。**

### 9.4 互斥性自动测试

开放 API 后，其他 mod 往标签里加东西可能破坏互斥。
建议加一个 gametest 断言"任一 EntityType 至多属于一个家族标签"，在 CI 阶段拦截。

---

## 10. 反制手段：附魔设计

**决策：三种勇士对应三种附魔，且三种附魔互斥。**

不使用专用物品、不做类图腾机制。理由是附魔天然满足 D2 系统的三个要求：
**可携带**（不占背包格子）、**有代价**（互斥即机会成本）、**与现有系统同构**
（MC 已有 smite / bane_of_arthropods 这套按族加伤的附魔）。

### 10.1 三种附魔

| 附魔 | 对应勇士 | 动词 | 效果方向 |
| --- | --- | --- | --- |
| `anti_barrier` | 屏障 | 破 | 破除护盾 |
| `anti_overload` | 过载 | 压 | 压制自愈 / 相位 |
| `anti_unstoppable` | 势不可挡 | 断 | 造成震慑 |

### 10.2 1.21.1 附魔机制（实测确认）

附魔在 1.21 **已完全数据驱动**：42 个原版附魔定义在
`data/minecraft/enchantment/*.json`，互斥是其中的 `exclusive_set` 字段。

```json
// data/minecraft/enchantment/smite.json（原版节选）
{
  "exclusive_set": "#minecraft:exclusive_set/damage",
  "max_level": 5,
  "slots": ["mainhand"],
  "supported_items": "#minecraft:enchantable/weapon",
  "effects": {
    "minecraft:damage": [
      {
        "effect": { "type": "minecraft:add",
                    "value": { "type": "minecraft:linear", "base": 2.5, "per_level_above_first": 2.5 } },
        "requirements": {
          "condition": "minecraft:entity_properties",
          "entity": "this",
          "predicate": { "type": "#minecraft:sensitive_to_smite" }
        }
      }
    ]
  }
}
```

**这是我们的模板**：`requirements` + `entity_properties` 就是"只在特定敌人身上生效"的写法。

### 10.3 硬约束一：`exclusive_set` 是**单值**的

反汇编 `Enchantment` 类确认：

```
Field exclusiveSet:Lnet/minecraft/core/HolderSet;   // 单个 HolderSet，不是 List
```

实测全部 42 个原版附魔：

| 检查 | 结果 |
| --- | --- |
| 含 `exclusive_set` 字段 | 18 个 |
| **含多个 `exclusive_set`** | **0 个** |
| 无 `exclusive_set` | 24 个 |

> **一条附魔只能属于一个互斥组。**
> 因此**不能**写成"同时与 `#champion` 和 `#damage` 互斥"——
> 若既要三种勇士附魔互相排斥、又要和原版伤害附魔排斥，
> 就必须把这些**全部放进同一个标签**。

### 10.4 硬约束二：互斥判定是**双向**的

`javap -c` 反汇编 `Enchantment.areCompatible` 的实际字节码：

```
 0: aload_0 / aload_1
 2: Holder.equals                     // 同一附魔 → 跳到 return false
10: a.value().exclusiveSet.contains(b)  // 方向 1
28: ifne → return false
31: b.value().exclusiveSet.contains(a)  // 方向 2
49: ifne → return false
52: iconst_1 → return true             // 双向都不含 → 兼容
```

**含义（对我们有利）**：只要**一方**把另一方列进自己的排他标签，两者就互斥。
所以三种附魔**各自**写 `"exclusive_set": "#pantheon_champions:exclusive_set/champion"`
即可互相排斥，不需要两两声明。

### 10.5 与原版伤害附魔的关系（已定：方案 A）

原版已有这个标签：

```json
// data/minecraft/tags/enchantment/exclusive_set/damage.json
{ "values": [ "minecraft:sharpness", "minecraft:smite", "minecraft:bane_of_arthropods",
              "minecraft:impaling", "minecraft:density", "minecraft:breach" ] }
```

注意：**smite / bane_of_arthropods / impaling 正是第 2.5 节的"按族克制"附魔。**

因 `exclusive_set` 单值，只有两种做法：

| 方案 | 做法 | 后果 |
| --- | --- | --- |
| **A. 独立组（已采用）** | 自建 `#pantheon_champions:exclusive_set/champion`，与原版伤害附魔**共存** | 武器可同时有 sharpness + 勇士附魔；勇士附魔只互相排斥 |
| B. 并入原版组 | 用 `replace: false` 向 `#minecraft:exclusive_set/damage` **追加**我们的三种 | 勇士附魔与 sharpness/smite 全部互斥，玩家必须**二选一** |

**决定：方案 A。** 理由——不与现有系统重复，且避开《命运2》被批评的"强制配装"问题
（见第 1 节的第 2、4 条教训）。玩家可以保留自己的伤害附魔，
勇士克制是**叠加的一层**，而不是替换关系。

实现文件：

```json
// data/pantheon_champions/tags/enchantment/exclusive_set/champion.json
{
  "values": [
    "pantheon_champions:anti_barrier",
    "pantheon_champions:anti_overload",
    "pantheon_champions:anti_unstoppable"
  ]
}
```

### 10.6 附魔如何识别勇士类型

勇士类型存在实体实例上（决策 8：双态需运行时决定），
而附魔效果是 JSON。实测 `EntityPredicate` 的字段（来自常量池 record 描述符）：

```
entityType; distanceToPlayer; movement; location; effects; nbt; flags;
equipment; subPredicate; periodicTick; vehicle; passenger; targetedEntity; team; slots
```

关键是有 **`nbt`** 字段（类型 `NbtPredicate`，类
`net/minecraft/advancements/critereon/NbtPredicate` 存在）。

**两条可行路径**：

| 路径 | 做法 | 评价 |
| --- | --- | --- |
| **NBT 判定** | 勇士类型写入实体 NBT，附魔用 `entity_properties.nbt` 匹配 | **纯 JSON，零代码**，推荐 |
| **自定义 SubPredicate** | 注册 `ENTITY_SUB_PREDICATE_TYPE`（`EntitySubPredicates` 可扩展） | 类型安全，但要写 Java |

**关键细节（javap 反汇编确认）**：`NbtPredicate` 匹配的是
`Entity.saveWithoutId()` 产出的 `CompoundTag`。而 NeoForge 的
`getPersistentData()` 内容**并非平铺在根标签**，而是挂在 **`NeoForgeData` 子标签**下：

```
480: aload_1
481: ldc   "NeoForgeData"          // 固定的子标签名
484: aload_0
485: getfield persistentData
488: invokevirtual CompoundTag.copy
```

所以谓词**必须带上这层前缀**，否则匹配不到：

```json
{ "nbt": "{NeoForgeData:{ChampionType:0}}" }
```

> 若同时使用 NeoForge **DataAttachment**（1.21 起推荐做法），
> 数据会序列化到 `neoforge:attachments` 子标签，路径又不同。
> 建议**只用 `getPersistentData()`**，路径更简单可控。

示例（纯 JSON 反制判定）：

```json
{
  "condition": "minecraft:entity_properties",
  "entity": "this",
  "predicate": { "nbt": "{NeoForgeData:{ChampionType:0}}" }
}
```

### 10.7 可用效果组件（32 个）

`EnchantmentEffectComponents` 实测字段，与勇士机制相关的：

| 组件 | 用途 |
| --- | --- |
| `minecraft:damage` | 条件加伤（smite 用的就是它）|
| `minecraft:post_attack` | 命中后施加效果（bane 用它上缓慢）|
| `minecraft:damage_immunity` | 免疫特定伤害 |
| `minecraft:damage_protection` | 减伤 |
| `minecraft:knockback` | 击退 |
| `minecraft:tick` | 周期性效果 |
| `minecraft:projectile_spawned` | 弹射物生成时 |
| `minecraft:attributes` | 属性修饰 |

**结论：三种勇士附魔的"反制效果"可以完全用 JSON 实现**
（`damage` + `post_attack` + 勇士类型条件），
而**勇士自身的护盾/自愈/冲锋行为必须用 Java 写在实体上**。

### 10.8 附魔定义（已实现）

> **状态：已实现并通过验证。** 文件位于
> `src/main/resources/data/pantheon_champions/enchantment/`。
> 下面记录的是**实际采用的**方案与验证方式。

#### 10.8.1 三个附魔

| 附魔 ID | 显示名（中 / 英） | 勇士类型 | 加伤 | 命中效果 |
| --- | --- | --- | --- | --- |
| `anti_barrier` | 反屏障 / Anti-Barrier | 屏障 (0) | +4 | 无（破盾交给实体侧 Java） |
| `anti_overload` | 反过载 / Anti-Overload | 过载 (1) | +4 | 虚弱 I，6 秒 |
| `anti_unstoppable` | 反势不可挡 / Anti-Unstoppable | 势不可挡 (2) | +4 | 缓慢 III，4 秒 |

**命名对齐《命运2》**：D2 里三种反制弹种就叫 Anti-Barrier / Anti-Overload /
Anti-Unstoppable（中文社区译作反屏障 / 反过载 / 反势不可挡），
所以 ID 与显示名都直接用这套，不再自己造「勇士克星·破/压/断」。

> **ID 是半永久的东西**：注册 ID 一旦发布，改动会让已有存档里的附魔
> 变成无效数据。趁现在只有骨架时改名是免费的，发布后就不是了。

三个都 `max_level: 1`、`weight: 2`、`anvil_cost: 4`、
`slots: ["mainhand"]`、`supported_items: "#minecraft:enchantable/weapon"`。

#### 10.8.1.1 兼容 Enchantment Descriptions 模组

描述写在 lang 文件里，**键格式**（已从该模组 1.21.1 分支的
`assets/enchdesc/lang/en_us.json` 核实）：

```
enchantment.<命名空间>.<附魔路径>.desc
```

即显示名键后面加 `.desc`。所以：

| 键 | 中文 | 英文 |
| --- | --- | --- |
| `...anti_barrier.desc` | 克制屏障勇士：破除其护盾，并对其造成额外伤害。 | Breaks Barrier Champions' shields... |
| `...anti_overload.desc` | 压制过载勇士：抑制其回复，造成额外伤害并施加虚弱。 | Suppresses Overload Champions' regeneration... |
| `...anti_unstoppable.desc` | 眩晕势不可挡勇士：打断其冲锋，造成额外伤害并施加缓慢。 | Staggers Unstoppable Champions... |

这三种附魔**不依赖该模组**：没装 ED 时 `.desc` 键只是一条没被引用的
翻译，不影响任何功能。

**为什么选虚弱 / 缓慢而不是直接写效果**：
D2 的"压"是压制回复、"断"是打断冲锋。MC 里没有现成的对应效果，
但虚弱（降低攻击力）在语义上贴近"压制"，缓慢（限制位移）贴近"打断冲锋"。
真正的护盾/自愈/冲锋逻辑必须写在实体上（Java），附魔这一层只做
**"打对了类型才有额外收益"**——这也符合第 1 节"反制应表达为技巧而非物品检查"的结论。

#### 10.8.2 踩过的坑：不能用 `entity_properties.type`

初版我写成了 `"predicate": { "type": "#pantheon_champions:champion" }`，
**这是错的**。`type` 匹配的是**实体类型**（zombie / skeleton 这种），
而"是不是勇士"是**单个实体的运行时状态**（决策 8：双态需运行时决定）。
用 type 会导致：**所有**僵尸都被当成屏障勇士，全都吃 +4 加伤。

必须用第 10.6 节的 NBT 判定，匹配实例数据：

```json
"predicate": { "nbt": "{NeoForgeData:{ChampionType:0}}" }
```

#### 10.8.3 路径已用字节码复核

`NbtPredicate.getEntityTagToCompare` 调用 `Entity.saveWithoutId`，
而 NeoForge 在 `saveWithoutId` 内部写入 `NeoForgeData` 子标签
（`javap -c` 确认：该方法字节码中出现 `ldc "NeoForgeData"`）。
所以 `NeoForgeData:` 这一层前缀是必需的，去掉就永远匹配不到。

#### 10.8.4 `run_function` 的取舍（**未采用**）

骨架里原本写的是 `minecraft:run_function` 调 `break_barrier`。
`RunFunction` 类确实存在（`javap` 确认），但它接收的是
`ResourceLocation` 并在**生效时**才去查函数表——
**函数不存在时不会在加载期报错，只在玩家命中时静默失败**。
这种"看起来配好了其实从不生效"的失败模式很难排查，
所以本次不使用 `run_function`，破盾逻辑留给实体侧 Java 实现。

#### 10.8.5 验证方式（三层，缺一不可）

| 脚本 | 验证内容 | 为什么需要这一层 |
| --- | --- | --- |
| `Tools/verify-enchant-structure.ps1` | 文件合法、均 1 级、三者指向同一标签、标签恰好覆盖三者、未混入原版伤害组，并代入双向算法推导两两互斥 | 静态但充分——互斥判定已用字节码确认，可直接代入 |
| `Tools/verify-enchant-datapack.ps1` | **专用服务端**启动，附魔注册表解析无报错 | 附魔是**数据包注册表**，只在服务端启动时构建。客户端停在标题界面时根本没解析，那时"无报错"是假证据 |
| `Tools/verify-enchant-in-world.ps1` | 进世界后无注册表报错 | 覆盖单人存档路径 |

**关键认知**：客户端标题界面只能证明**资源包**（sounds/lang/models）
没问题，证明不了**数据包注册表**（enchantment/tags）。
这两件事必须分开验证。

```json
// 实际实现（data/pantheon_champions/enchantment/anti_barrier.json）
{
  "description": { "translate": "enchantment.pantheon_champions.anti_barrier" },
  "exclusive_set": "#pantheon_champions:exclusive_set/champion",
  "max_level": 1,
  "weight": 2,
  "anvil_cost": 4,
  "max_cost": { "base": 30, "per_level_above_first": 0 },
  "min_cost": { "base": 15, "per_level_above_first": 0 },
  "slots": ["mainhand"],
  "supported_items": "#minecraft:enchantable/weapon",
  "primary_items": "#minecraft:enchantable/sharp_weapon",
  "effects": {
    "minecraft:damage": [
      {
        "effect": { "type": "minecraft:add", "value": 4.0 },
        "requirements": {
          "condition": "minecraft:entity_properties",
          "entity": "this",
          "predicate": { "nbt": "{NeoForgeData:{ChampionType:0}}" }
        }
      }
    ]
  }
}
```

`anti_overload` / `anti_unstoppable` 在此基础上多一个 `minecraft:post_attack` 块，
条件是 `all_of`：NBT 匹配 + `damage_source_properties.is_direct`
（照抄原版 `bane_of_arthropods` 的写法，确保只有直接命中才触发）。

### 10.10 创造模式标签页

**先说限制**：创造标签页只能放**物品**（`ItemLike`），而附魔是数据包注册表里的
一条记录，**不是物品**。所以「附魔标签页」没法直接列出附魔本身，
只能列出**附了这些附魔的附魔书**。原版也是这个逻辑——原版创造模式根本不提供
附魔书，附魔要靠铁砧或 `/enchant`。

当前内容：三本附魔书（`enchanted_book` 各附一种勇士附魔）。
图标：**不死图腾**（`Items.TOTEM_OF_UNDYING`，用户指定，语义贴合"扛住致命一击"；
等有正式图标资源再换）。

实现要点：

- 标签页是**注册表**（`Registries.CREATIVE_MODE_TAB`），要 `DeferredRegister`
  挂到 mod 事件总线。
- 附魔必须通过 `params.holders().lookupOrThrow(Registries.ENCHANTMENT)` 取，
  **不能**像物品那样用静态字段引用——标签页构建时注册表才可用。
- 用 `getOrThrow` 而不是 `get`：附魔是本模组自己的数据包文件，
  缺了就是打包错误，应该立刻炸出来，而不是静默少一本书。
- ⚠️ `displayItems` **只在客户端打开创造物品栏时执行**。
  服务端启动、`gradlew build` 都不会跑它——所以「编译通过」和
  「服务端无报错」都证明不了标签页能用。为此加了静态交叉校验
  （`verify-enchant-structure.ps1` 第 9 节）：把 Java 里 `CHAMPION_ENCHANTMENTS`
  数组的字符串与 `data/.../enchantment/` 下的实际文件名比对，
  **已用负例验证过**（把 `anti_barrier` 拼成 `anti_barrior`，检查会 FAIL 并点名两侧）。

标签页标题键：`itemGroup.pantheon_champions.champions`。

---

## 11. 待定决策

1. **三种附魔的具体数值与反制效果**
   破盾需要几次命中、压制持续多久、震慑窗口多长。
   **已给出可调默认值**，见 `champions-common.toml`（20 个数值项）。
2. **双态的抽签概率**
   默认 `dualState.barrierRatio = 0.5`；成为勇士的总概率
   默认 `general.championChance = 0.12`。可调。
3. **栖息地修饰符的具体效果**
   默认下界勇士概率 ×1.5、护盾 ×1.5。可调。
4. **非敌对生物是否纳入候选池**
   末影人、猪灵、僵尸猪灵目前**已纳入**（家族存在即纳入），
   由 `general.affectNeutralMobs` 控制；
   但 `skeleton_horse`、`zombie_horse`、`bee` 等仍未决定。
5. **勇士自身行为是否用 Java 实现**
   护盾 / 自愈 / 冲锋必须写在实体上（JSON 无法表达），需确定实现方式。见 10.7。

---

## 12. 实现分工（附魔 vs 实体）

这是本设计最容易混淆的一点：

| 部分 | 实现方式 | 原因 |
| --- | --- | --- |
| **反制手段**（三种附魔） | **纯 JSON** | 数据驱动附魔 + `entity_properties` 条件足够 |
| **勇士类型标记** | 实体 NBT（`NeoForgeData` 下的 `ChampionType`） | 双态需运行时决定 |
| **勇士自身行为** | **Java** | 护盾再生、自愈、冲锋节奏 JSON 无法表达 |
| **类型分配**（生成时） | Java（NeoForge 事件） | 需拦截实体生成 |

---

## 13. 配置文件

`champions-common.toml` 已生成并验证（39 项，9 个分类，102 行注释）。

**验证方式**（非人工检查，而是实际执行）：

| 检查 | 结果 |
| --- | --- |
| `javac -Xlint:all` 编译 | **零警告零错误** |
| `ModConfigSpec.correct()` | 39 项全部正确填充 |
| 生成文件重新解析 | **成功** |
| `spec.isCorrect(重新解析)` | **true**（文件与 spec 完全一致）|
| 越界值 `championChance = 5.0` | **false**（范围校验生效）|
| 残留 HTML 标签 | 无 |

配置分类：`general` / `types` / `dualState` / `barrier` / `overload` /
`unstoppable` / `habitat` / `enchantment` / `debug`。

**实现要点**（`ChampionsConfig.java`）：

```java
public static final ModConfigSpec SPEC;
static {
    ModConfigSpec.Builder b = new ModConfigSpec.Builder();
    b.comment("注释必须非空——全空白注释会让 NeoForge 在开发环境抛异常。")
     .push("general");
    ENABLED = b.comment("总开关。").define("enabled", true);
    CHAMPION_CHANCE = b.comment("基础概率。")
                       .defineInRange("championChance", 0.12D, 0.0D, 1.0D);
    b.pop();
    SPEC = b.build();
}
```

注册（mod 主类）：

```java
public MyMod(IEventBus bus, ModContainer container) {
    container.registerConfig(ModConfig.Type.COMMON, ChampionsConfig.SPEC);
}
```

**已核实的 API 事实**（来自 `neoforge-21.1.250-sources.jar` 源码与 FML 字节码）：

| 项目 | 事实 |
| --- | --- |
| `ModConfig.Type` 常量 | `COMMON` / `CLIENT` / `SERVER` / `STARTUP` |
| 注册方法 | `ModContainer.registerConfig(Type, IConfigSpec)` |
| `comment()` 作用域 | 只作用于**紧邻的下一个** `define`（`define` 后 `context` 重置）|
| 全空白注释 | 开发环境**抛 `IllegalStateException`**，生产环境记警告 |
| `defineList` | 3 参版本**已废弃**，须用 4 参版（含 `newElementSupplier`）|

> **踩坑记录**：`ConfigParser.parse(String)` 接收的是 **TOML 内容**而非文件路径。
> 传路径会让解析器把 `C:\...` 当配置读，报
> `Invalid character ':' after key [C]`——这个 `[C]` 是盘符，与中文注释无关。

---

*归类为设计定稿。生物清单、家族划分、攻击类型均已与本地 1.21.1 游戏数据逐项核对。*
