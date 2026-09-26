package beiwu.pantheon_champions.item;

import java.util.LinkedHashMap;
import java.util.Map;

import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.item.Item;
import net.neoforged.neoforge.registries.DeferredItem;
import net.neoforged.neoforge.registries.DeferredRegister;

import beiwu.pantheon_champions.PantheonChampions;
import beiwu.pantheon_champions.champion.ChampionType;

/**
 * 本模组的物品注册。
 *
 * <p>目前只有三只勇士刷怪蛋，每种勇士类型一只。</p>
 *
 * <h2>刷怪蛋的「代表生物」怎么选</h2>
 *
 * <p>刷怪蛋必须绑定一个具体的 {@link EntityType}，但「勇士」是一个
 * **运行时状态**而不是一种生物，所以没有完美的代表。
 * 这里选的是各自类型里最有辨识度的经典怪：</p>
 *
 * <ul>
 *   <li>屏障 → 骷髅（远程，需破盾）</li>
 *   <li>过载 → 蜘蛛（近战成群，需压制）</li>
 *   <li>势不可挡 → 僵尸（近战，需打断）</li>
 * </ul>
 *
 * <p>生成出来的生物**必定是指定类型的勇士**，与其他同族生物是否常见无关。
 * 想要别的生物当勇士，可以对它用概率生成，或用命令直接改 NBT。</p>
 *
 * <h2>刷怪蛋染色</h2>
 *
 * <p>两个颜色参数是原版的「底色 / 斑点色」。这里用勇士类型的主题色
 * （黄 / 蓝 / 红）做底色，让三只蛋在物品栏里一眼可辨，
 * 斑点色统一用深灰以免花哨。</p>
 */
public final class ChampionsItems {

    private ChampionsItems() {
    }

    public static final DeferredRegister.Items ITEMS =
            DeferredRegister.createItems(PantheonChampions.MOD_ID);

    /** 斑点色（原版 SpawnEggItem 的第二个颜色参数），统一深灰。 */
    private static final int HIGHLIGHT = 0x2B2B2B;

    /** 注册名 → 刷怪蛋。用 LinkedHashMap 保证创造栏里的顺序稳定可预期。 */
    private static final Map<String, DeferredItem<ChampionSpawnEggItem>> SPAWN_EGGS =
            new LinkedHashMap<>();

    /** 屏障勇士刷怪蛋，代表生物骷髅。底色用屏障黄。 */
    public static final DeferredItem<ChampionSpawnEggItem> BARRIER_SPAWN_EGG =
            registerEgg("barrier_spawn_egg", EntityType.SKELETON, ChampionType.BARRIER);

    /** 过载勇士刷怪蛋，代表生物蜘蛛。底色用过载蓝。 */
    public static final DeferredItem<ChampionSpawnEggItem> OVERLOAD_SPAWN_EGG =
            registerEgg("overload_spawn_egg", EntityType.SPIDER, ChampionType.OVERLOAD);

    /** 势不可挡勇士刷怪蛋，代表生物僵尸。底色用势不可挡红。 */
    public static final DeferredItem<ChampionSpawnEggItem> UNSTOPPABLE_SPAWN_EGG =
            registerEgg("unstoppable_spawn_egg", EntityType.ZOMBIE, ChampionType.UNSTOPPABLE);

    private static DeferredItem<ChampionSpawnEggItem> registerEgg(String name,
                                                                 EntityType<? extends Mob> type,
                                                                 ChampionType championType) {
        DeferredItem<ChampionSpawnEggItem> item = ITEMS.register(name,
                () -> new ChampionSpawnEggItem(
                        type,
                        championType,
                        // 底色用类型的主题色（不透明），与描边颜色保持一致。
                        championType.getArgbColor() & 0xFFFFFF,
                        HIGHLIGHT,
                        new Item.Properties()));
        SPAWN_EGGS.put(name, item);
        return item;
    }

    /** 全部刷怪蛋，供创造标签页遍历。 */
    public static Map<String, DeferredItem<ChampionSpawnEggItem>> spawnEggs() {
        return Map.copyOf(SPAWN_EGGS);
    }

    /** 每种勇士类型对应的刷怪蛋，供命令与测试辅助使用。 */
    public static DeferredItem<ChampionSpawnEggItem> eggFor(ChampionType type) {
        return switch (type) {
            case BARRIER -> BARRIER_SPAWN_EGG;
            case OVERLOAD -> OVERLOAD_SPAWN_EGG;
            case UNSTOPPABLE -> UNSTOPPABLE_SPAWN_EGG;
        };
    }
}
