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
Gradle 9.4.0（走腾讯镜像，因为 `services.gradle.org` 在本机证书链校验失败）。

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

## 已知未完成
- 配置里 20 个数值是**初始默认值，未做平衡测试**。
- 勇士实体行为（护盾 / 自愈 / 冲锋）与生成时类型分配尚未实现（需 Java）。
- 族类标签（`data/pantheon_champions/tags/entity_type/*.json`）还没写，
  DESIGN.md 第 9 节有设计；目前只有附魔互斥标签。
- 三种附魔的 JSON 定义还没写（已有互斥标签，附魔本体缺）。
- `runServer` 未单独验证（两者 mod 加载路径相同）。
