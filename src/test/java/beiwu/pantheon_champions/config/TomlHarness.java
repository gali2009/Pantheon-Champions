package beiwu.pantheon_champions.config;

import java.nio.file.Files;
import java.nio.file.Path;

import com.electronwill.nightconfig.core.CommentedConfig;
import com.electronwill.nightconfig.core.io.WritingMode;
import com.electronwill.nightconfig.toml.TomlFormat;

import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * Runs the real ModConfigSpec through NightConfig's TOML writer, then re-parses
 * the result to prove the file is valid and round-trips against the spec.
 *
 * <p>Note: ConfigParser.parse(String) takes TOML CONTENT, not a path. Passing a
 * path makes the parser treat "C:\..." as a config and fail on the drive colon.</p>
 */
public final class TomlHarness {

    public static void main(String[] args) throws Exception {
        Path out = Path.of(args.length > 0 ? args[0] : "champions-common.toml");
        Files.deleteIfExists(out);

        ModConfigSpec spec = ChampionsConfig.SPEC;

        CommentedConfig cfg = CommentedConfig.inMemory();
        int corrections = spec.correct(cfg, (a, p, i, c) -> {});
        TomlFormat.instance().createWriter().write(cfg, out, WritingMode.REPLACE);

        String text = Files.readString(out);

        System.out.println("corrections on empty config : " + corrections);
        System.out.println("bytes written               : " + Files.size(out));

        CommentedConfig reparsed = TomlFormat.instance().createParser().parse(text);
        System.out.println("re-parsed successfully      : yes");
        System.out.println("isCorrect(reparsed)         : " + spec.isCorrect(reparsed));
        System.out.println("comment lines               : " + text.lines().filter(l -> l.trim().startsWith("#")).count());
        System.out.println("sections                    : " + text.lines().filter(l -> l.trim().matches("^\\[[a-zA-Z]+]$")).count());
        System.out.println("keys                        : " + text.lines().filter(l -> l.trim().matches("^[a-zA-Z]+\\s*=.*")).count());
        System.out.println("contains stray html tag     : " + text.contains("<b>"));

        // spot-check a few values survived the round trip
        System.out.println("reparsed championChance     : " + reparsed.get("general.championChance"));
        System.out.println("reparsed mode               : " + reparsed.get("dualState.mode"));
        System.out.println("reparsed blacklist          : " + reparsed.get("general.blacklist"));
        System.out.println("reparsed damageReduction    : " + reparsed.get("unstoppable.damageReduction"));

        // reject an out-of-range value the way FML would
        CommentedConfig bad = TomlFormat.instance().createParser().parse(
                text.replace("championChance = 0.12", "championChance = 5.0"));
        System.out.println("isCorrect(bad value 5.0)    : " + spec.isCorrect(bad));
    }

    private TomlHarness() {}
}
