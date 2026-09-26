# GeckoLib 4.9.3 实施指南（本模组专用）

本文的每一条都**从 4.9.3 的真实源码/字节码得来**，不是抄 wiki。
凡是 wiki 与本文件冲突的地方，**以本文件为准**，因为 wiki 现在写的是 GeckoLib 5。

复现方式（两个 jar 都在本机 Gradle 缓存里）：

```powershell
# 反编译看签名
& "D:\Java\Java21\bin\javap.exe" -p -cp <geckolib-neoforge-1.21.1-4.9.3.jar> <类名>
# 看真实源码
# 解包 geckolib-neoforge-1.21.1-4.9.3-sources.jar
```

---

## 0. 最重要的前提：wiki 版本对不上

| 来源 | 实际版本 | 是否可用于本项目 |
| --- | --- | --- |
| `wiki.geckolib.com` 的 `docs/` | **GeckoLib 5** | ❌ 不可用 |
| `docs/` 的 `versioned_docs/version-geckolib4/` | 4.x，但**只有一页存根** | ⚠️ 只有版本表 |
| `geckolib4-old-wiki`（GitHub 老 wiki） | 4.x | ✅ 结构对，但**示例代码过期** |

**决定性证据**（都是实测，不是推测）：

1. `docs/index.mdx` 第 9 行自己写着：`Welcome to the GeckoLib Wiki for GeckoLib5!`
2. 新版 `docs/entities/the-entity-renderer.mdx` 第 64 行写
   `GeoEntityRenderer<ExampleEntity, R extends EntityRenderState & GeoRenderState>`，
   但 4.9.3 的真实签名是**单泛型**：
   ```
   public class GeoEntityRenderer<T extends Entity & GeoAnimatable> extends EntityRenderer<T>
   ```
3. `GeoRenderState` 这个类在 4.9.3 里**根本不存在**（javap 报找不到类）。
4. `setTransitionTicks`、`additiveAnimations` 在 4.9.3 源码里 **ABSENT**
   （全源码 grep 零命中）——那是 GL5 的 API。

**结论**：新版 wiki 的实体/渲染章节对本项目**全部不可用**。
老 wiki 的**结构**可用，但**代码示例过期**，见第 5 节。

---

## 1. 类的最小集合：3 个

每个勇士生物需要：

1. **实体类** —— `ChampionZombie extends Zombie implements GeoEntity`
2. **模型** —— `ChampionZombieModel extends DefaultedEntityGeoModel<ChampionZombie>`
   （或注册渲染器时直接 `new`，见第 7 节）
3. **渲染器** —— `ChampionZombieRenderer extends GeoEntityRenderer<ChampionZombie>`

外加三处注册：

- `EntityType`（`DeferredRegister<EntityType<?>>`）
- `EntityAttributeCreationEvent`（给属性）
- `EntityRenderersEvent.RegisterRenderers`（**仅客户端**，见第 7 节）

---

## 2. `GeoEntity` 只需实现 2 个方法

`GeoAnimatable` 的抽象方法有三个（源码 `GeoAnimatable.java:35,44,71`）：

```java
void registerControllers(AnimatableManager.ControllerRegistrar controllers);  // 必须
AnimatableInstanceCache getAnimatableInstanceCache();                          // 必须
double getTick(Object object);                                                 // 有默认实现
```

但 `GeoEntity.java:126` 已经把 `getTick` 覆盖成可用默认值：

```java
default double getTick(Object entity) {
    return ((Entity) entity).tickCount;
}
```

所以**实体侧只需写 2 个方法**。另外还有一批 `default` 不用管：
`getBoneResetTime()`→5、`shouldPlayAnimsWhileGamePaused()`→false、
`animatableCacheOverride()`→null、`getAnimData`/`setAnimData`、
`triggerAnim`/`stopTriggeredAnim`（见第 8 节）。

标准写法：

```java
public class ChampionZombie extends Zombie implements GeoEntity {
    // 每个实例一个 cache。必须是实例字段，不能 static（见第 3 节）。
    private final AnimatableInstanceCache geoCache = GeckoLibUtil.createInstanceCache(this);

    public ChampionZombie(EntityType<? extends Zombie> type, Level level) {
        super(type, level);
    }

    @Override
    public void registerControllers(AnimatableManager.ControllerRegistrar controllers) {
        // 见第 8 节
    }

    @Override
    public AnimatableInstanceCache getAnimatableInstanceCache() {
        return this.geoCache;
    }
}
```

---

## 3. `AnimatableInstanceCache`：不要手写，也不要 static

`GeckoLibUtil.createInstanceCache(this)` 会**自动按类型分流**
（`GeckoLibUtil.java:34-38`）：

```java
return cache != null ? cache : createInstanceCache(animatable,
    !(animatable instanceof Entity) && !(animatable instanceof BlockEntity));
```

→ **Entity 一定拿到 `InstancedAnimatableInstanceCache`**（`singletonObject=false`）。
`SingletonAnimatableInstanceCache` 只给 Item/Armor 用。

**这里要澄清一个容易误传的说法**：真正的 bug 不是「选了 Singleton」，
而是**把 cache 声明成 `static`**（或跨实例共享）。那样所有僵尸共用一个
`AnimatableManager`，动画会完全同步。正确写法就是上面的
`private final` 实例字段。

所以：**不要手写 `new SingletonAnimatableInstanceCache(...)`，
也不要 override `animatableCacheOverride()`**，`createInstanceCache(this)` 就是对的。

---

## 4. 资源路径（**没有 `geckolib/` 这一层**）

4.9.3 的 `DefaultedGeoModel`（源码 75-96 行）拼接规则是：

```java
basePath.withPath("geo/"                     + subtype() + "/" + basePath.getPath() + ".geo.json");
basePath.withPath("animations/"              + subtype() + "/" + basePath.getPath() + ".animation.json");
basePath.withPath("textures/"                + subtype() + "/" + basePath.getPath() + ".png");
```

`DefaultedEntityGeoModel` 的 `subtype()` 返回 `"entity"`，`basePath` 是注册名。

| 资源 | 路径 |
| --- | --- |
| 模型 | `assets/pantheon_champions/geo/entity/<名字>.geo.json` |
| 动画 | `assets/pantheon_champions/animations/entity/<名字>.animation.json` |
| 贴图 | `assets/pantheon_champions/textures/entity/<名字>.png` |

`<名字>` 用 **registry name**（`BuiltInRegistries.ENTITY_TYPE.getKey(entityType)`），
不是类名。`basePath.getPath()` 是原样插入的，所以还能再分子目录
（例如 `geo/entity/zombie/champion_zombie.geo.json`）。

> ⚠️ **新版 wiki 写的 `geckolib/models/entity/...` 对 4.9.3 是错的，照抄会 404。**
> 那层 `geckolib/` 是 GeckoLib5 才有的。

---

## 5. 老 wiki 的 `GeoModel` 示例**编译不过**

老 wiki 教的是：

```java
// ❌ 4.9.3 里没有这两个方法，且 new ResourceLocation 编译不过
getModelLocation() / getAnimationFileLocation()
new ResourceLocation(MOD_ID, "geo/entity/foo.geo.json")
```

两个问题：

1. **方法名过期**。4.9.3 的真实签名是
   `getModelResource` / `getTextureResource` / `getAnimationResource`
   （且前两个已 `@Deprecated`，新签名多一个 `GeoRenderer<T>` 参数）。
2. **`new ResourceLocation(...)` 编译不过**。javap 确认 MC 1.21.1 里
   `ResourceLocation(String, String)` 是 **private**：

   ```
   private net.minecraft.resources.ResourceLocation(java.lang.String, java.lang.String);
   ```

   必须用 `ResourceLocation.fromNamespaceAndPath(ns, path)`。

**推荐做法**：直接用 `DefaultedEntityGeoModel`，完全绕开这些坑：

```java
public class ChampionZombieModel extends DefaultedEntityGeoModel<ChampionZombie> {
    public ChampionZombieModel() {
        super(ResourceLocation.fromNamespaceAndPath("pantheon_champions", "champion_zombie"));
    }
}
```

它会自动按第 4 节的规则找文件，不用自己写任何 `getXxxResource`。

---

## 6. `GeoEntityRenderer` 的关键差异（容易踩）

`GeoEntityRenderer` **继承的是原版 `EntityRenderer`，不是 `LivingEntityRenderer`**
（4.9.3 源码第 51 行 javap 确认）。后果：

- **没有 `addLayer`**。原版 `RenderLayer` 体系用不上，
  盔甲用 `ItemArmorGeoLayer`，手持物用 `BlockAndItemGeoLayer`，
  要加的是 `GeoRenderLayer`（走 `addRenderLayer`）。
- **默认影子半径为 0**。`EntityRenderer.shadowRadius` 是 `protected` 字段，
  子类能直接读写，但 `GeoEntityRenderer` 不会替你设；
  要显示影子就 override `getShadowRadius`（**也是 `protected`**）或自己赋值。
- 名字牌、拴绳是 GeckoLib 自己重写的，不用管。
- `getTextureLocation` **不需要 override**，默认已转调
  `GeoRenderer.super.getTextureLocation` → `model.getTextureResource(...)`。

**一个 `GeoModel` 实例一次只能服务一个 animatable**
（`GeoModel` 内有 `lastRenderedInstance` 状态）。**不要跨实体类型共享 model 实例**，
每个实体类型给一个自己的 model。

---

## 7. 渲染器注册（NeoForge 侧已 javap 验证）

```java
@EventBusSubscriber(modid = PantheonChampions.MODID, bus = EventBusSubscriber.Bus.MOD, value = Dist.CLIENT)
public final class ChampionsClientEvents {
    @SubscribeEvent
    public static void onRegisterRenderers(EntityRenderersEvent.RegisterRenderers event) {
        event.registerEntityRenderer(ChampionsEntities.CHAMPION_ZOMBIE.get(),
                                     ChampionZombieRenderer::new);
    }
}
```

要点：

- `EntityRenderersEvent.RegisterRenderers` 是 `IModBusEvent` → **走 mod 事件总线**。
- 它**只在物理客户端触发** → 必须加 `value = Dist.CLIENT`，
  否则服务端加载时会因找不到客户端类而崩。
- `GeoEntityRenderer` 有两个构造器：

  ```java
  GeoEntityRenderer(EntityRendererProvider.Context, EntityType<? extends T>)  // 自动建 DefaultedEntityGeoModel（推荐）
  GeoEntityRenderer(EntityRendererProvider.Context, GeoModel<T>)              // 自定义 model
  ```

  用第一个的话，连 model 类都不用单独写。

---

## 8. 触发动画（击晕/破盾的表现）

`GeoEntity.triggerAnim(String controllerName, String animName)` 是 **default 方法**
（`GeoEntity.java:69`），**在服务端调用会自动发包**给跟踪该实体的玩家，
不需要自己写网络包，也不需要 `registerSyncedAnimatable`（那只针对 Item/Armor）。

```java
// 注册一个可触发的 controller
controllers.add(new AnimationController<>(this, "stun_controller", 0, state -> PlayState.STOP)
        .triggerableAnim("stun", STUN_ANIMATION));

// 服务端命中时
this.triggerAnim("stun_controller", "stun");
```

语义：触发动画播放期间 controller 会**跳过 AnimationState 检查**，播完自动清除。
若希望期间仍跑 state handler，加 `.receiveTriggeredAnimations()`。

---

## 9. 已知坑（按踩到概率排序）

1. **`updateSwingTime()` 不要自己调**。老 wiki 说「不 extends Monster 才需要」，
   但实测 MC 1.21.1 的 `Monster.aiStep()` **第一行就调了**
   `updateSwingTime()`（字节码确认）。我们的勇士 `extends Monster`，
   再调一次会让挥击时间**按两倍速走**。
2. **攻击动画只播一部分** → override `getCurrentSwingDuration()` 返回更长 tick
   （默认 6）。
3. **动画无法重播** → 停时没 reset，或 `.animation.json` 的 loop 写成了
   `hold_on_last_frame`。API 是 `AnimationState#resetCurrentAnimation()`。
4. **`AnimationStateHandler` 每个渲染帧调用**，不是每 tick。别在里面做重活。
5. **发光贴图后缀是 `_glowmask`**（`AutoGlowingTexture.java:62` 的常量）。
   注意同一文件附近的 Javadoc 写的是 `_glowing`，**那是错的旧文案，以代码为准**。
6. **不能给原版模型加 GeckoLib 动画**。原版模型是 `LayerDefinition` 烘的，
   GeckoLib 只驱动自己的 `.geo.json` 骨骼树。要动画就得换模型。
7. `GeoReplacedEntity` **不适用于本项目**：它是「替换已有 EntityType 的渲染」，
   而我们注册自己的 EntityType，用不上。

---

## 10. 与附魔的衔接

三种勇士附魔的 NBT 条件依赖实体上的 `ChampionType`
（`{NeoForgeData:{ChampionType:N}}`，0 屏障 / 1 过载 / 2 势不可挡）。
**目前还没有任何代码写入该 NBT**，所以附魔现在对普通怪物不产生额外效果。

实现实体行为时要一并写入这个 NBT，附魔才会真正生效。
同时它也是第 8 节触发动画的判据来源。
