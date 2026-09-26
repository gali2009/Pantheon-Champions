package beiwu.pantheon_champions.champion;

import java.util.Map;
import java.util.Set;

import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.monster.Enemy;

/**
 * 「这只生物该是哪种勇士」的唯一权威判定。
 *
 * <p>本表是 {@code DESIGN.md} 第 5 节《勇士归类表（定稿）》的**逐行编码**。
 * 之所以写成"按实体逐个列举"而不是"先查家族再套规则"，
 * 是因为归类表本身就是**逐实体**的——同一家族内存在例外：</p>
 *
 * <ul>
 *   <li>{@code wither_skeleton} 属骷髅族，却是**势不可挡**而非屏障（决策 13）</li>
 *   <li>{@code witch} 属灾厄族，却是**过载**而非屏障（决策 12）</li>
 * </ul>
 *
 * <p>若改写成家族规则，这两个例外会变成散落的 {@code if}，反而更难与文档对齐；
 * 显式表可以逐行比对，{@code Tools\verify-champion-types.ps1} 就是这么做的。</p>
 *
 * <p><b>为什么用 {@link EntityType} 做键而不是实体类</b>：
 * 原版有多个实体共用一个类的情况（例如 {@code Zombie} 类被 {@code zombie}、
 * {@code husk}、{@code drowned} 分别注册），按类做键会混淆；
 * 而 {@code EntityType} 就是注册表里那个唯一 ID，与归类表的 MCID 列一一对应。</p>
 */
public final class ChampionTypes {

    /**
     * 单态生物 → 类型。
     *
     * <p>不含双态生物（见 {@link #DUAL_STATE}），也不含被暂缓 / 排除的生物
     * （见 {@link #DEFERRED}、{@link #EXCLUDED}）。</p>
     */
    private static final Map<EntityType<?>, ChampionType> SINGLE_STATE = Map.ofEntries(
            // ---- 骷髅族：屏障（远程·弓）----
            Map.entry(EntityType.SKELETON, ChampionType.BARRIER),
            Map.entry(EntityType.STRAY, ChampionType.BARRIER),
            Map.entry(EntityType.BOGGED, ChampionType.BARRIER),

            // ---- 僵尸族：势不可挡（近战）----
            Map.entry(EntityType.ZOMBIE, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.HUSK, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.ZOMBIE_VILLAGER, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.ZOGLIN, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.ZOMBIFIED_PIGLIN, ChampionType.UNSTOPPABLE),

            // ---- 亡灵·直属 ----
            // 幻翼是俯冲攻击，归过载
            Map.entry(EntityType.PHANTOM, ChampionType.OVERLOAD),
            // 决策 13：凋灵骷髅虽在骷髅族，但按近战+凋零效果归势不可挡
            Map.entry(EntityType.WITHER_SKELETON, ChampionType.UNSTOPPABLE),

            // ---- 节肢：过载（近战·成群）----
            Map.entry(EntityType.SPIDER, ChampionType.OVERLOAD),
            Map.entry(EntityType.CAVE_SPIDER, ChampionType.OVERLOAD),
            Map.entry(EntityType.SILVERFISH, ChampionType.OVERLOAD),
            Map.entry(EntityType.ENDERMITE, ChampionType.OVERLOAD),

            // ---- 水生：屏障（远程·激光）----
            // 注意只有这两种是敌对的，鱼类/海龟等被动生物被 Enemy 闸门挡在外面
            Map.entry(EntityType.GUARDIAN, ChampionType.BARRIER),
            Map.entry(EntityType.ELDER_GUARDIAN, ChampionType.BARRIER),

            // ---- 灾厄：施法 / 远程 ----
            Map.entry(EntityType.PILLAGER, ChampionType.BARRIER),
            Map.entry(EntityType.EVOKER, ChampionType.BARRIER),
            // 决策 12：女巫是投药水的支援型，归过载
            Map.entry(EntityType.WITCH, ChampionType.OVERLOAD),

            // ---- 袭击者：兽 / 近战 → 势不可挡 ----
            Map.entry(EntityType.VINDICATOR, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.RAVAGER, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.VEX, ChampionType.UNSTOPPABLE),

            // ---- 猪灵（单态部分）----
            Map.entry(EntityType.PIGLIN_BRUTE, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.HOGLIN, ChampionType.UNSTOPPABLE),

            // ---- 末影：过载（近战·瞬移）----
            Map.entry(EntityType.ENDERMAN, ChampionType.OVERLOAD),

            // ---- 无族 ----
            Map.entry(EntityType.CREEPER, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.WARDEN, ChampionType.UNSTOPPABLE),
            Map.entry(EntityType.GHAST, ChampionType.BARRIER),
            Map.entry(EntityType.BLAZE, ChampionType.BARRIER),
            Map.entry(EntityType.BREEZE, ChampionType.BARRIER),
            Map.entry(EntityType.SHULKER, ChampionType.BARRIER)
    );

    /**
     * 双态生物：生成时抽签决定是屏障还是势不可挡
     * （决策 8 / 第 6 节）。它们是**唯一**可能有两种类型的生物。
     */
    private static final Set<EntityType<?>> DUAL_STATE = Set.of(
            EntityType.DROWNED,
            EntityType.PIGLIN
    );

    /**
     * 暂缓：设计上已归类，但暂不实现。
     *
     * <ul>
     *   <li>{@code illusioner}——原版世界里根本不会自然生成，
     *       实装无从验证（决策 14）</li>
     *   <li>{@code slime} / {@code magma_cube}——史莱姆族的机制要改，
     *       用户明确要求稍后再写</li>
     * </ul>
     */
    private static final Set<EntityType<?>> DEFERRED = Set.of(
            EntityType.ILLUSIONER,
            EntityType.SLIME,
            EntityType.MAGMA_CUBE
    );

    /**
     * 排除：永远不给勇士类型。
     *
     * <p>{@code giant} 没有任何攻击 AI，给了也没意义（决策 14）。
     * 凋灵 {@code wither} 同理，且它是 Boss 而非普通怪。</p>
     */
    private static final Set<EntityType<?>> EXCLUDED = Set.of(
            EntityType.GIANT,
            EntityType.WITHER
    );

    private ChampionTypes() {
    }

    /**
     * 判断这只生物能不能成为勇士。
     *
     * <p><b>三道闸门</b>，缺一不可：</p>
     *
     * <ol>
     *   <li>必须是 {@link Mob}——只有生物能持有属性与 AI</li>
     *   <li>必须实现 {@link Enemy}——<b>这条挡住全部被动生物</b>。
     *       家族标签里有意包含被动成员（对齐原版 {@code #aquatic} 的语义，
     *       且亡灵族含骷髅马），若按标签直接分配，
     *       鱼、海龟、蝾螈、马、蜜蜂都会变成勇士</li>
     *   <li>不能在 {@link #DEFERRED} 或 {@link #EXCLUDED} 名单里</li>
     * </ol>
     *
     * @param mob 待判定的生物
     * @return 可以成为勇士则返回 {@code true}
     */
    public static boolean isEligible(Mob mob) {
        if (!(mob instanceof Enemy)) {
            return false;
        }
        EntityType<?> type = mob.getType();
        return !DEFERRED.contains(type) && !EXCLUDED.contains(type);
    }

    /**
     * 按归类表解析勇士类型。
     *
     * <p>双态生物在此处**抽签**：以 {@code barrierRatio} 的概率得到屏障，
     * 否则势不可挡（决策：RANDOM 模式）。抽签在生成时只做一次，
     * 结果写入 NBT，之后不再变化——所以一只怪不会中途换类型。</p>
     *
     * @param mob           待判定的生物
     * @param random        随机源
     * @param barrierRatio  双态生物判为屏障的概率，取值 0~1
     * @return 解析出的类型；该生物不该是勇士时返回 {@code null}
     */
    public static ChampionType resolve(Mob mob, RandomSource random, double barrierRatio) {
        if (!isEligible(mob)) {
            return null;
        }
        EntityType<?> type = mob.getType();

        if (DUAL_STATE.contains(type)) {
            return random.nextDouble() < barrierRatio
                    ? ChampionType.BARRIER
                    : ChampionType.UNSTOPPABLE;
        }
        return SINGLE_STATE.get(type);
    }

    /**
     * 该生物是否为双态。
     *
     * <p>用于「按类型配发对应武器」——见第 6.2 节的实现警示：
     * 不能读它手上拿什么，要先定类型再发武器。</p>
     */
    public static boolean isDualState(EntityType<?> type) {
        return DUAL_STATE.contains(type);
    }

    /**
     * 归类表里**当前实装**的单态生物数量，供校验脚本比对（应为 31）。
     *
     * <p>与 DESIGN.md 第 5 节的「单态生物 33」相差 2，差的就是
     * {@code slime} 与 {@code magma_cube}——文档定稿时它们归过载，
     * 但用户后来要求史莱姆族的机制另行设计，故暂缓。
     * 这是**有意偏离文档**，不是漏写。</p>
     */
    public static int singleStateCount() {
        return SINGLE_STATE.size();
    }

    /** 双态生物数量（应为 2）。 */
    public static int dualStateCount() {
        return DUAL_STATE.size();
    }
}
