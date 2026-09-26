package beiwu.pantheon_champions.config;

import java.nio.file.Files;
import java.nio.file.Path;

import com.electronwill.nightconfig.core.CommentedConfig;
import com.electronwill.nightconfig.core.io.WritingMode;
import com.electronwill.nightconfig.toml.TomlFormat;

import net.neoforged.neoforge.common.ModConfigSpec;

/**
 * 把真实的 ModConfigSpec 交给 NightConfig 的 TOML 写入器生成配置文件，
 * 再把产物重新解析一遍，以此证明文件合法、且能与 spec 往返一致。
 *
 * <p>这是一个带 main() 的验证程序，不是 JUnit 测试套件——由 gradle 的
 * {@code verifyConfig} 任务（JavaExec）驱动，见 build.gradle。</p>
 *
 * <p>注意：{@code ConfigParser.parse(String)} 接收的是 TOML <b>内容</b>，不是路径。
 * 传路径会让解析器把 {@code "C:\..."} 当成配置正文，从而在盘符的冒号上报错
 * （{@code Invalid character ':' after key [C]}）——那个 {@code [C]} 是盘符，
 * 与中文注释无关。</p>
 */
public final class TomlHarness {

    public static void main(String[] args) throws Exception {
        Path out = Path.of(args.length > 0 ? args[0] : "champions-common.toml");
        Files.deleteIfExists(out);

        ModConfigSpec spec = ChampionsConfig.SPEC;

        // 用内存配置：CommentedFileConfig 的 valueMap() 是快照，
        // 注释会写进快照副本，导致 save() 产出空文件。
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

        // 抽查几个值确实活过了往返
        System.out.println("reparsed championChance     : " + reparsed.get("general.championChance"));
        System.out.println("reparsed mode               : " + reparsed.get("dualState.mode"));
        System.out.println("reparsed blacklist          : " + reparsed.get("general.blacklist"));
        System.out.println("reparsed damageReduction    : " + reparsed.get("unstoppable.damageReduction"));

        // 构造一个越界值，按 FML 的方式拒绝它（负例校验）
        CommentedConfig bad = TomlFormat.instance().createParser().parse(
                text.replace("championChance = 0.12", "championChance = 5.0"));
        System.out.println("isCorrect(bad value 5.0)    : " + spec.isCorrect(bad));
    }

    private TomlHarness() {}
}
