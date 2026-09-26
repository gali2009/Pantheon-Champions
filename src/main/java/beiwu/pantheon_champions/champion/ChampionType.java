package beiwu.pantheon_champions.champion;

import net.minecraft.ChatFormatting;
import net.minecraft.network.chat.Component;
import net.minecraft.util.FastColor;

/**
 * 三种勇士类型。
 *
 * <p>数值与《命运2》的对应关系：</p>
 *
 * <table border="1">
 *   <caption>类型对照</caption>
 *   <tr><th>类型</th><th>ID</th><th>描边色</th><th>反制附魔</th></tr>
 *   <tr><td>屏障</td><td>0</td><td>黄</td><td>反屏障</td></tr>
 *   <tr><td>过载</td><td>1</td><td>蓝</td><td>反过载</td></tr>
 *   <tr><td>势不可挡</td><td>2</td><td>红</td><td>反势不可挡</td></tr>
 * </table>
 *
 * <p><b>ID 数值是有意固定的</b>：它直接写进实体 NBT
 * （{@code {NeoForgeData:{ChampionType:N}}}），而三种附魔的 JSON 里
 * 把这个数字写死在谓词中。因此 <b>ID 一旦发布就不能改</b>——
 * 改了会让存档里已有的勇士变成另一种类型，也会让附魔静默失效。</p>
 *
 * <p><b>为什么颜色用 {@link ChatFormatting} 而不是 RGB</b>：
 * 描边颜色只能通过计分板队伍设置（见 {@code ChampionGlow}），
 * 而 {@code PlayerTeam.setColor} 只接受原版的 16 种颜色枚举。
 * 用户要的"黄/蓝/红"正好都有对应项，所以不需要自定义色值。</p>
 */
public enum ChampionType {

    /** 屏障：周期性回血，需要「反屏障」附魔破盾。描边黄。 */
    BARRIER(0, "barrier", ChatFormatting.YELLOW),

    /** 过载：持续自愈与相位，需要「反过载」附魔压制。描边蓝。 */
    OVERLOAD(1, "overload", ChatFormatting.BLUE),

    /** 势不可挡：减伤 + 冲锋，需要「反势不可挡」附魔打断。描边红。 */
    UNSTOPPABLE(2, "unstoppable", ChatFormatting.RED);

    /** 写入 NBT 的数值，同时也是附魔谓词里匹配的数值。 */
    private final int id;

    /** 配置与命令用的稳定标识符。 */
    private final String key;

    /** 描边与名牌的颜色。 */
    private final ChatFormatting color;

    ChampionType(int id, String key, ChatFormatting color) {
        this.id = id;
        this.key = key;
        this.color = color;
    }

    public int getId() {
        return this.id;
    }

    public String getKey() {
        return this.key;
    }

    public ChatFormatting getColor() {
        return this.color;
    }

    /**
     * 描边用的 ARGB 颜色值。
     *
     * <p>{@code LevelRenderer} 在渲染发光描边时会调用 {@code Entity.getTeamColor()}，
     * 拿到一个 ARGB 整数后拆成红绿蓝三通道。队伍颜色走的就是这条路径。
     * {@code ChatFormatting.getColor()} 返回的是 RGB（无 alpha），
     * 所以要补上不透明的 alpha 通道。</p>
     *
     * @return 不透明的 ARGB 颜色
     */
    public int getArgbColor() {
        Integer rgb = this.color.getColor();
        // getColor() 对非颜色格式（BOLD 之类）返回 null。我们只用颜色项，
        // 但万一将来有人改错了枚举值，退回白色比抛 NPE 更安全。
        return rgb == null ? 0xFFFFFFFF : FastColor.ARGB32.opaque(rgb);
    }

    /**
     * 按 NBT 数值反查类型。
     *
     * @param id 实体 NBT 里存的数值
     * @return 对应类型；数值不合法时返回 {@code null}
     */
    public static ChampionType byId(int id) {
        for (ChampionType type : values()) {
            if (type.id == id) {
                return type;
            }
        }
        return null;
    }

    /** 翻译键，用于名牌与调试输出。 */
    public String getTranslationKey() {
        return "champion.pantheon_champions." + this.key;
    }

    /** 显示名（如「屏障勇士」）。 */
    public Component getDisplayName() {
        return Component.translatable(this.getTranslationKey());
    }
}
