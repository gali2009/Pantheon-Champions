package beiwu.pantheon_champions.sound;

import beiwu.pantheon_champions.PantheonChampions;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.neoforged.neoforge.registries.DeferredHolder;
import net.neoforged.neoforge.registries.DeferredRegister;

/**
 * 本模组的声音事件。
 *
 * <p>这里注册的是「声音事件」（SoundEvent），不是音频文件本身。两者的关系是：
 * {@code assets/pantheon_champions/sounds.json} 把事件名映射到磁盘上的 .ogg 文件，
 * 而代码只能引用注册过的 {@link SoundEvent}。少任何一边都不会响——</p>
 *
 * <ul>
 *   <li>只有 .ogg 没有 sounds.json：文件是死数据，游戏不知道它对应哪个事件。</li>
 *   <li>只有 sounds.json 没有注册：代码拿不到 SoundEvent，无从播放。</li>
 * </ul>
 *
 * <p>命名必须与 sounds.json 里的键一致：这里注册的 {@code stun1} 对应
 * {@code assets/pantheon_champions/sounds.json} 中的 {@code "stun1"}，
 * 以及文件 {@code assets/pantheon_champions/sounds/stun1.ogg}。</p>
 */
public final class ChampionsSounds {

    private ChampionsSounds() {
    }

    public static final DeferredRegister<SoundEvent> SOUND_EVENTS =
            DeferredRegister.create(BuiltInRegistries.SOUND_EVENT, PantheonChampions.MOD_ID);

    /**
     * 勇士被击晕时的音效。
     *
     * <p>用可变距离事件（variable range），这样它会随距离衰减，并由声音引擎
     * 按方位定位。音频文件已确认为单声道，这是衰减能生效的前提——立体声文件
     * 不受衰减影响，会永远在玩家所在位置播放。</p>
     */
    public static final DeferredHolder<SoundEvent, SoundEvent> STUN_1 =
            register("stun1");

    /** 第二种击晕音效，与 {@link #STUN_1} 同用途，供随机挑选。 */
    public static final DeferredHolder<SoundEvent, SoundEvent> STUN_2 =
            register("stun2");

    private static DeferredHolder<SoundEvent, SoundEvent> register(String name) {
        return SOUND_EVENTS.register(name,
                () -> SoundEvent.createVariableRangeEvent(
                        ResourceLocation.fromNamespaceAndPath(PantheonChampions.MOD_ID, name)));
    }
}
