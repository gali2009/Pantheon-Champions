package beiwu.pantheon_champions.champion;

import net.minecraft.world.entity.Mob;
import net.minecraft.world.scores.PlayerTeam;
import net.minecraft.world.scores.Scoreboard;

import beiwu.pantheon_champions.PantheonChampions;
import beiwu.pantheon_champions.config.ChampionsConfig;

/**
 * 勇士的发光描边，按类型着色。
 *
 * <h2>为什么必须绕道计分板队伍</h2>
 *
 * <p>发光本身很简单：{@code Entity.setGlowingTag(true)} 即可。
 * 但**颜色不受我们控制**——字节码显示 {@code LevelRenderer} 渲染描边时，
 * 颜色来自 {@code Entity.getTeamColor()}（第 1106 行附近），而该方法的实现是：</p>
 *
 * <pre>
 * PlayerTeam team = getTeam();
 * return team != null &amp;&amp; team.getColor() != null ? team.getColor() : 0xFFFFFF;
 * </pre>
 *
 * <p>也就是说：<b>没有队伍就是白色</b>，有队伍就用队伍颜色。
 * 我扫遍了 NeoForge 的全部客户端渲染事件类，**没有任何**
 * overview / glow / outline 相关的事件可以介入这个颜色，
 * 所以想区分黄 / 蓝 / 红，唯一不改原版代码的办法就是给每个类型建一个队伍。</p>
 *
 * <h2>已核实的副作用（无法回避）</h2>
 *
 * <ol>
 *   <li><b>同类型勇士之间不会互相攻击。</b>
 *       {@code TargetingConditions} 在筛选目标时会调用 {@code isAlliedTo}，
 *       而 {@code Entity.isAlliedTo} 直接查队伍。对「勇士是精英变体」的定位
 *       来说这反而合理，但它确实是原版行为改变，所以做成可关的配置项。</li>
 *   <li><b>名牌会被染色。</b> 同样是 {@code getTeamColor()} 的连带效果。</li>
 * </ol>
 *
 * <p>关闭 {@code glow.colorByTeam} 后描边统一为白色，上述副作用一并消失。</p>
 */
public final class ChampionGlow {

    /**
     * 队伍名前缀。
     *
     * <p>刻意用不可能与玩家自建队伍重名的形式：{@code panch_}
     * 既短又能一眼看出是本模组加的。若用「屏障」这类可读名字，
     * 玩家在计分板里建同名队伍就会与本模组互相干扰。</p>
     */
    private static final String TEAM_PREFIX = "panch_";

    private ChampionGlow() {
    }

    /**
     * 给勇士加上发光描边。
     *
     * @param mob  勇士
     * @param type 勇士类型，决定描边颜色
     */
    public static void apply(Mob mob, ChampionType type) {
        if (!ChampionsConfig.GLOW_ENABLED.get()) {
            return;
        }

        mob.setGlowingTag(true);

        if (ChampionsConfig.GLOW_TEAM.get()) {
            assignTeam(mob, type);
        }
    }

    /**
     * 把勇士放进对应类型的队伍，从而给描边上色。
     *
     * <p>队伍是**懒创建**的：只有在真的出现该类型勇士时才建，
     * 避免玩家一进世界就凭空多出三个空队伍。</p>
     */
    private static void assignTeam(Mob mob, ChampionType type) {
        Scoreboard scoreboard = mob.level().getScoreboard();
        String teamName = TEAM_PREFIX + type.getKey();

        PlayerTeam team = scoreboard.getPlayerTeam(teamName);
        if (team == null) {
            team = scoreboard.addPlayerTeam(teamName);
            team.setColor(type.getColor());
            // 允许友军伤害，尽量把「同队不互攻」的影响限制在索敌环节；
            // 但注意索敌用的 isAlliedTo 不看这个开关，所以副作用仍在。
            team.setAllowFriendlyFire(true);
        }

        scoreboard.addPlayerToTeam(mob.getScoreboardName(), team);
    }

    /**
     * 从队伍中移除（生物离开世界时清理）。
     *
     * <p>计分板是按维度共享的存档数据，不清理的话队伍成员列表会无限增长，
     * 读档后还会留下大量指向已不存在实体的条目。</p>
     */
    public static void remove(Mob mob) {
        Scoreboard scoreboard = mob.level().getScoreboard();
        String name = mob.getScoreboardName();
        PlayerTeam team = scoreboard.getPlayersTeam(name);
        if (team != null && team.getName().startsWith(TEAM_PREFIX)) {
            scoreboard.removePlayerFromTeam(name, team);
        }
    }

    /** 队伍名，供调试与校验使用。 */
    public static String teamNameFor(ChampionType type) {
        return TEAM_PREFIX + type.getKey();
    }

    /** 模组初始化时的日志用标识。 */
    static String describe() {
        return PantheonChampions.MOD_ID + " 描边队伍前缀: " + TEAM_PREFIX;
    }
}
