package beiwu.pantheon_champions.config;

import java.util.List;

import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * 勇士（Champion）系统配置。
 *
 * <p>本类只负责「数值与开关」。勇士的家族划分、勇士类型归属属于<b>数据</b>，
 * 放在 {@code data/pantheon_champions/tags/entity_type/*.json}，不在此处。</p>
 *
 * <p>用法：在 mod 主类构造函数中注册（见 {@code PantheonChampions}）</p>
 * <pre>{@code
 * public PantheonChampions(IEventBus modBus, ModContainer container) {
 *     container.registerConfig(ModConfig.Type.COMMON, ChampionsConfig.SPEC);
 * }
 * }</pre>
 *
 * <p><b>注意</b>：所有 {@code comment()} 必须非空——NeoForge 在开发环境下
 * 遇到全空白注释会直接抛 {@code IllegalStateException}（已核对 ModConfigSpec 源码）。</p>
 */
public final class ChampionsConfig {

    /** 双态生物（溺尸 / 猪灵）决定勇士类型的方式。 */
    public enum DualStateMode {
        /**
         * 生成时随机抽签决定，并配发对应武器。
         * 推荐：逻辑自洽，不存在「武器与类型不匹配」的状态。
         */
        RANDOM,
        /**
         * 按手持武器决定。注意原版猪灵默认持弩，
         * 其近战武器只是备用，因此「近战 → 势不可挡」分支极少触发。
         */
        WEAPON
    }

    public static final ModConfigSpec SPEC;

    // ---- 总开关 ----
    public static final ModConfigSpec.BooleanValue ENABLED;
    public static final ModConfigSpec.DoubleValue CHAMPION_CHANCE;
    public static final ModConfigSpec.BooleanValue AFFECT_NEUTRAL_MOBS;
    public static final ModConfigSpec.ConfigValue<List<? extends String>> BLACKLIST;

    // ---- 勇士属性 ----
    public static final ModConfigSpec.DoubleValue HEALTH_MULTIPLIER;
    public static final ModConfigSpec.DoubleValue DAMAGE_MULTIPLIER;

    // ---- 发光描边 ----
    public static final ModConfigSpec.BooleanValue GLOW_ENABLED;
    public static final ModConfigSpec.BooleanValue GLOW_TEAM;

    // ---- 双态 ----
    public static final ModConfigSpec.EnumValue<DualStateMode> DUAL_STATE_MODE;
    public static final ModConfigSpec.DoubleValue DUAL_STATE_BARRIER_RATIO;

    // ---- 屏障 ----
    public static final ModConfigSpec.DoubleValue BARRIER_SHIELD_POINTS;
    public static final ModConfigSpec.IntValue BARRIER_SHIELD_DURATION;
    public static final ModConfigSpec.IntValue BARRIER_REGEN_DELAY;
    public static final ModConfigSpec.DoubleValue BARRIER_REGEN_PER_SECOND;
    public static final ModConfigSpec.IntValue BARRIER_BREAK_STUN;

    // ---- 过载 ----
    public static final ModConfigSpec.DoubleValue OVERLOAD_REGEN_PER_SECOND;
    public static final ModConfigSpec.IntValue OVERLOAD_DISRUPTION_DURATION;
    public static final ModConfigSpec.BooleanValue OVERLOAD_PHASE_ENABLED;
    public static final ModConfigSpec.IntValue OVERLOAD_PHASE_INTERVAL;

    // ---- 势不可挡 ----
    public static final ModConfigSpec.DoubleValue UNSTOPPABLE_DAMAGE_REDUCTION;
    public static final ModConfigSpec.IntValue UNSTOPPABLE_CHARGE_WINDUP;
    public static final ModConfigSpec.IntValue UNSTOPPABLE_STAGGER_WINDOW;
    public static final ModConfigSpec.IntValue UNSTOPPABLE_STAGGER_DURATION;

    // ---- 栖息地修饰符 ----
    public static final ModConfigSpec.BooleanValue HABITAT_NETHER_ENABLED;
    public static final ModConfigSpec.DoubleValue HABITAT_NETHER_CHANCE_MULT;
    public static final ModConfigSpec.DoubleValue HABITAT_NETHER_SHIELD_MULT;

    // ---- 反制附魔 ----
    public static final ModConfigSpec.BooleanValue ENCHANT_TABLE_ENABLED;
    public static final ModConfigSpec.BooleanValue ENCHANT_LOOT_ENABLED;
    public static final ModConfigSpec.BooleanValue ENCHANT_TRADE_ENABLED;

    // ---- 调试 ----
    public static final ModConfigSpec.BooleanValue DEBUG_LOG_ASSIGNMENTS;
    public static final ModConfigSpec.BooleanValue DEBUG_SHOW_TYPE_ABOVE_HEAD;

    static {
        ModConfigSpec.Builder b = new ModConfigSpec.Builder();

        // ================= general =================
        b.comment("勇士系统总开关与生成概率。",
                  "规则：敌对性决定候选池，家族互斥决定勇士类型。")
         .push("general");

        ENABLED = b.comment("勇士系统总开关。关闭后所有生物按原版行为生成。")
                  .define("enabled", true);

        CHAMPION_CHANCE = b.comment("生成时成为勇士的基础概率（0.0 ~ 1.0）。",
                                    "0.12 表示约每 8 只候选生物出现 1 只勇士。",
                                    "注意：这是「基础值」，实际值还会乘以栖息地等修饰符。")
                           .defineInRange("championChance", 0.12D, 0.0D, 1.0D);

        AFFECT_NEUTRAL_MOBS = b.comment("是否允许行为中立的生物成为勇士。",
                                        "影响的生物：末影人、猪灵、僵尸猪灵。",
                                        "它们实现了 Enemy 接口，但不会主动攻击玩家。")
                              .define("affectNeutralMobs", true);

        BLACKLIST = b.comment("禁止获得勇士形态的实体 ID 列表。",
                              "默认排除 minecraft:giant —— 原版巨人没有攻击 AI，",
                              "给它任何勇士类型都没有意义。")
                    .defineList("blacklist",
                                List.of("minecraft:giant"),
                                () -> "minecraft:zombie",
                                o -> o instanceof String);

        b.pop();

        // ================= championStats =================
        b.comment("勇士基础属性倍率。基准是该生物自身的原版属性，",
                  "所以不同生物成为勇士后的绝对数值不同，但相对强度一致。")
         .push("championStats");

        HEALTH_MULTIPLIER = b.comment("勇士最大生命值倍率。",
                                       "3.5 表示僵尸勇士有 20 × 3.5 = 70 点生命（35 颗心）。",
                                       "倍率基于该生物自身的原版最大生命值，不是固定数值。")
                             .defineInRange("healthMultiplier", 3.5D, 1.0D, 100.0D);

        DAMAGE_MULTIPLIER = b.comment("勇士攻击伤害倍率。",
                                       "1.5 表示勇士的裸伤害是原版的 1.5 倍。",
                                       "注意困难难度本身还会对「打向玩家」的伤害再乘 1.5，",
                                       "两者叠加后，困难难度下勇士伤害 = 原版困难值 × 1.5。",
                                       "只对拥有攻击伤害属性的生物生效（鱼类等被动生物不生效）。")
                             .defineInRange("damageMultiplier", 1.5D, 1.0D, 100.0D);

        b.pop();

        // ================= glow =================
        b.comment("勇士的发光描边。按类型区分颜色：",
                  "屏障 = 黄，过载 = 蓝，势不可挡 = 红。")
         .push("glow");

        GLOW_ENABLED = b.comment("是否让勇士发光（自带透视描边效果）。",
                                 "关闭后勇士与普通生物外观无区别，只能靠行为辨认。")
                        .define("enabled", true);

        GLOW_TEAM = b.comment("是否用计分板队伍给描边上色。",
                              "开启后描边按类型着色，但有两项副作用（原版机制所限，无法回避）：",
                              "1) 同类型的勇士之间不会互相攻击（原版队伍会屏蔽友军索敌）；",
                              "2) 勇士的名牌也会染上对应颜色。",
                              "关闭后描边统一为白色，且无上述副作用。")
                     .define("colorByTeam", true);

        b.pop();

        // ================= dualState =================
        b.comment("双态生物（溺尸 drowned / 猪灵 piglin）的类型决定方式。",
                  "设计上双态是「运行时决定」，一只生物不会同时是两种勇士。")
         .push("dualState");

        DUAL_STATE_MODE = b.comment("RANDOM = 生成时抽签并配发对应武器（推荐）。",
                                    "WEAPON = 按手持武器决定（原版猪灵默认持弩，近战分支极少触发）。")
                           .defineEnum("mode", DualStateMode.RANDOM);

        DUAL_STATE_BARRIER_RATIO = b.comment("RANDOM 模式下判为屏障的比例，其余为势不可挡。",
                                             "仅对双态生物生效。")
                                    .defineInRange("barrierRatio", 0.5D, 0.0D, 1.0D);

        b.pop();

        // ================= barrier =================
        b.comment("屏障勇士：受伤后架盾，盾期间免伤并从盾后回血。",
                  "玩家必须在护盾再生前破除，否则战斗拖长。")
         .push("barrier");

        BARRIER_SHIELD_POINTS = b.comment("护盾可吸收的伤害总量。")
                                 .defineInRange("shieldPoints", 20.0D, 1.0D, 200.0D);

        BARRIER_SHIELD_DURATION = b.comment("护盾最长持续 tick（20 tick = 1 秒）。",
                                            "到期自动解除，防止无限僵持。")
                                   .defineInRange("shieldDurationTicks", 100, 1, 1200);

        BARRIER_REGEN_DELAY = b.comment("护盾被打破后，多少 tick 内不能再生。",
                                        "这是玩家的「破盾窗口」。")
                               .defineInRange("regenDelayTicks", 60, 0, 1200);

        BARRIER_REGEN_PER_SECOND = b.comment("护盾存在期间每秒回复的生命值。",
                                             "设为 0 则纯免伤，不回血。")
                                    .defineInRange("regenPerSecond", 4.0D, 0.0D, 100.0D);

        BARRIER_BREAK_STUN = b.comment("护盾被打破后的虚弱 tick 数（无法行动，可被集火）。")
                              .defineInRange("breakStunTicks", 40, 0, 1200);

        b.pop();

        // ================= overload =================
        b.comment("过载勇士：高速自愈与相位机动，需持续打断才能压制。",
                  "对抗要点不是爆发伤害，而是「不让它恢复」。")
         .push("overload");

        OVERLOAD_REGEN_PER_SECOND = b.comment("每秒自愈量。被反制期间停止。")
                                     .defineInRange("regenPerSecond", 3.0D, 0.0D, 100.0D);

        OVERLOAD_DISRUPTION_DURATION = b.comment("单次反制命中后，压制自愈的持续 tick。",
                                                 "多次命中可刷新，不叠加。")
                                        .defineInRange("disruptionDurationTicks", 60, 1, 1200);

        OVERLOAD_PHASE_ENABLED = b.comment("是否启用相位机动（短距瞬移／闪避）。")
                                  .define("phaseEnabled", true);

        OVERLOAD_PHASE_INTERVAL = b.comment("相位机动的冷却 tick。")
                                   .defineInRange("phaseIntervalTicks", 80, 1, 2400);

        b.pop();

        // ================= unstoppable =================
        b.comment("势不可挡勇士：重装高减伤并向前冲锋。",
                  "玩家必须在冲锋落点前用反制手段造成震慑。")
         .push("unstoppable");

        UNSTOPPABLE_DAMAGE_REDUCTION = b.comment("常驻减伤比例（0.0 ~ 0.95）。",
                                                 "0.5 表示受到的伤害减半。")
                                        .defineInRange("damageReduction", 0.5D, 0.0D, 0.95D);

        UNSTOPPABLE_CHARGE_WINDUP = b.comment("冲锋前的蓄力 tick 数，即玩家的反应窗口。",
                                              "太短会显得无解，太长则没有压力。")
                                     .defineInRange("chargeWindupTicks", 30, 1, 200);

        UNSTOPPABLE_STAGGER_WINDOW = b.comment("蓄力期间可被震慑的窗口 tick 数。",
                                               "只有在此窗口内命中反制附魔才有效。")
                                      .defineInRange("staggerWindowTicks", 20, 1, 200);

        UNSTOPPABLE_STAGGER_DURATION = b.comment("被震慑后失去减伤与冲锋能力的 tick 数。")
                                        .defineInRange("staggerDurationTicks", 60, 1, 1200);

        b.pop();

        // ================= habitat =================
        b.comment("栖息地修饰符。栖息地与家族是两条独立的轴：",
                  "家族回答「它是什么」，栖息地回答「它在哪」，两者互不排斥。")
         .push("habitat");

        HABITAT_NETHER_ENABLED = b.comment("是否让下界生物获得额外强化。")
                                  .define("netherEnabled", true);

        HABITAT_NETHER_CHANCE_MULT = b.comment("下界生物成为勇士的概率倍率。")
                                      .defineInRange("netherChanceMultiplier", 1.5D, 1.0D, 10.0D);

        HABITAT_NETHER_SHIELD_MULT = b.comment("下界勇士的护盾量倍率（仅影响屏障类型）。")
                                      .defineInRange("netherShieldMultiplier", 1.5D, 1.0D, 10.0D);

        b.pop();

        // ================= enchantment =================
        b.comment("三种反制附魔的获取途径。",
                  "三种附魔互斥（共用 exclusive_set/champion 标签），",
                  "但与原版 sharpness / smite 等伤害附魔不互斥。")
         .push("enchantment");

        ENCHANT_TABLE_ENABLED = b.comment("是否可通过附魔台获得。")
                                 .define("enchantTableEnabled", true);

        ENCHANT_LOOT_ENABLED = b.comment("是否可在地牢战利品中出现。")
                                .define("lootEnabled", true);

        ENCHANT_TRADE_ENABLED = b.comment("是否可由村民交易获得。")
                                 .define("tradeEnabled", false);

        b.pop();

        // ================= debug =================
        b.comment("调试选项。正式游玩建议全部关闭。")
         .push("debug");

        DEBUG_LOG_ASSIGNMENTS = b.comment("在日志中打印每次勇士类型分配结果。")
                                 .define("logAssignments", false);

        DEBUG_SHOW_TYPE_ABOVE_HEAD = b.comment("在勇士头顶显示其类型（客户端调试用）。")
                                      .define("showTypeAboveHead", false);

        b.pop();

        SPEC = b.build();
    }

    private ChampionsConfig() {}
}
