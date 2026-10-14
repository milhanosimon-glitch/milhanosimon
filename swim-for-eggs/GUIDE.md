# 🌊🥚 Swim for Eggs — Complete Build Guide

An underwater take on the classic **"Steal an Egg"** loop: dive down a sloping ocean, grab an egg from a biome's pedestal, outswim that biome's **Sea Monster**, and bring the egg back to the Safe Zone for coins. Spend the coins on bigger **Oxygen Tanks**, faster **Flippers**, and **Egg Mutations** that multiply your payouts.

Every script in this folder is complete and can be pasted straight into Studio. The map, monsters and UI are **generated in code**, so the game runs as soon as the scripts are in place. You can still swap in hand-built art later (see §2.7).

---

## 1. Engine & Setup (Roblox Studio)

### 1.1 Explorer hierarchy

Create these objects with **exactly** these names and types. Each file in `src/` maps to one object:

```
ReplicatedStorage
└── SwimForEggsShared            (Folder)
    ├── Config                   (ModuleScript)   ← src/ReplicatedStorage/SwimForEggsShared/Config.luau
    └── Signal                   (ModuleScript)   ← .../Signal.luau

ServerScriptService
├── GameBootstrap                (Script)         ← src/ServerScriptService/GameBootstrap.server.luau
└── Services                     (Folder)
    ├── DataService              (ModuleScript)   ← .../Services/DataService.luau
    ├── MapBuilder               (ModuleScript)   ← .../Services/MapBuilder.luau
    ├── SwimOxygenService        (ModuleScript)   ← .../Services/SwimOxygenService.luau
    ├── EggService               (ModuleScript)   ← .../Services/EggService.luau
    ├── MonsterFactory           (ModuleScript)   ← .../Services/MonsterFactory.luau
    ├── MonsterService           (ModuleScript)   ← .../Services/MonsterService.luau
    ├── ShopService              (ModuleScript)   ← .../Services/ShopService.luau
    ├── MonetizationService      (ModuleScript)   ← .../Services/MonetizationService.luau
    └── GameManager              (ModuleScript)   ← .../Services/GameManager.luau

StarterPlayer
└── StarterPlayerScripts
    ├── DepthLighting            (LocalScript)    ← src/StarterPlayer/StarterPlayerScripts/DepthLighting.client.luau
    └── UIController             (LocalScript)    ← src/StarterPlayer/StarterPlayerScripts/UIController.client.luau

StarterGui                       (leave empty; UIController builds every ScreenGui, see §3)
```

Created automatically at runtime:

```
ReplicatedStorage
└── SwimForEggsRemotes (Folder)
    ├── ShopAction  (RemoteFunction)  client → server: buy / equip
    ├── Notify      (RemoteEvent)     server → client: toast messages
    └── Celebrate   (RemoteEvent)     server → client: "+X COINS!" popup
Workspace
└── SwimForEggsMap (Model)   Safe Zone, Shops, Aquariums, Biomes, Spawns, Eggs, Monsters
```

> **Rojo users:** `default.project.json` is included. Run `rojo serve` from the `swim-for-eggs` folder.
> **File suffixes:** `.server.luau` is a **Script**, `.client.luau` is a **LocalScript**, and a plain `.luau` is a **ModuleScript**.

**Why one bootstrap?** `GameBootstrap` requires every service in a fixed order. It calls `:Init()` (synchronous setup, including building the map) and then `:Start()` (connections and loops). This avoids the usual "which script ran first?" race conditions. Characters only spawn after the map exists.

### 1.2 Studio settings

1. **Home → Game Settings → Security → Enable Studio Access to API Services**: turn this ON, or DataStores won't save in Studio. The game still runs without it, using temporary data.
2. **Game Settings → Avatar**: R15 is recommended. R6 also works, and the gear visuals support both.
3. **Workspace → StreamingEnabled**: OFF is simplest. If you turn it on, set `Workspace.SwimForEggsMap.ModelStreamingMode = Persistent`.
4. Publish the place before you test monetization (§5).

### 1.3 Terrain water

`MapBuilder` fills the ocean for you, so you don't need to paint anything:

| Step | Code | Result |
|---|---|---|
| Water | `Terrain:FillBlock(cf, size, Enum.Material.Water)` per zone (keeps each call well under the voxel limit) | A 320 × ~560 × 1000 stud water volume, surface at **Y = 0** |
| Seabed | A thick **rotated** `FillBlock` slab per zone, with its top face on the line `GetSeabedY(z)` | Diagonal slope from −10 to −500, with a different terrain material per biome |
| Look | `Terrain.WaterColor = (20,190,215)`, `WaterTransparency = 0.55`, `WaterReflectance = 0.25`, `WaterWaveSize = 0.12`, `WaterWaveSpeed = 8` | Bright tropical water at the surface. `DepthLighting` tints it darker as you descend |

**Painting it by hand instead:** open Terrain Editor → **Generate/Fill** → Material **Water**, region X −160…160, Y −560…0, Z 0…1000. Then use **Fill/Add** with a slanted Part as a guide to paint the seabed. Keep `Config.GetSeabedY()` in sync with the slope you paint, because the monsters use it to stay above the floor.

Swimming is the built-in `Humanoid` **Swimming** state. Roblox uses `Humanoid.WalkSpeed` as swim speed, so **Flippers set WalkSpeed while you are in water**.

### 1.4 Player data folders

`DataService` builds this under every `Player`. It replicates, so the UI reads it directly:

```
Player
├── leaderstats (Folder)            ← shown on the Roblox leaderboard
│   ├── Coins        (IntValue)
│   └── Eggs Stolen  (IntValue)
├── Gear (Folder)                   ← what is EQUIPPED
│   ├── EquippedTank     (StringValue)  "Scuba"
│   ├── EquippedFlippers (StringValue)  "Turbo"
│   └── EquippedMutation (StringValue)  "Golden"
└── Inventory (Folder)              ← what is OWNED
    ├── Tanks     (Folder) → BoolValue per owned id
    ├── Flippers  (Folder) → BoolValue per owned id
    └── Mutations (Folder) → BoolValue per owned id
```

Replicated **player attributes** that drive the HUD: `Oxygen`, `MaxOxygen`, `InWater`, `Objective`, `CarryingEgg`, `CarryingMultiplier`, `CarryingMutation`, `ChasedBy`, `LastDeathCause`, `DataLoaded`, `Pass_InfiniteOxygen`, `Pass_DoubleCoins`.

The **saved DataStore record** is one table per player (`SwimForEggs_PlayerData_v1`, key `Player_<UserId>`):

```lua
{ Coins = 0, EggsStolen = 0,
  Owned    = { Tanks = { Bubble = true }, Flippers = { Starter = true }, Mutations = { None = true } },
  Equipped = { Tanks = "Bubble", Flippers = "Starter", Mutations = "None" },
  Receipts = { "<PurchaseId>", ... } }
```

Robustness features:
- Loads retry with backoff. If a load fails in a live server, the player is **kicked rather than given blank data**, so their real save is never overwritten.
- Missing fields are reconciled from defaults, and deleted items are sanitized out.
- Saves use `UpdateAsync` and never overlap.
- The game autosaves every 120 s, saves on `PlayerRemoving`, and saves in parallel in `BindToClose`.

---

## 2. Map Design, Depth Themes & Monsters

### 2.1 Layout (side view)

```
 Y
 +40 ┃▓ BackAquarium        SAFE ZONE (Y=+1)                ▓ FarAquarium
     ┃▓  [Tanks][Flippers][Mutations]   spawn   DROP-OFF    ▓
   0 ┃▓━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈≈▓  water surface
     ┃              Z=-160 … 0                  ┗━╲ 0m  Coral Reef          ▓
-100 ┃                                              ╲━━ 100m Kelp Forest    ▓
-200 ┃                                                ╲━━ 200m Twilight     ▓
-300 ┃                                                  ╲━━ 300m Abyss      ▓
-400 ┃                                                    ╲━━ 400m Magma    ▓
-500 ┃                                                       ╲━━━━━━━━━━━━━▓ Z=1000
```

- **Safe Zone** is an island plateau from Z −160 to 0 at Y +1.
- **Ocean** sits directly in front of the island, from Z 0 to 1000. The seabed slopes diagonally from 10 m deep at the shore to 500 m at the far wall, so the formula is `seabedY = −(10 + 0.49·z)`.
- A submerged **ExitRamp** at the shoreline lets swimmers climb back onto the island.
- Each biome has **3 eggs on marble pedestals**, at roughly the zone's depth + 60 m. The biome's monster hovers 24 studs above them.

### 2.2 Depth zones & their monsters

| Depth | Biome | Terrain (Material / Color3) | Props | Lighting (local tween) | Egg value | O₂ drain |
|---|---|---|---|---|---|---|
| 0 m | **Coral Reef** | `Sand` / (255,221,153) | Branching coral (pink 255,105,180; orange 255,140,60; purple 170,85,255; yellow; teal), neon tips, starfish | Bright turquoise: Ambient (90,170,190), Atmosphere (80,220,230), Brightness 2.5 | 25 | 1.0× |
| 100 m | **Kelp Forest** | `LeafyGrass` / (70,130,60) | 30–55 stud swaying kelp stalks (`Grass` 58,145,60) with leaves, mossy boulders | Green haze: Ambient (60,120,80), Atmosphere (60,170,120), Brightness 1.6 | 100 | 1.25× |
| 200 m | **Twilight Zone** | `Slate` / (60,70,110) | Slate boulders, floating neon jellyfish (blue / pink) with PointLights | Deep blue dusk: Ambient (40,50,110), Brightness 0.8, Density 0.65 | 350 | 1.5× |
| 300 m | **Glowing Abyss** | `Basalt` / (40,25,60) | Neon crystal clusters (cyan 0,255,230 / violet 200,80,255), glowing mushrooms | Near-black violet: Ambient (60,20,110), Brightness 0.3, Bloom makes the neon pop | 1,200 | 1.75× |
| 400 m | **Magma Vents** | `CrackedLava` / (255,90,20) | Basalt chimneys with neon-orange mouths spewing ember plumes, lava rocks | Ember red: Ambient (140,50,20), Atmosphere (255,90,30), Tint (255,190,160) | 4,000 | 2.0× |

**The Sea Monsters** (built from Parts by `MonsterFactory`, driven by `MonsterService`):

| Biome | Monster | Design | Patrol → Chase speed | Kill radius | Counter-gear |
|---|---|---|---|---|---|
| Coral Reef | **Snapjaw the Reef Shark** | Steel-blue shark (90,140,200) with white belly, dorsal and tail fins, a row of teeth, glowing yellow eyes | 8 → **13** | 6 | Starter Fins (16) outrun it |
| Kelp Forest | **Kelpstrangler the Moray** | 10-segment green eel (60,110,40) with neon-lime spots. **Its whole body is deadly**, so it can cut you off | 9 → **18** | 6.5 | Coral Kickers (22) |
| Twilight Zone | **Lurelight the Anglerfish** | Bulbous dark body (35,30,60), huge underbite, a **cyan lure that lights up the dark** (PointLight, range 30) | 8 → **23** | 8 | Turbo Tails (28) |
| Glowing Abyss | **The Abyssal Kraken** | Purple mantle (110,40,170) with cyan glow spots and 8 trailing four-segment tentacles, scale 1.5 | 7 → **29** | 10 | Jet Flippers (34) |
| Magma Vents | **Magmaw the Lava Leviathan** | 14-segment basalt serpent with neon-orange cracks, horns and an ember particle aura, scale 1.6 | 10 → **36** | 11 | Mythic Mermaid Fins (42) |

Each monster's label switches between `💤 Guarding`, `😡 HUNTING` and `↩️ Returning`. When it aggros, it plays a red **RoarBurst** and freezes for 0.6–0.9 s, which gives you a short head start.

### 2.3 Shops in the Safe Zone

The three stalls stand in a row near the back of the island (Z ≈ −130) and face the spawn (Z ≈ −85):

| Stall | Position (X, Z) | Theme | Contents |
|---|---|---|---|
| 🫧 **Oxygen Tanks** | (−50, −130) | Cyan (0,200,255) | Bubble Snorkel 20 s (free) · Scuba 40 s (300) · Twin 70 s (2,000) · Deep-Sea Rig 110 s (8,000) · Nuclear Lung 180 s (28,000) |
| 🦶 **Flippers** | (0, −130) | Orange (255,170,0) | Starter 16 (free) · Coral Kickers 22 (400) · Turbo Tails 28 (2,500) · Jet 34 (9,000) · Mythic Mermaid Fins 42 (30,000) |
| 🧬 **Egg Mutations** | (+50, −130) | Violet (200,90,255) | Plain ×1 · Golden ×1.5 (1,000) · Toxic Neon ×2 (4,500) · Rainbow ×3 (15,000) · Galaxy ×5 (50,000) |

Each stall has a wood counter, white pillars, a candy-striped awning and a SurfaceGui sign. A **ProximityPrompt** (`E`, attribute `ShopId`) on the counter opens the matching shop UI. The **EGG DROP-OFF** zone is a translucent neon-green box (90 × 14 × 26) on the beach at Z −16, right where you climb out of the water.

### 2.4 Aquarium barriers (no fences anywhere)

Every map edge is a giant aquarium wall, built by `buildAquarium()`:

| Layer | Material | Color3 / settings |
|---|---|---|
| Glass shell (collides) | `Glass` | (175,235,255), Transparency 0.45, Reflectance 0.15 |
| Inner water | `SmoothPlastic` | (0,160,255), Transparency 0.6, with rising bubble particles |
| Top/bottom rails | `Neon` | Cyan (0,255,230) |
| Vertical posts every ~48 studs | `Neon` | Alternating cyan / hot pink (255,70,200) |
| Decorative fish inside | `Neon` | Orange, yellow, pink, cyan, lime |

The Left and Right walls run the full length (Z −172 to 1012) from +40 down to −570. The **Back** wall stands behind the Safe Zone and the **Far** wall stands past the Magma Vents. Monsters are also hard-clamped inside the ocean volume, so they can never leave it.

### 2.5 The classic "Steal an Egg" palette

| Element | Material | Color3 |
|---|---|---|
| Island grass | SmoothPlastic | (98, 214, 84) |
| Grass edge / trim | SmoothPlastic | (64, 170, 62) |
| Beach / ramp | Sand | (255, 226, 150) |
| Walkway path | SmoothPlastic | (255, 236, 179) |
| Shop counters | WoodPlanks | (196, 132, 74) |
| Awning stripes | SmoothPlastic | Shop theme color + (255, 255, 255) |
| Roof accent red | SmoothPlastic | (255, 72, 72) |
| Neon accents | Neon | Cyan (0,255,230) · Pink (255,70,200) · Yellow (255,230,40) |
| Drop-off zone | Neon, T = 0.75 | (0, 255, 140) |
| Palm trunks / leaves | Wood / SmoothPlastic | (160,110,60) / (60,200,80) |
| Egg pedestals | Marble + Neon ring | (240,240,250) + biome accent |

Rule of thumb for the look: use **SmoothPlastic** for every solid surface, use **Neon** only for accents, keep saturation high, and avoid realistic textures. All of these values live in `Config.Palette`, so you can retheme from one place.

### 2.6 Lighting baseline (server Lighting service)

Set these values in **Lighting**. `DepthLighting` takes over on the client from there:
`Technology = Future`, `ClockTime = 14`, `GlobalShadows = true`, `EnvironmentDiffuseScale = 0.5`, `EnvironmentSpecularScale = 0.5`. Add a `Sky` with a bright skybox if you like.

### 2.7 Using a hand-built map

Set `Config.World.BuildMapProcedurally = false`, then build `Workspace.SwimForEggsMap` containing:
- a `Spawns` folder with Parts named `EggSpawn_<zone>_<n>` (attribute `ZoneIndex` = 1–5) and `MonsterHome_<zone>`,
- a Part named `EggDropZone` (any size; scoring is a point-in-box test),
- empty `Eggs` and `Monsters` folders,
- a `SpawnLocation`, shop counters with a `ProximityPrompt` that has a string attribute `ShopId` = `Tanks` / `Flippers` / `Mutations`.

If a `SwimForEggsMap` already exists, MapBuilder uses it instead of generating one. This means you can also run the game once, copy the generated map from the running session, paste it into Edit mode and hand-polish it.

---

## 3. User Interface

`UIController` creates every ScreenGui in `PlayerGui` with `ResetOnSpawn = false`, so the UI survives respawns. To build it manually in **StarterGui** instead, copy this tree. The names are what the code relies on:

```
MainMenuGui (ScreenGui, DisplayOrder 20, IgnoreGuiInset)
└── Background (Frame, full-screen ocean gradient)
    ├── Title          "SWIM FOR EGGS" (FredokaOne, gold, thick stroke)
    ├── Subtitle
    ├── Buttons (UIListLayout)
    │   ├── PlayButton        ▶ PLAY
    │   ├── HowToPlayButton   ❓ How to Play
    │   └── StoreButton       💎 Store
    └── HowToPlayPanel (hidden) → Body, BackButton

HUDGui (ScreenGui, DisplayOrder 5)
├── TopBar (UIListLayout)
│   ├── CoinsFrame → Icon 💰, CoinsLabel
│   └── EggsFrame  → Icon 🥚, EggsLabel
├── ObjectiveFrame → ObjectiveLabel        (player attribute "Objective")
├── CarryIndicator → CarryLabel            ("🥚 Carrying Kelp Forest Egg (x1.5)")
├── OxygenFrame                            (bottom-centre)
│   ├── OxygenTitle "🫧 OXYGEN"
│   ├── OxygenBarBack → OxygenFill (smoothed; cyan > 50%, yellow > 25%, flashing red, gold = ∞)
│   └── OxygenText  "32s" / "∞ Infinite"
├── DepthMeter                             (right side)
│   ├── DepthLabel "237m"
│   ├── ZoneLabel  "Twilight Zone" (biome color)
│   └── DepthTrack → Zone1..Zone5 colored segments (with 0m/100m… marks), DepthMarker
├── ChaseWarning → WarningLabel            ("⚠️ SNAPJAW THE REEF SHARK IS CHASING YOU! ⚠️")
├── Vignette → Top / Bottom / Left / Right (pulsing red gradients while chased)
├── SideButtons → StoreButton
├── CelebratePopup                         ("+1,234 COINS! 💰")
└── ToastContainer                         (notifications)

ShopGui (ScreenGui, DisplayOrder 10)
├── TanksShop / FlippersShop / MutationsShop   (one window each, themed)
│   ├── Header → Title, CoinsLabel, CloseButton
│   └── ItemList (ScrollingFrame + UIGridLayout)
│       └── ItemCard_<id> → Swatch(Icon), ItemName, ItemStats, PriceLabel, ActionButton
│                            (BUY green/red · EQUIP blue · EQUIPPED grey)
└── RobuxStore
    ├── Header → Title, CoinsLabel, CloseButton
    └── ItemList → PassCard_InfiniteOxygen, PassCard_DoubleCoins,
                   ProductCard_Coins1000, ProductCard_Coins10000, ProductCard_OxygenRefill
```

Behaviour notes:
- The main menu runs a slow cinematic camera over the ocean with a blur. **Play** restores the normal camera and shows the HUD.
- A shop opens when its counter's prompt is triggered and closes by itself if you walk more than 25 studs away.
- A `UIScale` scales the whole UI with the screen height (0.55–1.15), so it works on phones.

---

## 4. Core Gameplay Scripts

| System | Script | What it does |
|---|---|---|
| **Gear-based swimming & oxygen** | `SwimOxygenService` | Ticks at 10 Hz on the server. If your head is below Y 0 inside the ocean, oxygen drains at `1 × zone multiplier` per second; above water it refills at 30/s. When oxygen reaches **0** you **drown** (`Health = 0`) and EggService drops the egg where you sank. WalkSpeed equals the **Flippers' SwimSpeed** in water and 16 on land. Your equipped tank is shown on your back and your flippers on your feet. Infinite Oxygen pass holders never drain. |
| **Dynamic depth lighting** | `DepthLighting` (local) | Checks camera depth about 7× per second. When you cross a 100 m boundary (or the surface), it tweens `Lighting.Ambient/OutdoorAmbient/Brightness`, the `Atmosphere`, a `ColorCorrectionEffect` and `Terrain.WaterColor` over 1.6 s. A `BloomEffect` makes neon glow. |
| **Egg + mutations** | `EggService` | A `Touched` handler on each egg checks the player is alive, not already carrying an egg and has loaded data. It then welds the egg **above your head**, applies your equipped Mutation (Neon material, matching PointLight, particles, Sparkles for Galaxy, HSV cycling for Rainbow) and labels it with its multiplier. It fires `EggStolen`. Dropped eggs float in place and anyone can grab them; after 15 s they return home. |
| **Monster AI** | `MonsterService` + `MonsterFactory` | A per-zone state machine **Patrol → Roar → Chase → Return**. Aggro starts the instant `EggStolen` fires. Chase uses **3D steering**: it aims at the target's predicted position, uses raycast whiskers to avoid obstacles (9 candidate angles, then slides along the surface), turns smoothly, and is hard-clamped inside the water and above the seabed. Eels and serpents have segmented bodies that follow the head. A catch is a distance test against the head and body segments: the egg returns to its pedestal, the player dies, and the monster swims back to patrol. It gives up if the thief leaves the water. |
| **Game manager** | `GameManager` | Checks carriers inside `EggDropZone` 10× per second. A score pays `EggValue × Mutation × (2 if 2x Coins pass)`, adds 1 to **Eggs Stolen**, drops the monster's aggro, respawns the egg after 8 s, fires the celebration popup and updates the **Objective** text. |
| **Leaderstats** | `DataService` | `Coins` and `Eggs Stolen` IntValues in `leaderstats`, kept in sync with the saved profile. |
| **Shops** | `ShopService` | A `ShopAction` RemoteFunction that checks types, item ids, price, rate limit (0.25 s), that the player isn't carrying an egg, and that they're in the Safe Zone. It buys and equips (or just equips owned items) and saves after a purchase. |

**Why steering instead of PathfindingService?** `PathfindingService` only plans walking paths on surfaces. Open water is a 3D volume, so steering with raycast avoidance is the standard approach for swimming or flying NPCs. It is also much cheaper than re-pathing every frame.

**Why not `.Touched` for monster hits?** The monsters are anchored and moved by CFrame, and `.Touched` is unreliable for that. A per-frame distance check is deterministic and works for long eel bodies too.

### Tuning cheat-sheet (`Config.luau`)
- `Config.Gameplay`: refill rate, drain, respawn timers, carry speed penalty (`CarrySpeedMultiplier`), and the dropped-egg return time.
- `Config.Zones[i].Monster`: `ChaseSpeed`, `TurnRate`, `KillRadius`, `AggroRoarTime`, `LeadTime`, `PatrolRadius`.
- `Config.Items`: prices, oxygen seconds, swim speeds and multipliers.

Speeds are balanced so that **zone N's monster is outswum by flipper tier N**, and the tank tiers match the round-trip air needed at each depth (deeper zones also drain faster).

---

## 5. Monetization

### 5.1 Create the passes and products
1. Publish the place (**File → Publish to Roblox**).
2. Go to **Creator Hub → Creations → (your experience) → Monetization**.
3. **Passes → Create a Pass**:
   - *Infinite Oxygen* (suggested 199 R$). Turn **On Sale** on.
   - *2x Coins* (suggested 249 R$).
4. **Developer Products → Create**:
   - *1,000 Coins* (suggested 49 R$)
   - *10,000 Coins* (suggested 349 R$)
   - *Emergency Air* (suggested 15 R$)
5. Copy each **ID** into `Config.GamePasses.*.Id` and `Config.DevProducts.*.Id`. Any item whose ID is still 0 stays disabled, and the UI tells the player it isn't set up yet.

### 5.2 How it works (`MonetizationService`)
- **Gamepasses**: on join, `UserOwnsGamePassAsync` (wrapped in pcall, retried 3 times) sets the attribute `Pass_InfiniteOxygen` or `Pass_DoubleCoins`. `PromptGamePassPurchaseFinished` grants the pass immediately after an in-game purchase. Gameplay code checks the attribute, for example `SwimOxygenService` skips the drain and `GameManager` doubles the coins.
- **Developer Products**: `MarketplaceService.ProcessReceipt` is the only place products are granted:
  1. An unknown product, a player who has left, or a profile that hasn't loaded returns `NotProcessedYet`, so Roblox retries later.
  2. If the `PurchaseId` is already in the saved `Receipts`, it returns `PurchaseGranted` (idempotent, so no double coins).
  3. Otherwise it grants the reward (coins or an oxygen refill) inside `pcall`, records the receipt and **saves**.
  4. It returns `PurchaseGranted` only after the save succeeds.
- The client calls `PromptGamePassPurchase` / `PromptProductPurchase` from the Robux Store cards.

> ⚠️ Only **one** script in the entire game may assign `MarketplaceService.ProcessReceipt`. Remove any free-model scripts that also set it.

### 5.3 Testing
- In Studio, purchases are simulated test purchases and no Robux is spent. Watch the Output for `[Monetization]` logs.
- To test pass perks without buying, set `Config.Monetization.StudioGrantAllPasses = true`. This only applies in Studio.

---

## 6. Play-test checklist

1. Press **Play**. The Output should print `[MapBuilder] Map built.` and then `[Swim for Eggs] Server ready 🌊🥚`.
2. The main menu appears over the cinematic ocean shot. Press **Play** to show the HUD with 0 Coins, the oxygen bar full and the depth at 0m.
3. Walk down the ramp into the water. The oxygen bar drains, the depth meter climbs, and the lighting tweens as you cross 100 m.
4. Touch a Coral Reef egg. It sits above your head, Snapjaw roars and the HUD shows the red **CHASING** warning.
5. Swim back up the ramp into the green DROP-OFF. You get +25 coins, Eggs Stolen goes up by 1 and the shark swims home.
6. Buy Scuba (300) at the Tanks stall. The tank on your back changes color and MaxOxygen becomes 40.
7. Let your oxygen run out while carrying an egg. You drown, the egg floats where you sank, and it returns home after 15 s.
8. Let a monster catch you. You die, the egg snaps back to its pedestal and the monster returns to patrol.
9. Rejoin and confirm your coins, gear and Eggs Stolen persisted. This needs API access enabled.

### Troubleshooting
| Symptom | Fix |
|---|---|
| `DataStore unavailable in Studio` warning | Enable Studio Access to API Services (§1.2). |
| Characters fall forever | Make sure `MapBuilder` exists in `Services`. Check the Output for MapBuilder errors. |
| Shop says "Shops only work in the Safe Zone" | Climb out of the water first. Shops are server-validated. |
| Monster never moves | Check that the `Spawns` folder contains `MonsterHome_<n>` parts (only matters for hand-built maps). |
| Purchases don't grant | Check that the IDs in Config are correct and that no other script sets `ProcessReceipt`. |

### Performance notes
- Monsters cost about one raycast per frame (up to 10 when blocked). The oxygen and scoring loops run at 10 Hz.
- Each biome has 55 prop clusters, and only a fraction of them carry PointLights. Lower `propCount` in `MapBuilder.buildBiomes` for low-end mobile.
- For buttery monster motion on high-ping clients, a future upgrade is to replicate only the monster's target CFrame and interpolate it on the client.
