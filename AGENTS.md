# Pantheon: Champions

Minecraft 1.21.1 / NeoForge 把《命运2》的三种勇士（Barrier 屏障 / Overload 过载 /
Unstoppable 势不可挡）搬进 MC。

- 设计文档：`DESIGN.md`（先读它，里面有全部已定决策）
- modid / 命名空间：`pantheon_champions`
- Java 包：`beiwu.pantheon_champions`
- 项目名（人读）：**Pantheon: Champions**

## 命名规则（已从字节码核实，别猜）
- modid 正则（`net/neoforged/fml/loading/moddiscovery/ModInfo.class`）：
  `^[a-z][a-z0-9_]{1,63}$` —— **不允许 `.` 和 `-`**。
- 命名空间字符集（`ResourceLocation.validNamespaceChar`）：
  `_` `-` `a-z` `0-9` `.` —— 比 modid 宽松。
- 结论：`pantheon-champions` 做命名空间合法、做 **modid 会加载失败**。
  唯一同时满足两者的是 `pantheon_champions`。

## 构建与验证
**不要手写 javac 命令**，用现成脚本：

```
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\build-and-verify.ps1
```

它调用 Gradle：`gradlew build`（编译 main + test）→ `gradlew verifyConfig`
（跑 `TomlHarness` 重新生成 TOML 并回读校验）→ 同步 `src/main/resources/` 副本。
**退出码 0 才算通过**。

也可以直接用 Gradle 任务：

```
.\gradlew.bat build           # 编译并打包
.\gradlew.bat verifyConfig    # 只重生 + 校验配置
.\gradlew.bat runClient       # 启动游戏
```

> **注意**：`verifyConfig` 是 `build.gradle` 里的 `JavaExec` 任务。
> 以前 PowerShell 脚本自己维护依赖 jar 列表，**同一个坑踩了四次**
> （`-sources.jar` 匹配、`IEventBus`、`slf4j`、`Dist` 各缺一次），
> 每次都表现为莫名其妙的编译错误。现在类路径交给 Gradle 解析，
> **不要再往脚本里加 jar 列表**。

依赖版本（`gradle.properties`）：MC 1.21.1 / NeoForge 21.1.250 / ModDevGradle 2.0.141 /
Gradle 9.4.0（走腾讯镜像，因为 `services.gradle.org` 在本机证书链校验失败）/
GeckoLib 4.9.3 / JEI 19.57.0.449 / Jade 15.10.6+neoforge（后两个仅开发期，见下）。

## 前置依赖：GeckoLib（已实机验证）
用来做模型和动画。**1.21.1 属于 GeckoLib 4.x 线**，坐标与当前官网文档不同，
照官网抄会失败：

| 项 | 值 | 说明 |
|---|---|---|
| group | `software.bernie.geckolib` | **不是** `com.geckolib` |
| artifact | `geckolib-neoforge-1.21.1` | artifact 名内嵌 MC 版本 |
| 版本 | `4.9.3` | |
| Maven | `https://dl.cloudsmith.io/public/geckolib3/geckolib/maven/` | |

**三个已核实的坑**：
1. **官网 wiki 的 group 是错的（对本版本而言）**。`wiki.geckolib.com` 的
   GeckoLib5 页写 `com.geckolib`，但那对 1.21.1 **404**。1.21.1 必须用
   `software.bernie.geckolib`（已下载 jar 对比 SHA1 确认）。
2. **wiki 的版本支持表滞后**。表里 1.21.1 只写到 `4.8.3`，但 Maven 上
   `geckolib-neoforge-1.21.1` 已发布到 `4.9.3`（`lastUpdated` 2026-09-16）。
   表不是兼容性上限。本项目用 4.9.3，且**运行时实测装载成功**。
3. **不需要 mclib，也不需要 mixin 插件**。那是 1.20.4 及以下的做法。
   1.20.5+ 只需一行 `implementation`（官方 Installation-(Geckolib4) 文档确认，
   且该 jar 的 Gradle module 元数据声明零传递依赖）。

`GeoEntity` 是**接口**（`javap` 已确认），所以勇士实体可以
`extends Monster implements GeoEntity` —— 这点很关键，因为勇士必须是敌对生物。

验证脚本：`Tools\verify-geckolib.ps1`（启动 runClient，从日志确认 GeckoLib
与本 mod 同时出现在 mod 列表）。**不要拿 `gradlew build` 成功冒充运行时装载成功**，
两者失败方式完全不同。

## 开发期辅助模组：JEI 与 Jade（已实机验证装载）
**这两个只在开发环境用**，用来在游戏里核对本模组自己的内容：
JEI 看附魔书能不能正常进物品栏、Jade 直接读实体 NBT。

| 项 | JEI | Jade |
|---|---|---|
| 坐标 | `mezz.jei:jei-1.21.1-neoforge` | `maven.modrinth:jade` |
| 版本属性 | `jei_version=19.57.0.449` | `jade_version=15.10.6+neoforge` |
| 仓库 | `https://maven.blamejared.com` | `https://api.modrinth.com/maven` |

**四个已核实的坑**：

1. **JEI 有传递依赖，且都不在 Maven Central。** 主 artifact 依赖
   `jei-1.21.1-common` / `-lib` / `-gui`，只在 BlameJared 仓库有。
   所以**那个仓库不能省**，否则解析直接失败。已实测解析出完整依赖树。
2. **JEI 还有个 `-neoforge-api` artifact，但只有 2.7 KB**，里面仅
   `mezz/jei/api/neoforge/NeoForgeTypes.class` 三个类，
   **不是完整 API**。想用 JEI 的 API 得依赖主 artifact，别被名字骗了。
3. **Jade 没有自己的 Maven**，只在 Modrinth 上。
   坐标的 group 是 `maven.modrinth`、artifact 是 **slug**（`jade`），
   不是 Modrinth 的项目 id（`nvQzSEkH`）——两种都挂在一份 metadata 下，
   用 slug 即可。
4. **Jade 的版本号带 `+`**（`15.10.6+neoforge`）。
   `+` 在 Maven 版本语法里是**动态版本通配符**，理论上 Gradle 会拒绝。
   实测**直接写属性可以正常解析**，所以没有做特殊处理；
   万一将来 Gradle 改严格了，正确修法是加 dependency-resolution
   规则，**不是**去掉 `+`（`+` 是人家发布的正式名字的一部分）。

**最重要的性质：它们是 `compileOnly` + `runtimeOnly`，绝不是 `implementation`，
也绝不写进 `neoforge.mods.toml`。** 出厂 mod 必须能在没有 JEI/Jade 时正常工作。
已回读校验出厂 jar 内的 `META-INF/neoforge.mods.toml`：
依赖块只有 `neoforge` / `minecraft` / `geckolib`，**没有 jei、没有 jade**。

验证脚本：`Tools\verify-devtools.ps1`（启动 runClient，确认两者出现在资源重载
列表、插件加载成功、且无 `Missing or unsupported mandatory dependencies`
之类的装载报错）。**`gradlew dependencies` 解析成功只证明能下到 jar，
不证明能被装载**——这两件事失败方式不同，别混为一谈。

## 本地参考资料
`docs-reference/`（已 gitignore）是上游文档的浅克隆，不用反复抓网页：
- `geckolib-wiki/` —— 新版 wiki 源码。**`docs/` 是 GeckoLib 5 的文档，本项目
  用不了**（`docs/index.mdx` 自己写着 "Wiki for GeckoLib5"）。
  `versioned_docs/version-geckolib4/` **只有一页存根**，仅版本表。
- `geckolib4-old-wiki/` —— 4.x 文档。**结构可用，但示例代码过期**
  （`new ResourceLocation(...)`、`getModelLocation()` 在 4.9.3 都编译不过）。
- `neoforge-docs/versioned_docs/version-1.21.1/` —— NeoForge 官方文档
  **1.21.1 版本**（63 篇）。注意要用带版本号的目录，**不要读 `docs/`**，
  那是最新版（1.21.11），API 与本项目不一致。

**GeckoLib 4.9.3 的权威依据是 jar 本身，不是任何 wiki**：
- 看签名：`javap -p -cp <geckolib-neoforge-1.21.1-4.9.3.jar> <类名>`
  （两个 jar 都在 `~/.gradle/caches/modules-2/files-2.1/software.bernie.geckolib/`）
- 看源码：解包 `geckolib-neoforge-1.21.1-4.9.3-sources.jar`

本模组的 GeckoLib 实施细节（类结构、路径规则、坑）已整理到 **`GECKOLIB.md`**，
写实体/模型/渲染器前先读它，不要直接照 wiki 抄。

需要更新时：`git -C docs-reference/<目录> pull`。

## 浏览器自动化
`C:\Users\Admin\.dsh\tools\browser\browser.mjs`（DSH 级工具，不在项目内）。
用 `node` 直接调用，驱动真实 Chrome 154，带界面可观察，复用已装 Chrome
不额外下载内核。支持 goto/text/html/links/click/fill/press/wait/eval/shot/close。

**为什么不用 MCP**：DSH 的 `dsh-mcp-client` 已安装，能把 chrome-devtools-mcp
变成原生工具，但实测那会**常驻 30 个工具、每请求约 7,500 token**。
本脚本按需启动、用完退出，静态成本为 0。

**限制**：当前模型不支持读图，所以 `shot` 能生成截图但**我看不到内容**。
看渲染结果要靠 `eval` 提取 DOM 数据，或截图后由人来看。

## 已核实的硬约束（踩过的坑，别重犯）
1. **`MobType` 枚举在 1.21.1 已被移除**。老教程里的 `MobType.UNDEAD` 编译不过。
   判断亡灵要用 `entityType.is(EntityTypeTags.UNDEAD)`。
2. **附魔 `exclusive_set` 是单值**（`HolderSet`，不是 List），
   且互斥判定是**双向**的（`Enchantment.areCompatible`）。
   所以三种勇士附魔各自只写 `"exclusive_set": "#pantheon_champions:exclusive_set/champion"`
   即可，不需要两两声明。
3. **标签 JSON 用对象形式** `{"values": [...]}`，不是裸数组。
4. **NeoForge 的 `getPersistentData()` 存放在 `NeoForgeData` 子标签下**，
   不在根。NBT 谓词要写 `{ "nbt": "{NeoForgeData:{ChampionType:0}}" }`。
5. **`ConfigParser.parse(String)` 收的是 TOML 内容，不是文件路径**。
   传路径会把 `C:\...` 当配置读，报 `Invalid character ':' after key [C]`
   （`[C]` 是盘符）。这个报错跟中文注释无关。
6. `ModConfigSpec` 的 `comment()` 必须是**非空**字符串，
   全空白注释在开发环境会抛 `IllegalStateException`。
7. `comment()` 只作用于**紧邻的下一个** `define`（每次 define 后 context 重置）。
8. 不要用 3 参 `defineList`（已废弃），用 4 参版（含 `newElementSupplier`）。
9. **`ProcessResources` 必须显式设 `filteringCharset = 'UTF-8'`**。
   它默认用平台编码读模板，本机是 GBK。模板里有中文时，按 GBK 解析 UTF-8
   字节不仅变乱码，**某些字节序列还会把紧跟的换行一起吃掉**，导致下一行被
   并进注释里。实测中 `[[dependencies]]` 表头被吞掉过，整个依赖块静默失效
   ——`build` 依然成功，只有打开生成的 toml 才看得出来。
   凡是往 `src/main/templates/` 里写非 ASCII 内容，都要注意这条。
10. **改了 `expand` / 模板后要 `clean` 再验**。`generateModMetadata` 是
   `ProcessResources` 任务，输入没变时会 UP-TO-DATE，光看 `build` 成功会
   读到上次的旧产物。
11. **Java 源码编码已在 `build.gradle` 里钉死为 UTF-8**（`options.encoding`，
    以及 Test / JavaExec 的 `file.encoding`）。**不要删掉这几行**。
    不设时 javac 按平台默认编码读源码，本机是 GBK；而 `ChampionsConfig`
    里的中文是**字符串字面量**，会写进出厂的 TOML 配置文件，属于用户可见文本。
    GBK 下「恰好能用」是因为读和写两端自洽，但只要出现 GBK 映射不了的字符
    就会坏掉，且报错通常不指向真正的原因。

## Java 注释语言
**本模组的 Java 注释一律用中文写**：类头 Javadoc、方法说明、行内注释都是。
`ChampionsConfig` 是范例，照它的风格来。

注意 `comment(...)` 的参数是**字符串**而不是注释，但它也是中文——那是给玩家
看的配置说明，会写进 `pantheon_champions-common.toml`。改它等于改用户可见文本，
验证时要连带检查 TOML 是否有乱码（`Tools\build-and-verify.ps1` 会重生该文件）。

## 声音资源
- 音频必须放 `assets/pantheon_champions/sounds/`。**`assets/<命名空间>/` 这层
  不能少**——直接放 `resources/sounds/` 是死数据，游戏永远找不到。
- **MC 只支持 `.ogg`（Vorbis）**，不认 MP3/Opus。
- **必须是单声道**。立体声不受 OpenAL 衰减影响，会永远在玩家位置播放；
  官方文档已明确警告这条。转码：
  `ffmpeg -i 输入 -ac 1 -c:a libvorbis -q:a 5 输出.ogg`
  （ffmpeg 9.0.1 已装，位于 `%LOCALAPPDATA%\Microsoft\WinGet\Packages`，
  PATH 别名在 `%LOCALAPPDATA%\Microsoft\WinGet\Links`）。
- 光有音频不会响，还需要两样：
  1. `assets/pantheon_champions/sounds.json` —— 把事件名映射到文件
  2. Java 里注册 `SoundEvent`（见 `ChampionsSounds`）
- 验证脚本 `Tools\verify-sounds.ps1`：启动游戏后检查资源重载是否完成、
  有无声音加载报错。**`build` 成功不代表声音能用**，只有日志能证明。

## 设计要点（详见 DESIGN.md）
- MC 有 **4 套并行的分类体系**：`MobCategory`（只管生成规则）、
  `Enemy` 接口（权威的敌对判定）、`EntityTypeTags`（族类）、AI 基类。
- 族类**互斥**，栖息地（如下界）是**独立的第二轴**，两者不抢槽位。
- 勇士类型由**族类 + 攻击类型**共同决定；骷髅一族 = 屏障。
- 双态（溺尸 / 猪灵）：运行时决定，一只怪不会同时是两种勇士。
- 反制手段用**附魔**承载，三种互斥，但**不与**原版 sharpness/smite 互斥（方案 A）。
- 巨人 `giant` 不给勇士类型（没有攻击 AI）；`wither` 也不给；
  `illusioner` 暂缓。这些都可配置。

## 已完成的骨架
- `build.gradle` / `settings.gradle` / `gradle.properties` / `gradlew`（Gradle 9.4.0）
- `src/main/templates/META-INF/neoforge.mods.toml`（由 `generateModMetadata` 填充变量）
- 主类 `PantheonChampions`（`@Mod`，构造器 `(IEventBus, ModContainer)`，
  注册 `ChampionsConfig.SPEC` 为 `ModConfig.Type.COMMON`）
- `gradlew build` **BUILD SUCCESSFUL**，产出
  `build/libs/pantheon_champions-1.21.1-neoforge-0.1.0.jar`
- **`gradlew runClient` 已实机验证**：日志出现
  `Pantheon: Champions 0.1.0 (pantheon_champions)`、
  `[Pantheon: Champions/]: Pantheon: Champions loading`、
  `Reloading ResourceManager: ... mod/pantheon_champions`，
  游戏正常进到标题界面，并在 `run/config/` 生成配置文件。

> 游戏写入的 `run/config/pantheon_champions-common.toml` 与仓库里的副本
> **键值完全相同，仅顺序不同**（NeoForge 用文件配置，键序＝声明顺序；
> TomlHarness 用内存配置）。以游戏写入的顺序为准。

## 已完成的：三种勇士附魔
`src/main/resources/data/pantheon_champions/enchantment/` 下三个 JSON，
均 `max_level: 1`、互斥（走 `#pantheon_champions:exclusive_set/champion`）：

| 附魔 ID | 显示名（中） | 勇士类型 | 加伤 | 命中效果 |
| --- | --- | --- | --- | --- |
| `anti_barrier` | 反屏障 | 屏障 (0) | +4 | 无 |
| `anti_overload` | 反过载 | 过载 (1) | +4 | 虚弱 I / 6s |
| `anti_unstoppable` | 反势不可挡 | 势不可挡 (2) | +4 | 缓慢 III / 4s |

**命名对齐《命运2》**（Anti-Barrier / Anti-Overload / Anti-Unstoppable）。
早期用的 `champion_breaker` 等名字已废弃——**ID 一旦发布就不能再改**，
改了会让存档里的附魔变无效数据。

**兼容 Enchantment Descriptions 模组**：描述键是
`enchantment.<命名空间>.<附魔路径>.desc`（从该模组 1.21.1 分支核实）。
不依赖该模组，没装时只是没被引用的翻译。

条件用 **NBT 判定** `{NeoForgeData:{ChampionType:N}}`，**不是**
`entity_properties.type`——`type` 匹配实体类型，而"是不是勇士"是实例运行时状态，
用 `type` 会让所有僵尸都吃加伤。**未采用 `run_function`**：它延迟解析函数引用，
函数不存在时加载期不报错、只在命中时静默失败。

## 已完成的：创造模式标签页
`beiwu/pantheon_champions/creativetab/ChampionsCreativeTabs.java`，
标签页 id `champions`，图标**不死图腾**（用户指定）。

⚠️ **创造标签页只能放物品，附魔不是物品**，所以里面放的是
**三本附了勇士附魔的附魔书**。想「列出附魔本身」在 MC 里做不到。

⚠️ **`displayItems` 只在客户端打开创造物品栏时执行**——服务端启动和
`gradlew build` 都不跑它。所以标签页没法靠日志证明正确，
真正管用的是**静态交叉校验**：`verify-enchant-structure.ps1` 第 9 节
把 Java 里 `CHAMPION_ENCHANTMENTS` 数组的字面量与
`data/.../enchantment/` 下的实际文件名比对，并检查图标是不死图腾。
**该检查已用负例验证过**（把 `anti_barrier` 拼成 `anti_barrior` → FAIL 并点名两侧）。

验证脚本（三层，**都要能跑**）：
- `Tools/verify-enchant-structure.ps1` —— 静态检查：文件合法性、均 1 级、
  三者指向同一标签、标签恰好覆盖三者、未混入原版伤害组，代入双向互斥算法
  推导两两互斥，外加 lang 键（含 ED 描述）与创造标签页的交叉校验
- `Tools/verify-enchant-datapack.ps1` —— 启动**专用服务端**验证注册表解析
- `Tools/verify-enchant-in-world.ps1` / `verify-enchantments.ps1` —— 进世界 / 资源包路径
- `Tools/verify-creative-tab.ps1` —— 客户端启动，抓标签页注册报错

> **关键认知**：客户端标题界面只能证明**资源包**（sounds/lang/models），
> 证明不了**数据包注册表**（enchantment/tags）。附魔只在**服务端启动**时构建，
> 所以停在标题界面时"无报错"是**假证据**。这两件事必须分开验证。
>
> `verify-enchant-datapack.ps1` 已用**负例**验过：故意把 `minecraft:damage`
> 改成 `minecraft:damage_TYPO`，服务端拒绝加载（`Failed to load registries`），
> 脚本正确抓到并点名文件；恢复后通过。

## 已知未完成
- 配置里 20 个数值是**初始默认值，未做平衡测试**。
- **勇士实体行为（护盾 / 自愈 / 冲锋）与生成时类型分配尚未实现（需 Java）。**
  ⚠️ 这也意味着**目前没有任何代码写入 `ChampionType` 这个 NBT**，
  所以三种附魔现在能加载、能互斥、能附到武器上，
  但**对普通怪物不产生额外效果**——这是预期状态，等实体行为落地后才连通。
- 族类标签（`data/pantheon_champions/tags/entity_type/*.json`）还没写，
  DESIGN.md 第 9 节有设计；目前只有附魔互斥标签。
- GeckoLib 的实体/模型/渲染器一行代码都还没写（实施指南见 `GECKOLIB.md`）。
- `runServer` 已通过 `verify-enchant-datapack.ps1` 验证（不再是缺口）。
