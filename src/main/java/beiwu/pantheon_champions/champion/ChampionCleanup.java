package beiwu.pantheon_champions.champion;

import net.minecraft.world.entity.Mob;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityLeaveLevelEvent;

import beiwu.pantheon_champions.PantheonChampions;
import beiwu.pantheon_champions.config.ChampionsConfig;

/**
 * 清理离开世界的勇士所留下的计分板队伍条目。
 *
 * <h2>为什么需要清理</h2>
 *
 * <p>计分板是**按维度保存进存档**的数据。勇士被移除（死亡、区块卸载、
 * 传送走）时若不把它从队伍里摘掉，{@code PlayerTeam} 的成员列表会
 * **无限增长**：每次刷怪都加一条，读档后还留着一堆指向已不存在实体的 UUID。
 * 长期游玩后这会造成可观的存档膨胀。</p>
 *
 * <p>{@code EntityLeaveLevelEvent} 由 {@code ServerLevel.EntityCallbacks}
 * 触发（字节码已确认），覆盖实体被移除的路径，包含区块卸载。</p>
 *
 * <p><b>注意</b>：区块卸载会让实体离开世界、重新加载时再进入，
 * 所以「离开时清队伍、进入时重新加」是成对发生的，不会导致勇士丢颜色——
 * 重新进入时会走 {@code EntityJoinLevelEvent}，虽然那条路径会因为
 * {@code loadedFromDisk()} 为真而**跳过 NBT 与属性的分配**，
 * 但它仍会调用 {@code ChampionGlow.apply} 把队伍补回去，
 * 因此勇士重新加载后颜色依旧正确。</p>
 */
@EventBusSubscriber(modid = PantheonChampions.MOD_ID)
public final class ChampionCleanup {

    private ChampionCleanup() {
    }

    @SubscribeEvent
    public static void onEntityLeaveLevel(EntityLeaveLevelEvent event) {
        if (event.getLevel().isClientSide()) {
            return;
        }
        // 只有启用队伍着色时才可能加过队伍，否则无事可做。
        if (!ChampionsConfig.GLOW_ENABLED.get() || !ChampionsConfig.GLOW_TEAM.get()) {
            return;
        }
        if (!(event.getEntity() instanceof Mob mob)) {
            return;
        }

        // ⚠️ 这里**不能**用 ChampionAssignment.readType 来判断
        // 「是不是我们的勇士」：readType 走 getPersistentData()，
        // 而该方法会**惰性创建**一个空的 NeoForgeData 标签。
        // 后果是世界里每一个离开视野的实体都会被凭空写入持久化数据，
        // 存档持续膨胀——一个纯粹为了「清理」的处理器反而变成了污染源。
        //
        // 改用队伍成员关系判断：只有我们加过队伍的实体才可能命中，
        // 而查队伍不碰 NBT（getScoreboardName 只读缓存的 stringUUID 字段，
        // 字节码确认它直接返回 getfield，没有副作用）。
        ChampionGlow.remove(mob);
    }
}
