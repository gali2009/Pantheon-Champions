package beiwu.pantheon_champions.item;

import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.MobSpawnType;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.SpawnEggItem;
import net.minecraft.world.item.context.UseOnContext;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.gameevent.GameEvent;

import beiwu.pantheon_champions.champion.ChampionAssignment;
import beiwu.pantheon_champions.champion.ChampionType;
import beiwu.pantheon_champions.champion.ChampionTypes;

/**
 * 勇士刷怪蛋：生成一只**必然是该类型**的勇士。
 *
 * <h2>为什么不直接复用原版的生成流程</h2>
 *
 * <p>原版 {@code SpawnEggItem.useOn} 内部调用
 * {@code EntityType.spawn(...)}，而那个重载把新生成的实体**返回**了，
 * 但物品自己并没有保存它，所以我们拿不到刚生成的那一只。
 * 这里覆写 {@code useOn}，改用返回实体的那个重载，就地把它转成勇士。</p>
 *
 * <p>走 {@code EntityType.spawn(level, Consumer, pos, type, ...)} 而不是
 * 先生成再用 UUID 差集去找，是因为差集法在
 * 「旁边本来就站着一只同类生物」时容易误伤，
 * 而直接拿到返回值没有这个歧义。</p>
 *
 * <h2>为什么不用物品的 ENTITY_DATA 组件写 NBT</h2>
 *
 * <p>原版确实支持把 NBT 写进刷怪蛋的 {@code ENTITY_DATA} 组件，
 * 但字节码显示 {@code EntityType.updateCustomEntityTag} 会先检查
 * {@code entity.onlyOpCanSetNbt()} 并要求施加者是 OP——
 * **普通玩家用刷怪蛋时那条 NBT 会被静默丢弃**。
 * 所以类型不能靠物品数据传递，必须在生成后由代码显式写入。</p>
 */
public class ChampionSpawnEggItem extends SpawnEggItem {

    /** 这只刷怪蛋生成哪种勇士。 */
    private final ChampionType championType;

    public ChampionSpawnEggItem(EntityType<? extends Mob> defaultType,
                                ChampionType championType,
                                int backgroundColor,
                                int highlightColor,
                                Properties properties) {
        super(defaultType, backgroundColor, highlightColor, properties);
        this.championType = championType;
    }

    public ChampionType getChampionType() {
        return this.championType;
    }

    /**
     * 在方块上使用：生成一只指定类型的勇士。
     *
     * <p>逻辑与原版 {@code SpawnEggItem.useOn} 保持一致
     * （包括刷怪笼的处理、方块碰撞体积判断、物品消耗与游戏事件），
     * 只在生成成功后多一步「标记为勇士」。</p>
     */
    @Override
    public InteractionResult useOn(UseOnContext context) {
        // 客户端不生成实体，交给原版返回 SUCCESS 即可。
        if (!(context.getLevel() instanceof ServerLevel level)) {
            return super.useOn(context);
        }

        ItemStack stack = context.getItemInHand();
        BlockPos clickedPos = context.getClickedPos();
        Direction clickedFace = context.getClickedFace();
        BlockState clickedState = level.getBlockState(clickedPos);

        // 刷怪笼：原版行为是设置刷怪笼的实体类型，不生成生物。
        // 这里的刷怪蛋类型固定，交给原版处理即可（类型由 getType 决定）。
        if (level.getBlockEntity(clickedPos) instanceof net.minecraft.world.level.Spawner) {
            InteractionResult result = super.useOn(context);
            if (result.consumesAction()) {
                // 刷怪笼里存的是纯实体类型，无法携带勇士 NBT，
                // 所以用刷怪笼生成的生物会走普通的概率分配路径。
                return result;
            }
            return result;
        }

        // 方块有碰撞体积就放在它上方，否则放在方块自身位置（原版逻辑）。
        BlockPos spawnPos = clickedState.getCollisionShape(level, clickedPos).isEmpty()
                ? clickedPos
                : clickedPos.relative(clickedFace);

        // 原版：点击面朝上、或点击位置与生成位置相同时，才对齐到方块中心。
        boolean align = clickedPos.equals(spawnPos) && clickedFace == Direction.UP;

        Mob spawned = spawnChampion(level, stack, spawnPos, align);

        if (spawned == null) {
            return InteractionResult.PASS;
        }

        stack.shrink(1);
        level.gameEvent(context.getPlayer(), GameEvent.ENTITY_PLACE, clickedPos);
        return InteractionResult.CONSUME;
    }

    /**
     * 生成生物并在生成过程中把它标记为勇士。
     *
     * <p>写成泛型方法是为了配合 {@code EntityType.spawn} 的签名：
     * 它要求 {@code Consumer<T>} 与实体类型参数一致，而
     * {@code getType(stack)} 返回的是 {@code EntityType<?>}——
     * 通配符无法直接传给泛型参数（编译器会报「lambda 参数类型不兼容」）。
     * 这里把它收窄到 {@code T extends Mob}，
     * 因为刷怪蛋构造器已经保证绑定的实体类型一定是生物。</p>
     */
    @SuppressWarnings("unchecked")
    private <T extends Mob> Mob spawnChampion(ServerLevel level,
                                              ItemStack stack,
                                              BlockPos spawnPos,
                                              boolean align) {
        EntityType<T> type = (EntityType<T>) this.getType(stack);

        return type.spawn(level,
                mob -> {
                    // 这个 Consumer 在 finalizeSpawn 之后、加入世界之前执行，
                    // 是注入勇士状态的正确时机：此时属性已初始化完毕。
                    if (ChampionTypes.isEligible(mob)) {
                        ChampionAssignment.applyChampion(mob, this.championType);
                    }
                },
                spawnPos,
                MobSpawnType.SPAWN_EGG,
                false,
                align);
    }
}
