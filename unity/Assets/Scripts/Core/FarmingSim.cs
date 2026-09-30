using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>Tool families. Kinds are derived from the item id prefix.</summary>
    public enum ToolKind
    {
        Hoe = 0,
        Watering = 1,
        Axe = 2,
        Pickaxe = 3,
        Scythe = 4,

        /// <summary>Owned by the fishing feature, which claims it off the bus.</summary>
        Fishing = 5,

        /// <summary>Bare hands: harvest, forage, plant.</summary>
        Hands = 6,
    }

    /// <summary>Request to resolve one tool swing at a tile.</summary>
    public readonly struct ToolUseRequest
    {
        public ToolUseRequest(WorldPos tile, string? toolId)
        {
            Tile = tile;
            ToolId = toolId;
        }

        public WorldPos Tile { get; }

        /// <summary>Held item id, or null when the player is holding nothing.</summary>
        public string? ToolId { get; }
    }

    /// <summary>What a tool swing actually did.</summary>
    public sealed class ToolResult
    {
        private ToolResult(bool succeeded, string effect, string reason)
        {
            Succeeded = succeeded;
            Effect = effect;
            Reason = reason;
        }

        public bool Succeeded { get; }

        /// <summary>tilled, watered, cleared, planted, harvested, or none.</summary>
        public string Effect { get; }

        /// <summary>Machine-readable failure reason, empty on success.</summary>
        public string Reason { get; }

        public static ToolResult Ok(string effect)
        {
            return new ToolResult(true, effect, string.Empty);
        }

        public static ToolResult Fail(string reason)
        {
            return new ToolResult(false, "none", reason);
        }
    }

    /// <summary>Payload for <see cref="GameEvents.CropPlanted"/>.</summary>
    public sealed class CropPlantedEvent
    {
        public WorldPos Tile;

        public string CropId = string.Empty;

        public string SeedId = string.Empty;
    }

    /// <summary>Payload for <see cref="GameEvents.CropHarvested"/>.</summary>
    public sealed class CropHarvestedEvent
    {
        public WorldPos Tile;

        public string CropId = string.Empty;

        public int Qty;

        public QualityTier Quality;
    }

    /// <summary>Payload for <see cref="GameEvents.CropAdvanced"/>.</summary>
    public sealed class CropAdvancedEvent
    {
        public WorldPos Tile;

        public string CropId = string.Empty;

        /// <summary>The stage just reached; equals <c>CropDef.MatureStage</c> when ripe.</summary>
        public int Stage;
    }

    /// <summary>Payload for <see cref="GameEvents.CropWithered"/>.</summary>
    public sealed class CropWitheredEvent
    {
        public WorldPos Tile;

        public string CropId = string.Empty;
    }

    /// <summary>Payload for <see cref="GameEvents.CropPlantRejected"/>.</summary>
    public sealed class CropPlantRejectedEvent
    {
        public WorldPos Tile;

        public string SeedId = string.Empty;

        public string Reason = string.Empty;
    }

    /// <summary>Payload for <see cref="GameEvents.ItemPicked"/>.</summary>
    public sealed class ItemPickedEvent
    {
        public WorldPos Tile;

        public string ItemId = string.Empty;

        public int Qty;
    }

    /// <summary>Payload for <see cref="GameEvents.InventoryFull"/>.</summary>
    public sealed class InventoryFullEvent
    {
        public WorldPos Tile;

        public string ItemId = string.Empty;
    }

    /// <summary>Payload for <see cref="GameEvents.TileWatered"/>.</summary>
    public sealed class TileWateredEvent
    {
        public WorldPos Tile;
    }

    /// <summary>Payload for <see cref="GameEvents.PlayerExhausted"/>.</summary>
    public sealed class PlayerExhaustedEvent
    {
        public WorldPos Tile;

        public string ToolId = string.Empty;

        public int Energy;
    }

    /// <summary>Payload for <see cref="GameEvents.FarmingBlocked"/>.</summary>
    public sealed class FarmingBlockedEvent
    {
        public string Reason = string.Empty;

        public WorldPos Tile;
    }

    /// <summary>
    /// Farming simulation: tools, till/plant/water/harvest, energy costs and
    /// quality rolls (port of src/features/farming/sim/FarmingSim.ts).
    ///
    /// Integration contract: the input layer publishes
    /// <see cref="GameEvents.ToolUseRequested"/>; this module subscribes to it and
    /// resolves the outcome, always publishing either
    /// <see cref="GameEvents.ToolUsed"/> or <see cref="GameEvents.ToolFailed"/> —
    /// never both, never neither. Seeds resolve as a plant action and bare hands
    /// harvest mature crops. All randomness flows through the injected
    /// <see cref="Rng"/>, never <c>UnityEngine.Random</c>.
    /// </summary>
    public static class FarmingSim
    {
        /// <summary>Prefixes that map an item id to a tool family.</summary>
        public const string HoePrefix = "hoe-";

        public const string WateringCanPrefix = "watering-can-";
        public const string AxePrefix = "axe-";
        public const string PickaxePrefix = "pickaxe-";
        public const string ScythePrefix = "scythe-";
        public const string FishingRodPrefix = "fishing-rod-";

        /// <summary>Placed-object id for bare tilled soil.</summary>
        public const string TilledId = "tilled";

        /// <summary>Experience awarded per harvest and per foraged item.</summary>
        public const int HarvestXp = 15;

        public const int ForageXp = 12;

        /// <summary>
        /// Energy per swing. Charged on any swing the farmer can afford,
        /// including one that turns out to do nothing, so swinging at a wall
        /// teaches the cost rather than being free. The fishing family is
        /// excluded because <c>fish:sim</c> claims it off the bus.
        /// </summary>
        public static int EnergyCost(ToolKind kind)
        {
            switch (kind)
            {
                case ToolKind.Hoe: return 6;
                case ToolKind.Watering: return 4;
                case ToolKind.Axe: return 8;
                case ToolKind.Pickaxe: return 8;
                case ToolKind.Scythe: return 2;
                default: return 0;
            }
        }

        /// <summary>What each kind of removable debris yields.</summary>
        public static string DebrisDropId(string debrisId, out int qty)
        {
            switch (debrisId)
            {
                case "weed": qty = 1; return "fiber";
                case "branch": qty = 1; return "wood";
                case "stump": qty = 2; return "wood";
                case "rock": qty = 1; return "stone";
                default: qty = 0; return string.Empty;
            }
        }

        /// <summary>Derives the tool family from a held item id.</summary>
        public static ToolKind KindOf(string? toolId)
        {
            if (string.IsNullOrEmpty(toolId))
            {
                return ToolKind.Hands;
            }

            string id = toolId!;
            if (id.StartsWith(HoePrefix, StringComparison.Ordinal))
            {
                return ToolKind.Hoe;
            }

            if (id.StartsWith(WateringCanPrefix, StringComparison.Ordinal))
            {
                return ToolKind.Watering;
            }

            if (id.StartsWith(AxePrefix, StringComparison.Ordinal))
            {
                return ToolKind.Axe;
            }

            if (id.StartsWith(PickaxePrefix, StringComparison.Ordinal))
            {
                return ToolKind.Pickaxe;
            }

            if (id.StartsWith(ScythePrefix, StringComparison.Ordinal))
            {
                return ToolKind.Scythe;
            }

            if (id.StartsWith(FishingRodPrefix, StringComparison.Ordinal))
            {
                return ToolKind.Fishing;
            }

            return ToolKind.Hands;
        }

        /// <summary>
        /// Maps a tool id to the upgrade tier encoded in its id, or 0. Ids are
        /// authored as <c>&lt;name&gt;-t&lt;tier&gt;</c> (for example
        /// <c>pickaxe-t3</c>), and a bare numeric suffix is also accepted.
        /// </summary>
        public static int TierOf(string? toolId)
        {
            if (string.IsNullOrEmpty(toolId))
            {
                return 0;
            }

            int dash = toolId!.LastIndexOf('-');
            if (dash < 0 || dash + 1 >= toolId.Length)
            {
                return 0;
            }

            string suffix = toolId.Substring(dash + 1);
            if (suffix.Length > 1 && (suffix[0] == 't' || suffix[0] == 'T'))
            {
                suffix = suffix.Substring(1);
            }

            return int.TryParse(suffix, out int tier) ? tier : 0;
        }

        /// <summary>
        /// Harvest quality roll: ~94% normal, ~5% silver, ~1% gold. Uses a
        /// dedicated fork so quality never perturbs the main simulation stream.
        /// </summary>
        public static QualityTier RollQuality(Rng rng)
        {
            if (rng == null)
            {
                throw new ArgumentNullException(nameof(rng));
            }

            double r = rng.Fork("crop:quality").Next();
            if (r < 0.94)
            {
                return QualityTier.Normal;
            }

            return r < 0.99 ? QualityTier.Silver : QualityTier.Gold;
        }

        /// <summary>
        /// Resolves one tool swing: mutates <paramref name="state"/>, charges
        /// energy, and publishes exactly one of
        /// <see cref="GameEvents.ToolUsed"/> / <see cref="GameEvents.ToolFailed"/>.
        /// </summary>
        public static ToolResult ApplyToolUse(
            GameState state,
            ToolUseRequest request,
            Rng rng,
            ContentDb content,
            EventBus bus)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (rng == null)
            {
                throw new ArgumentNullException(nameof(rng));
            }

            if (content == null)
            {
                throw new ArgumentNullException(nameof(content));
            }

            if (bus == null)
            {
                throw new ArgumentNullException(nameof(bus));
            }

            string toolId = request.ToolId ?? string.Empty;
            ToolKind kind = KindOf(toolId);
            WorldPos tile = request.Tile;

            MapState? map = state.MapAt(tile);
            PlacedObject? occupant = map?.PlacedAt(tile.X, tile.Y);

            // A machine tile belongs to the machine feature. Farming has nothing
            // to do here, so a spurious tool:failed never reaches audio or UI.
            if (occupant != null && content.IsMachine(occupant.Id))
            {
                return ToolResult.Fail("machine-tile");
            }

            // Holding a machine means "place this", which the machine feature
            // claims from the same bus event. Defer rather than reporting
            // 'nothing' for a placement that is about to succeed.
            if (content.IsMachine(toolId))
            {
                return ToolResult.Fail("machine-place");
            }

            // Winter: the soil is frozen, so tilling is rejected with no state
            // change. Distinct from every other failure so the view can show a
            // cold puff rather than the generic thud.
            if (kind == ToolKind.Hoe && state.World.Calendar.SeasonIndex == SeasonIndex.Winter)
            {
                bus.Emit(GameEvents.FarmingBlocked, new FarmingBlockedEvent { Reason = "frozen", Tile = tile });
                bus.Emit(GameEvents.ToolFailed, new ToolFailedEvent { Tile = tile, ToolId = request.ToolId, Reason = "frozen" });
                return ToolResult.Fail("frozen");
            }

            // Rod tools belong to the fishing feature, which resolves them via
            // its own bus subscription. Skip rather than report a false failure.
            if (kind == ToolKind.Fishing)
            {
                return ToolResult.Fail("fishing-owned");
            }

            if (kind == ToolKind.Hands)
            {
                ToolResult hands = ApplyHands(state, tile, toolId, rng, content, bus);
                Announce(bus, hands, tile, request.ToolId);
                return hands;
            }

            int cost = EnergyCost(kind);
            if (state.Player.Energy < cost)
            {
                bus.Emit(GameEvents.PlayerExhausted, new PlayerExhaustedEvent
                {
                    Tile = tile,
                    ToolId = toolId,
                    Energy = state.Player.Energy,
                });
                bus.Emit(GameEvents.ToolFailed, new ToolFailedEvent { Tile = tile, ToolId = request.ToolId, Reason = "exhausted" });
                return ToolResult.Fail("exhausted");
            }

            state.Player.Energy -= cost;
            ToolResult result = ApplyToolEffect(state, kind, tile, content, bus);
            Announce(bus, result, tile, request.ToolId);
            return result;
        }

        private static void Announce(EventBus bus, ToolResult result, WorldPos tile, string? toolId)
        {
            if (result.Succeeded)
            {
                bus.Emit(GameEvents.ToolUsed, new ToolUsedEvent
                {
                    Tile = tile,
                    ToolId = toolId ?? string.Empty,
                    Effect = result.Effect,
                });
            }
            else
            {
                bus.Emit(GameEvents.ToolFailed, new ToolFailedEvent
                {
                    Tile = tile,
                    ToolId = toolId,
                    Reason = result.Reason,
                });
            }
        }

        private static ToolResult ApplyToolEffect(
            GameState state,
            ToolKind kind,
            WorldPos tile,
            ContentDb content,
            EventBus bus)
        {
            MapState? map = state.MapAt(tile);
            if (map == null)
            {
                return ToolResult.Fail("no-map");
            }

            string? code = map.Grid.CodeAt(tile.X, tile.Y);
            if (code == null)
            {
                return ToolResult.Fail("out-of-bounds");
            }

            switch (kind)
            {
                case ToolKind.Hoe:
                {
                    bool tillable = content.TryGetMap(tile.MapId, out MapDef def) && def.IsTillable(code!);
                    if (!tillable)
                    {
                        return ToolResult.Fail("not-tillable");
                    }

                    if (map.PlacedAt(tile.X, tile.Y) != null)
                    {
                        return ToolResult.Fail("occupied");
                    }

                    map.SetPlaced(new PlacedObject
                    {
                        Id = TilledId,
                        X = tile.X,
                        Y = tile.Y,
                        Watered = false,
                    });
                    return ToolResult.Ok("tilled");
                }

                case ToolKind.Watering:
                {
                    PlacedObject? target = map.PlacedAt(tile.X, tile.Y);
                    if (target == null)
                    {
                        return ToolResult.Fail("no-soil");
                    }

                    bool isTilled = string.Equals(target.Id, TilledId, StringComparison.Ordinal);
                    bool isCrop = PlacedIdPrefix.CropIdOf(target.Id) != null;
                    if (!isTilled && !isCrop)
                    {
                        return ToolResult.Fail("no-soil");
                    }

                    target.Watered = true;
                    bus.Emit(GameEvents.TileWatered, new TileWateredEvent { Tile = tile });
                    return ToolResult.Ok("watered");
                }

                case ToolKind.Axe:
                    return ClearDebris(state, tile, new[] { "weed", "branch", "stump" }, bus);

                case ToolKind.Pickaxe:
                    return ClearDebris(state, tile, new[] { "rock" }, bus);

                case ToolKind.Scythe:
                {
                    PlacedObject? target = map.PlacedAt(tile.X, tile.Y);
                    if (target != null && PlacedIdPrefix.ForageIdOf(target.Id) != null)
                    {
                        return PickForage(state, tile, bus);
                    }

                    return ClearDebris(state, tile, new[] { "weed" }, bus);
                }

                default:
                    return ToolResult.Fail("no-effect");
            }
        }

        private static ToolResult ApplyHands(
            GameState state,
            WorldPos tile,
            string toolId,
            Rng rng,
            ContentDb content,
            EventBus bus)
        {
            MapState? map = state.MapAt(tile);
            PlacedObject? obj = map?.PlacedAt(tile.X, tile.Y);

            string? cropId = obj != null ? PlacedIdPrefix.CropIdOf(obj.Id) : null;
            if (cropId != null && obj != null)
            {
                if (!content.TryGetCrop(cropId, out CropDef def))
                {
                    return ToolResult.Fail("no-crop");
                }

                if (obj.Stage < def.MatureStage)
                {
                    return ToolResult.Fail("not-mature");
                }

                return HarvestCrop(state, tile, obj, cropId, def, rng, bus);
            }

            if (obj != null && PlacedIdPrefix.ForageIdOf(obj.Id) != null)
            {
                return PickForage(state, tile, bus);
            }

            // Planting. If the tile is bare soil, treat the held item as a
            // planting attempt regardless of whether it is a known seed, so an
            // unrecognised seed bag reports "no-crop" rather than the useless
            // "nothing is here". On other tiles only a real seed attempts a
            // plant, so picking up a rock still says "nothing".
            bool onTilledSoil = obj != null && string.Equals(obj.Id, TilledId, StringComparison.Ordinal);
            bool isKnownSeed = !string.IsNullOrEmpty(toolId) && content.CropForSeed(toolId) != null;
            if (onTilledSoil || isKnownSeed)
            {
                return ApplyPlant(state, tile, toolId ?? string.Empty, content, bus);
            }

            return ToolResult.Fail("nothing");
        }

        /// <summary>
        /// Plants a seed on tilled soil. Consumes exactly one seed, and refuses
        /// with a distinct reason for each failure so the view and audio can
        /// react differently.
        /// </summary>
        public static ToolResult ApplyPlant(
            GameState state,
            WorldPos tile,
            string seedId,
            ContentDb content,
            EventBus bus)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (content == null)
            {
                throw new ArgumentNullException(nameof(content));
            }

            if (bus == null)
            {
                throw new ArgumentNullException(nameof(bus));
            }

            CropDef? crop = content.CropForSeed(seedId);
            if (crop == null)
            {
                return ToolResult.Fail("no-crop");
            }

            MapState? map = state.MapAt(tile);
            if (map == null)
            {
                return ToolResult.Fail("no-map");
            }

            PlacedObject? soil = map.PlacedAt(tile.X, tile.Y);
            if (soil == null || !string.Equals(soil.Id, TilledId, StringComparison.Ordinal))
            {
                return ToolResult.Fail("not-tilled");
            }

            if (!crop.GrowsIn(state.World.Calendar.SeasonIndex))
            {
                bus.Emit(GameEvents.CropPlantRejected, new CropPlantRejectedEvent
                {
                    Tile = tile,
                    SeedId = seedId,
                    Reason = "wrong-season",
                });
                return ToolResult.Fail("wrong-season");
            }

            int seedSlot = FindSeedSlot(state, seedId);
            if (seedSlot < 0)
            {
                return ToolResult.Fail("no-seed");
            }

            ItemStack? stack = state.Player.Inventory.Slots[seedSlot];
            if (stack != null && stack.Qty > 1)
            {
                stack.Qty -= 1;
            }
            else
            {
                state.Player.Inventory.Slots[seedSlot] = ItemStack.Empty();
            }

            map.SetPlaced(new PlacedObject
            {
                Id = PlacedIdPrefix.Crop(crop.Id),
                X = tile.X,
                Y = tile.Y,
                Stage = 0,
                Watered = false,
                GrownDays = 0,
                MissedWater = 0,
            });

            bus.Emit(GameEvents.CropPlanted, new CropPlantedEvent
            {
                Tile = tile,
                CropId = crop.Id,
                SeedId = seedId,
            });

            return ToolResult.Ok("planted");
        }

        private static ToolResult HarvestCrop(
            GameState state,
            WorldPos tile,
            PlacedObject crop,
            string cropId,
            CropDef def,
            Rng rng,
            EventBus bus)
        {
            QualityTier quality = RollQuality(rng);
            int added = InventorySim.AddStack(state, ItemStack.Of(cropId, 1, quality));
            if (added <= 0)
            {
                bus.Emit(GameEvents.InventoryFull, new InventoryFullEvent { Tile = tile, ItemId = cropId });
                return ToolResult.Fail("inventory-full");
            }

            MapState map = state.MapAt(tile)!;

            if (def.Regrows)
            {
                int reset = Math.Max(0, def.Days.Length - def.RegrowDays);
                map.SetPlaced(new PlacedObject
                {
                    // Keep the original "crop:<id>" id so the tile is still
                    // recognised as a crop after it is picked back to stage.
                    Id = crop.Id,
                    X = crop.X,
                    Y = crop.Y,
                    Stage = reset,
                    GrownDays = reset,
                    Watered = false,
                    MissedWater = 0,
                    Variant = crop.Variant,
                });
            }
            else
            {
                map.SetPlaced(new PlacedObject
                {
                    Id = TilledId,
                    X = crop.X,
                    Y = crop.Y,
                    Watered = false,
                });
            }

            state.BumpStat("day:harvest:" + cropId, 1);
            state.BumpStat("day:xp:farming", HarvestXp);

            bus.Emit(GameEvents.CropHarvested, new CropHarvestedEvent
            {
                Tile = tile,
                CropId = cropId,
                Qty = 1,
                Quality = quality,
            });

            return ToolResult.Ok("harvested");
        }

        private static ToolResult ClearDebris(
            GameState state,
            WorldPos tile,
            string[] allowed,
            EventBus bus)
        {
            MapState? map = state.MapAt(tile);
            if (map == null)
            {
                return ToolResult.Fail("no-map");
            }

            PlacedObject? obj = map.PlacedAt(tile.X, tile.Y);
            if (obj == null)
            {
                return ToolResult.Fail("no-debris");
            }

            bool allowedHere = false;
            for (int i = 0; i < allowed.Length; i++)
            {
                if (string.Equals(allowed[i], obj.Id, StringComparison.Ordinal))
                {
                    allowedHere = true;
                    break;
                }
            }

            if (!allowedHere)
            {
                return ToolResult.Fail("no-debris");
            }

            string dropId = DebrisDropId(obj.Id, out int dropQty);
            if (dropId.Length == 0)
            {
                return ToolResult.Fail("no-drop");
            }

            int added = InventorySim.AddStack(state, ItemStack.Of(dropId, dropQty));
            if (added <= 0)
            {
                bus.Emit(GameEvents.InventoryFull, new InventoryFullEvent { Tile = tile, ItemId = dropId });
                return ToolResult.Fail("inventory-full");
            }

            map.RemovePlaced(tile.X, tile.Y);
            bus.Emit(GameEvents.ItemPicked, new ItemPickedEvent { Tile = tile, ItemId = dropId, Qty = dropQty });
            return ToolResult.Ok("cleared");
        }

        /// <summary>Picks up a <c>forage:&lt;itemId&gt;</c> placed object.</summary>
        private static ToolResult PickForage(GameState state, WorldPos tile, EventBus bus)
        {
            MapState? map = state.MapAt(tile);
            if (map == null)
            {
                return ToolResult.Fail("no-map");
            }

            PlacedObject? obj = map.PlacedAt(tile.X, tile.Y);
            string? itemId = PlacedIdPrefix.ForageIdOf(obj?.Id);
            if (obj == null || itemId == null)
            {
                return ToolResult.Fail("no-forage");
            }

            int added = InventorySim.AddStack(state, ItemStack.Of(itemId, 1));
            if (added <= 0)
            {
                bus.Emit(GameEvents.InventoryFull, new InventoryFullEvent { Tile = tile, ItemId = itemId });
                return ToolResult.Fail("inventory-full");
            }

            map.RemovePlaced(tile.X, tile.Y);
            state.BumpStat("day:forage:" + itemId, 1);
            state.BumpStat("day:xp:foraging", ForageXp);
            bus.Emit(GameEvents.ItemPicked, new ItemPickedEvent { Tile = tile, ItemId = itemId, Qty = 1 });
            return ToolResult.Ok("cleared");
        }

        private static int FindSeedSlot(GameState state, string seedId)
        {
            InventoryState inv = state.Player.Inventory;
            if (inv.Selected >= 0 && inv.Selected < inv.Slots.Count)
            {
                ItemStack? selected = inv.Slots[inv.Selected];
                if (selected != null && !selected.IsEmpty && string.Equals(selected.Id, seedId, StringComparison.Ordinal))
                {
                    return inv.Selected;
                }
            }

            for (int i = 0; i < inv.Slots.Count; i++)
            {
                ItemStack? slot = inv.Slots[i];
                if (slot != null && !slot.IsEmpty && string.Equals(slot.Id, seedId, StringComparison.Ordinal))
                {
                    return i;
                }
            }

            return -1;
        }

        /// <summary>
        /// Wires farming into a bus and store, so an input-layer
        /// <see cref="GameEvents.ToolUseRequested"/> becomes a resolved action.
        /// </summary>
        public static IDisposable Subscribe(EventBus bus, ContentDb content, Rng rng, Func<GameState> stateAccessor)
        {
            if (bus == null)
            {
                throw new ArgumentNullException(nameof(bus));
            }

            if (stateAccessor == null)
            {
                throw new ArgumentNullException(nameof(stateAccessor));
            }

            return bus.On<ToolUseRequest>(GameEvents.ToolUseRequested, request =>
            {
                GameState state = stateAccessor();
                if (state == null)
                {
                    return;
                }

                ApplyToolUse(state, request, rng, content, bus);
            });
        }
    }
}
