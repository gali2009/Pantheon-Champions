package beiwu.pantheon_champions.creativetab;

import beiwu.pantheon_champions.PantheonChampions;
import beiwu.pantheon_champions.item.ChampionsItems;
import net.minecraft.core.Holder;
import net.minecraft.core.registries.Registries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceKey;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.item.CreativeModeTab;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.item.enchantment.Enchantment;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * 本模组的创造模式标签页。
 *
 * <p><b>一个必须先说清的限制</b>：创造标签页只能放<b>物品</b>（{@code ItemLike}），
 * 而附魔不是物品——它是数据包注册表里的一条记录。所以「附魔标签页」没法直接
 * 列出附魔本身，只能列出<b>附了这些附魔的附魔书</b>。这也是原版的做法：
 * 原版创造模式里根本不提供附魔书，附魔要靠铁砧或 {@code /enchant} 获得。</p>
 *
 * <p>因此本标签页当前的内容是：三本附魔书，各附一种勇士附魔。
 * 等以后加了刷怪蛋、材料等物品，再来这里追加。</p>
 *
 * <p>图标暂时用不死图腾（用户指定）。语义上贴合「扛住致命一击」，
 * 等有正式图标资源再换。</p>
 */
public final class ChampionsCreativeTabs {

    private ChampionsCreativeTabs() {
    }

    public static final DeferredRegister<CreativeModeTab> CREATIVE_MODE_TABS =
            DeferredRegister.create(Registries.CREATIVE_MODE_TAB, PantheonChampions.MOD_ID);

    /**
     * 三种勇士附魔的注册名，与
     * {@code data/pantheon_champions/enchantment/} 下的文件名一一对应。
     */
    private static final String[] CHAMPION_ENCHANTMENTS = {
            "anti_barrier",
            "anti_overload",
            "anti_unstoppable"
    };

    public static final DeferredHolder<CreativeModeTab, CreativeModeTab> CHAMPIONS_TAB =
            CREATIVE_MODE_TABS.register("champions", () -> CreativeModeTab.builder()
                    .title(Component.translatable(
                            "itemGroup." + PantheonChampions.MOD_ID + ".champions"))
                    .icon(() -> new ItemStack(Items.TOTEM_OF_UNDYING))
                    .displayItems((params, output) -> {
                        // 刷怪蛋是普通物品，直接按注册顺序放进去即可。
                        // 放在附魔书前面，因为它们更常用。
                        for (var egg : ChampionsItems.spawnEggs().values()) {
                            output.accept(egg.get());
                        }

                        // 附魔属于数据包注册表，必须通过 params.holders() 取，
                        // 不能像物品那样用静态字段直接引用——标签页构建时才拿得到注册表。
                        var enchantments = params.holders().lookupOrThrow(Registries.ENCHANTMENT);

                        for (String name : CHAMPION_ENCHANTMENTS) {
                            ResourceKey<Enchantment> key = ResourceKey.create(
                                    Registries.ENCHANTMENT,
                                    ResourceLocation.fromNamespaceAndPath(
                                            PantheonChampions.MOD_ID, name));

                            // 用 getOrThrow 而不是 get：附魔是本模组自己的数据包文件，
                            // 缺了就是打包错误，应该立刻炸出来，而不是静默少一本书。
                            Holder.Reference<Enchantment> holder = enchantments.getOrThrow(key);

                            ItemStack book = new ItemStack(Items.ENCHANTED_BOOK);
                            book.enchant(holder, 1);
                            output.accept(book);
                        }
                    })
                    .build());
}
