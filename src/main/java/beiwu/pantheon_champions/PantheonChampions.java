package beiwu.pantheon_champions;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beiwu.pantheon_champions.config.ChampionsConfig;
import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.config.ModConfig;

/**
 * Pantheon: Champions — ports Destiny 2's three Champion types into Minecraft.
 *
 * <p>Target: Minecraft 1.21.1, NeoForge 21.1.250.</p>
 *
 * <p>The three verbs being ported: Barrier (破 — break the shield before it
 * regenerates), Overload (压 — suppress its self-healing), Unstoppable
 * (断 — interrupt the charge in its wind-up window).</p>
 *
 * <p>Design notes live in {@code DESIGN.md} at the project root; the family and
 * champion-type tables, plus every verified API constraint, are recorded there.</p>
 */
@Mod(PantheonChampions.MOD_ID)
public final class PantheonChampions {

    public static final String MOD_ID = "pantheon_champions";

    public static final Logger LOG = LoggerFactory.getLogger("Pantheon: Champions");

    public PantheonChampions(IEventBus modBus, ModContainer container) {
        // ModConfig.Type.COMMON writes to config/pantheon_champions-common.toml
        // in the run directory, and is loaded on both sides.
        container.registerConfig(ModConfig.Type.COMMON, ChampionsConfig.SPEC);

        LOG.info("Pantheon: Champions loading");
    }
}
