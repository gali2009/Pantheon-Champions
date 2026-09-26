package beiwu.pantheon_champions;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beiwu.pantheon_champions.config.ChampionsConfig;
import beiwu.pantheon_champions.sound.ChampionsSounds;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.config.ModConfig;

/**
 * Pantheon: Champions —— 把《命运2》的三种勇士搬进 Minecraft。
 *
 * <p>目标版本：Minecraft 1.21.1 / NeoForge 21.1.250。</p>
 *
 * <p>要移植的三个动词：屏障（破 —— 在护盾回满前打破它）、
 * 过载（压 —— 压制它的自愈）、势不可挡（断 —— 在起手窗口内打断冲锋）。</p>
 *
 * <p>设计文档见项目根目录的 {@code DESIGN.md}，族类表、勇士归类表，
 * 以及所有已核实的 API 约束都记录在那里。</p>
 */
@Mod(PantheonChampions.MOD_ID)
public final class PantheonChampions {

    public static final String MOD_ID = "pantheon_champions";

    public static final Logger LOG = LoggerFactory.getLogger("Pantheon: Champions");

    public PantheonChampions(IEventBus modBus, ModContainer container) {
        // ModConfig.Type.COMMON 会写到运行目录下的 config/pantheon_champions-common.toml，
        // 并且在客户端与服务端都会加载。
        container.registerConfig(ModConfig.Type.COMMON, ChampionsConfig.SPEC);

        // 注册表必须在构造器里挂到 mod 事件总线上，且要早于注册事件触发。
        // 声音属于原版内置注册表，所以 DeferredRegister 需要的是 mod 总线，
        // 而不是自定义注册表键。
        ChampionsSounds.SOUND_EVENTS.register(modBus);

        LOG.info("Pantheon: Champions loading");
    }
}
