package beiwu.pantheon_champions.champion;

import org.jetbrains.annotations.Nullable;

import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.util.RandomSource;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.attributes.AttributeInstance;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.monster.Enemy;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.fml.common.EventBusSubscriber;
import net.neoforged.neoforge.event.entity.EntityJoinLevelEvent;

import beiwu.pantheon_champions.PantheonChampions;
import beiwu.pantheon_champions.config.ChampionsConfig;

/**
 * 在生物生成时决定它是不是勇士，并写入 {@code ChampionType} NBT。
 *
 * <p><b>这是整个系统的枢纽</b>：三种反制附魔的 JSON 谓词写的是
 * {@code {NeoForgeData:{ChampionType:N}}}，在本类出现之前，
 * 没有任何代码写入这个 NBT，所以附魔对普通怪物完全不生效。
 * 本类落地后附魔才真正连通。</p>
 *
 * <h2>为什么用 {@link EntityJoinLevelEvent} 而不是 FinalizeSpawnEvent</h2>
 *
 * <p>最初打算用 {@code FinalizeSpawnEvent}，但字节码分析推翻了它：
 * 该事件只由 {@code EventHooks.finalizeMobSpawn} 与
 * {@code finalizeMobSpawnSpawner} 触发，而这两个方法**只被
 * {@code BaseSpawner} 和 {@code TrialSpawner} 引用**——
 * 也就是说它**只覆盖刷怪笼**。</p>
 *
 * <p>实测确认 {@code Mob.finalizeSpawn} 内部对 {@code EventHooks} 的调用次数为
 * <b>0</b>，所以自然生成、刷怪蛋、命令召唤、结构生成全都抓不到。</p>
 *
 * <p>{@code EntityJoinLevelEvent} 由 {@code ServerLevel} 与
 * {@code PersistentEntitySectionManager} 触发，覆盖**全部**进入世界的路径，
 * 包括读档。因此必须用 {@link EntityJoinLevelEvent#loadedFromDisk()} 把
 * 「从存档里读出来的实体」区分开：它们**跳过 NBT 与属性分配**
 * （否则每次读档都会重新抽签改类型），但仍需要补回发光描边队伍。</p>
 */
// 不写 bus = ... ：该参数在 NeoForge 21.1 已标记为待删除（编译会告警），
// 且其默认值本来就是 GAME——而 EntityJoinLevelEvent 正是 GAME 总线事件，
// 所以按默认值订阅即可，语义不变。
@EventBusSubscriber(modid = PantheonChampions.MOD_ID)
public final class ChampionAssignment {

    /**
     * 存放勇士类型的 NBT 键名，位于 NeoForge 的持久化数据子标签下。
     *
     * <p>完整路径是 {@code NeoForgeData.ChampionType}。附魔谓词里必须写成
     * {@code {NeoForgeData:{ChampionType:N}}}，前缀不能省——
     * {@code getPersistentData()} 的内容并非平铺在实体根标签上。</p>
     */
    public static final String NBT_KEY = "ChampionType";

    /**
     * 血量修正的 ID。用固定的 {@link ResourceLocation} 是为了让
     * {@code addOrReplacePermanentModifier} 幂等——它会先按 ID 移除旧的再添加，
     * 所以同一只生物被重复处理也不会叠加成 2 倍、3 倍。
     */
    private static final ResourceLocation HEALTH_MODIFIER_ID =
            ResourceLocation.fromNamespaceAndPath(PantheonChampions.MOD_ID, "champion_health");

    /** 攻击伤害修正的 ID，理由同上。 */
    private static final ResourceLocation DAMAGE_MODIFIER_ID =
            ResourceLocation.fromNamespaceAndPath(PantheonChampions.MOD_ID, "champion_damage");

    private ChampionAssignment() {
    }

    /**
     * 实体进入世界时调用。
     *
     * <p>流程：总开关 → 跳过读档实体 → 概率抽签 → 类型解析 → 写 NBT →
     * 改属性 → 加发光描边。</p>
     */
    @SubscribeEvent
    public static void onEntityJoinLevel(EntityJoinLevelEvent event) {
        if (!ChampionsConfig.ENABLED.get()) {
            return;
        }

        // 只处理服务端的生物。客户端那一侧只是渲染影子，不该做逻辑判定，
        // 否则两边状态会不一致。
        if (event.getLevel().isClientSide()) {
            return;
        }

        // 从存档读出来的实体已经有类型了，绝不能重新抽签——
        // 否则玩家每次读档，同一只勇士都会换类型甚至变回普通怪。
        //
        // 但**描边必须补回**：生物离开世界时（含区块卸载）我们会把它从
        // 计分板队伍里摘掉以防存档膨胀，而队伍不会随实体一起存盘。
        // 所以这里只补渲染状态，绝不碰 NBT 与属性。
        if (event.loadedFromDisk()) {
            // 只有「按队伍着色」开着时才需要补描边队伍——
            // 若没启用队伍，离开世界时也没摘过队伍，无事可做。
            if (!ChampionsConfig.GLOW_ENABLED.get() || !ChampionsConfig.GLOW_TEAM.get()) {
                return;
            }
            // ⚠️ 这里的 Enemy 闸门不是多余的：readType 内部会调用
            // getPersistentData()，而它是**惰性创建**的——实体原本没有
            // 持久化数据时，该调用会凭空塞一个空的 NeoForgeData 标签，
            // 并在下次存档时写进 NBT。先过闸门能把这种「空标签污染」
            // 限制在敌对生物范围内，而不是世界里每一个实体。
            // （`nbt={NeoForgeData:{}}` 会因此误匹配，我自己测试时踩过。）
            if (event.getEntity() instanceof Mob loadedMob
                    && loadedMob instanceof Enemy) {
                ChampionType existing = readType(loadedMob);
                if (existing != null) {
                    ChampionGlow.apply(loadedMob, existing);
                }
            }
            return;
        }

        if (!(event.getEntity() instanceof Mob mob)) {
            return;
        }

        // ---- 以下三步的顺序**刻意**如此，每一步都不碰 NBT ----

        // 1) 被动生物在这里被挡住：家族标签里有意含被动成员
        //    （鱼类、海龟、马、蜜蜂都在标签里），但勇士只能给敌对生物。
        if (!ChampionTypes.isEligible(mob)) {
            return;
        }

        // 2) 先抽签。**必须在读 NBT 之前**：readType 会惰性创建
        //    NeoForgeData（见上文），若先读，那么每一只没被抽中的普通怪
        //    也会被塞上一个空标签。放在抽签之后，只有真正成为勇士的
        //    生物才会产生 NBT。
        if (!rollChampion(mob)) {
            return;
        }

        // 3) 最后才查「是不是已经有类型了」。
        //    刷怪蛋的路径是：先在 Consumer 里写好类型，实体**随后**才进入
        //    世界——所以这里会看到非空类型并跳过，从而保住刷怪蛋指定的
        //    类型不被概率抽签覆盖。跨维度重入场的实体同理。
        //    注意这个检查放在抽签之后**依然安全**：抽中与否都不会改写
        //    已有的类型，因为两条分支都直接 return。
        if (readType(mob) != null) {
            return;
        }

        ChampionType type = ChampionTypes.resolve(mob,
                mob.getRandom(),
                ChampionsConfig.DUAL_STATE_BARRIER_RATIO.get());
        if (type == null) {
            // 归类表里没有这只生物（史莱姆族暂缓、幻术师暂缓、巨人排除）。
            return;
        }

        applyChampion(mob, type);
    }

    /**
     * 概率抽签：这只生物是否成为勇士。
     *
     * <p>基础概率来自配置，再乘以下界栖息地倍率。
     * 倍率可以超过 1，所以最后用 {@code Math.min(1.0, ...)} 收口，
     * 否则概率会大于 100%（虽然后果只是必然成为勇士）。</p>
     */
    private static boolean rollChampion(Mob mob) {
        double chance = ChampionsConfig.CHAMPION_CHANCE.get();

        if (ChampionsConfig.HABITAT_NETHER_ENABLED.get()
                && mob.getType().is(ChampionFamilies.NETHER)) {
            chance *= ChampionsConfig.HABITAT_NETHER_CHANCE_MULT.get();
        }

        chance = Math.min(1.0D, chance);

        // 用生物自身的随机源，保证同一次生成在重放时结果可复现（种子一致时）。
        RandomSource random = mob.getRandom();
        return random.nextDouble() < chance;
    }

    /**
     * 把一只生物正式转成勇士。
     *
     * <p>{@code public} 是给刷怪蛋与命令复用，保证所有入口走同一套逻辑。</p>
     */
    public static void applyChampion(Mob mob, ChampionType type) {
        writeType(mob, type);
        applyStatModifiers(mob);
        ChampionGlow.apply(mob, type);

        if (ChampionsConfig.DEBUG_LOG_ASSIGNMENTS.get()) {
            PantheonChampions.LOG.info("勇士分配: {} -> {} ({} 点生命)",
                    mob.getType().toShortString(),
                    type.getKey(),
                    String.format("%.1f", mob.getMaxHealth()));
        }
    }

    /**
     * 写入勇士类型 NBT。
     *
     * <p>用 {@code getPersistentData()} 而不是 DataAttachment：
     * 前者的路径稳定为 {@code NeoForgeData.ChampionType}，
     * 而 DataAttachment 会序列化到 {@code neoforge:attachments} 下，
     * 附魔谓词要跟着改，路径更绕。</p>
     */
    private static void writeType(Mob mob, ChampionType type) {
        CompoundTag data = mob.getPersistentData();
        data.putInt(NBT_KEY, type.getId());
    }

    /**
     * 读取勇士类型。
     *
     * @return 该生物是勇士时返回其类型，否则返回 {@code null}
     */
    @Nullable
    public static ChampionType readType(Mob mob) {
        CompoundTag data = mob.getPersistentData();
        // 用 contains 判断而不是「读不到就返回 0」——
        // 因为 0 是合法的屏障 ID，与「没有这个键」必须区分开。
        if (!data.contains(NBT_KEY)) {
            return null;
        }
        return ChampionType.byId(data.getInt(NBT_KEY));
    }

    /**
     * 施加血量与伤害倍率。
     *
     * <p>两个属性都用 {@code ADD_MULTIPLIED_BASE}：这个运算的含义是
     * 「在基础值上追加 base × amount」，效果等价于把数值放大到
     * {@code base × (1 + amount)}。我们要的正是「原版值 × 倍率」，
     * 所以传入的 amount 是 {@code 倍率 - 1}。</p>
     *
     * <p><b>为什么用修正器而不是 {@code setBaseValue}</b>：
     * 直接改基础值会覆盖其他 mod 的属性调整，且「生物原本多少血」这个
     * 信息会永久丢失；修正器是可叠加、可移除的，与其他 mod 兼容。</p>
     *
     * <p><b>为什么必须用 permanent 而不是 transient 修正器</b>：
     * 字节码显示 {@code AttributeInstance.save()} **只保存
     * {@code permanentModifiers} 这一个 Map**，瞬态修正器不写进 NBT。
     * 用瞬态的话，勇士在区块卸载 → 重新加载后会**丢掉全部倍率**，
     * 血量从 70 点掉回 20 点——而且这个 bug 在「生成后立刻查看」时
     * 完全看不出来，只有走远再回来才暴露。</p>
     *
     * <p>{@code addOrReplacePermanentModifier} 内部是「先按 ID 移除、再添加」，
     * 所以重复调用是幂等的，不会叠加出 2 倍、3 倍。</p>
     */
    private static void applyStatModifiers(Mob mob) {
        double healthMultiplier = ChampionsConfig.HEALTH_MULTIPLIER.get();
        // 先把最大生命值抬上去，再把当前血量补满——
        // 否则新生成的低血量生物会带着「满血但只值一点」的状态出现。
        AttributeInstance health = mob.getAttribute(Attributes.MAX_HEALTH);
        if (health != null) {
            health.addOrReplacePermanentModifier(new AttributeModifier(
                    HEALTH_MODIFIER_ID,
                    healthMultiplier - 1.0D,
                    AttributeModifier.Operation.ADD_MULTIPLIED_BASE));
            mob.setHealth(mob.getMaxHealth());
        }

        double damageMultiplier = ChampionsConfig.DAMAGE_MULTIPLIER.get();
        AttributeInstance damage = mob.getAttribute(Attributes.ATTACK_DAMAGE);
        // 不是所有生物都有攻击伤害属性（例如被动生物、部分特殊怪），
        // 所以这里必须判空，不能假设存在。
        if (damage != null) {
            damage.addOrReplacePermanentModifier(new AttributeModifier(
                    DAMAGE_MODIFIER_ID,
                    damageMultiplier - 1.0D,
                    AttributeModifier.Operation.ADD_MULTIPLIED_BASE));
        }
    }
}
