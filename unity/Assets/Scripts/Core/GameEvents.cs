#nullable enable
namespace EmberHollow.Core
{
    /// <summary>
    /// Canonical event names published on <see cref="EventBus"/>.
    ///
    /// Contract (enforced by the EditMode test <c>EventContractTests</c>): every
    /// interact-style action publishes a clearly distinct success event AND a
    /// clearly distinct failure event. Success and failure must never look or
    /// sound the same, so a shared name or a shared payload shape for the two
    /// sides of an action is a bug. This applies to fishing, mining, combat and
    /// gifting, not just farming.
    /// </summary>
    public static class GameEvents
    {
        // --- Store / lifecycle -------------------------------------------------
        public const string StateChanged = "state:changed";
        public const string UnknownAction = "store:unknown-action";
        public const string DayStarted = "day:started";
        public const string DayEnded = "day:ended";

        // --- Generic interact contract ----------------------------------------
        /// <summary>Input layer asks whoever owns the tile to resolve a tool use.</summary>
        public const string ToolUseRequested = "tool:use-requested";

        /// <summary>Success: the tool did something. Payload <see cref="ToolUsedEvent"/>.</summary>
        public const string ToolUsed = "tool:used";

        /// <summary>Failure: the tool did nothing. Payload <see cref="ToolFailedEvent"/>.</summary>
        public const string ToolFailed = "tool:failed";

        // --- Farming -----------------------------------------------------------
        public const string CropPlanted = "crop:planted";
        public const string CropHarvested = "crop:harvested";
        public const string CropPlantRejected = "crop:plant-rejected";
        public const string CropWithered = "crop:withered";
        public const string CropAdvanced = "crop:advanced";
        public const string TileWatered = "tile:watered";
        public const string FarmingBlocked = "farming:blocked";

        // --- Items / inventory -------------------------------------------------
        public const string ItemPicked = "item:picked";
        public const string InventoryFull = "inventory:full";
        public const string InventorySelected = "inventory:selected";
        public const string InventoryMoved = "inventory:moved";
        public const string ShippingSold = "shipping:sold";
        public const string ShippingBlocked = "shipping:blocked";

        // --- Player ------------------------------------------------------------
        public const string PlayerExhausted = "player:exhausted";
        public const string PlayerCollapsed = "player:collapsed";
        public const string PlayerDamaged = "player:damaged";
        public const string PlayerHealed = "player:healed";

        // --- Weather -----------------------------------------------------------
        public const string WeatherChanged = "weather:changed";
        public const string WeatherForecastUpdated = "weather:forecast";

        // --- Skills ------------------------------------------------------------
        public const string SkillLeveledUp = "skill:level-up";
        public const string SkillXpGained = "skill:xp";

        // --- Fishing (success/failure split required) --------------------------
        public const string FishingCast = "fishing:cast";
        public const string FishingBite = "fishing:bite";
        public const string FishingCaught = "fishing:caught";
        public const string FishingFled = "fishing:fled";
        public const string FishingFailed = "fishing:failed";
        public const string FishingReelIn = "fishing:reel-in";

        // --- Mining (success/failure split required) --------------------------
        public const string MiningSwing = "mining:swing";
        public const string MiningHit = "mining:hit";
        public const string MiningBroke = "mining:broke";
        public const string MiningFailed = "mining:failed";
        public const string MiningFloorCleared = "mining:floor-cleared";
        public const string MiningDescended = "mining:descended";

        // --- Combat (success/failure split required) --------------------------
        public const string CombatSwing = "combat:swing";
        public const string CombatHit = "combat:hit";
        public const string CombatMissed = "combat:missed";
        public const string CombatDodged = "combat:dodged";
        public const string MonsterKilled = "monster:killed";
        public const string PlayerHurt = "player:hurt";
        public const string BossDefeated = "boss:defeated";

        // --- Gifting (success/failure split required) -------------------------
        public const string GiftLiked = "gift:liked";
        public const string GiftLoved = "gift:loved";
        public const string GiftDisliked = "gift:disliked";
        public const string GiftRejected = "gift:rejected";

        // --- People ------------------------------------------------------------
        public const string DialogueStarted = "dialogue:started";
        public const string DialogueAdvanced = "dialogue:advanced";
        public const string DialogueEnded = "dialogue:ended";
        public const string FriendshipChanged = "friendship:changed";
        public const string EventTriggered = "event:triggered";
        public const string QuestAccepted = "quest:accepted";
        public const string QuestCompleted = "quest:completed";
        public const string QuestFailed = "quest:failed";

        // --- Economy -----------------------------------------------------------
        public const string MoneyChanged = "money:changed";
        public const string ShopOpened = "shop:opened";
        public const string ShopPurchased = "shop:purchased";
        public const string ShopRefused = "shop:refused";

        // --- Crafting / machines / animals -------------------------------------
        public const string CraftSucceeded = "craft:succeeded";
        public const string CraftFailed = "craft:failed";
        public const string MachineStarted = "machine:started";
        public const string MachineReady = "machine:ready";
        public const string AnimalFed = "animal:fed";
        public const string AnimalProductReady = "animal:product-ready";

        // --- UI / meta ---------------------------------------------------------
        public const string NoticePosted = "ui:notice";
        public const string SceneRequested = "scene:requested";
    }

    /// <summary>Payload for the success half of the generic tool contract.</summary>
    public sealed class ToolUsedEvent
    {
        public WorldPos Tile;

        public string ToolId = string.Empty;

        /// <summary>tilled, watered, cleared, planted, harvested.</summary>
        public string Effect = string.Empty;
    }

    /// <summary>Payload for the failure half of the generic tool contract.</summary>
    public sealed class ToolFailedEvent
    {
        public WorldPos Tile;

        /// <summary>Null when the player was holding nothing.</summary>
        public string? ToolId;

        /// <summary>Machine-readable reason, e.g. exhausted / frozen / not-tillable.</summary>
        public string Reason = string.Empty;
    }
}
