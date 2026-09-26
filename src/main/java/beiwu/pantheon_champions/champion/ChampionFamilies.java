package beiwu.pantheon_champions.champion;

import net.minecraft.core.registries.Registries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.tags.TagKey;
import net.minecraft.world.entity.EntityType;

import beiwu.pantheon_champions.PantheonChampions;

/**
 * 勇士「家族」标签的 Java 侧句柄。
 *
 * <p>家族回答的是「它是什么」，一只生物只属于一个家族（家族互斥），
 * 因此勇士类型可以唯一确定。栖息地（{@link #NETHER}）是**独立的第二轴**，
 * 回答「它在哪」，与家族不冲突——例如岩浆怪既是史莱姆族又是下界。</p>
 *
 * <p>标签内容在 {@code data/pantheon_champions/tags/entity_type/*.json}。
 * 这里只声明 <b>键</b>，不重复成员列表：成员表是数据，改它不需要重新编译，
 * 其他 mod 也能通过数据包往标签里加东西。</p>
 *
 * <p><b>为什么自建标签而不复用原版 {@code #minecraft:undead}：</b>
 * 原版亡灵标签含 {@code wither}，而凋灵按设计不做勇士；更重要的是，
 * Mojang 更新时往原版标签加怪会**被动改变我们的家族划分**，
 * 可能破坏互斥性。自建标签显式列举成员，
 * 且保留 {@code "replace": false}（默认值）以便他人扩展。</p>
 */
public final class ChampionFamilies {

    /** 亡灵族：僵尸族 + 骷髅族 + 幻翼 + 马。有意排除 {@code wither}。 */
    public static final TagKey<EntityType<?>> UNDEAD = tag("undead");

    /** 僵尸族（亡灵的互斥子族）。 */
    public static final TagKey<EntityType<?>> ZOMBIE = tag("zombie");

    /** 骷髅族（亡灵的互斥子族）。 */
    public static final TagKey<EntityType<?>> SKELETON = tag("skeleton");

    /** 节肢族：蜘蛛、蠹虫、末影螨、蜜蜂。 */
    public static final TagKey<EntityType<?>> ARTHROPOD = tag("arthropod");

    /** 水生族。非敌对的鱼类也在内，但类型分配只对敌对生物生效。 */
    public static final TagKey<EntityType<?>> AQUATIC = tag("aquatic");

    /** 灾厄族：施法 / 远程——唤魔者、幻术师、掠夺者、女巫。 */
    public static final TagKey<EntityType<?>> ILLAGER = tag("illager");

    /** 袭击者族：兽 / 近战——卫道士、劫掠兽、恼鬼。 */
    public static final TagKey<EntityType<?>> RAIDER = tag("raider");

    /** 猪灵族。 */
    public static final TagKey<EntityType<?>> PIGLIN = tag("piglin");

    /** 史莱姆族。 */
    public static final TagKey<EntityType<?>> SLIME = tag("slime");

    /** 末影族（只有末影人）。 */
    public static final TagKey<EntityType<?>> ENDER = tag("ender");

    /** 无族：苦力怕、旋风人、监守者、巨人、恶魂、烈焰人、潜影贝。 */
    public static final TagKey<EntityType<?>> FACTIONLESS = tag("factionless");

    /**
     * 下界栖息地（独立轴，不是家族）。
     *
     * <p>下界生物获得概率与护盾加成，见配置文件的 {@code [habitat]} 段。</p>
     */
    public static final TagKey<EntityType<?>> NETHER = tag("habitat/nether");

    private ChampionFamilies() {
    }

    private static TagKey<EntityType<?>> tag(String path) {
        // 1.21.1 里 ResourceLocation 的构造器是私有的，
        // 必须走 fromNamespaceAndPath —— 用 new ResourceLocation(...) 编译不过。
        return TagKey.create(Registries.ENTITY_TYPE,
                ResourceLocation.fromNamespaceAndPath(PantheonChampions.MOD_ID, path));
    }
}
