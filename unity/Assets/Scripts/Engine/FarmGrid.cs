#nullable enable
using EmberHollow.Core;
using UnityEngine;

namespace EmberHollow.Engine
{
    /// <summary>
    /// Converts between the farm map's tile grid and world space, and answers the
    /// questions a view needs about a tile.
    ///
    /// The farm is one world unit per tile, centred on the origin, so tile
    /// <c>(0,0)</c> sits at <c>(-15.5, -11.5)</c> on the 32x24 map. Keeping the
    /// grid centred matters: the scene builder lays the field out around the
    /// origin and the camera follows the player through the middle of it, so an
    /// off-centre origin would put the playable area under one corner of the
    /// screen.
    ///
    /// Deliberately static and free of state, so the mapping is testable in
    /// EditMode with no scene loaded.
    /// </summary>
    public static class FarmGrid
    {
        /// <summary>Map id of the only map the farm scene loads.</summary>
        public const string FarmMapId = "farm";

        /// <summary>
        /// Ground code the authored legend marks as tillable. Kept in step with
        /// <c>DefaultContent.FarmMap</c>, which writes 't' for every cell inside
        /// the impassable edge ring.
        /// </summary>
        public const string TillableCode = "t";

        /// <summary>Placed-object id the farming sim uses for bare tilled soil.</summary>
        public const string TilledId = FarmingSim.TilledId;

        /// <summary>World-space centre of a tile, at ground level.</summary>
        public static Vector3 TileCenter(int x, int y, int width, int height)
        {
            return new Vector3(x - width * 0.5f + 0.5f, 0f, y - height * 0.5f + 0.5f);
        }

        /// <summary>
        /// The tile containing a world position. Clamps to the grid rather than
        /// failing, because the player can and does stand on the impassable ring
        /// where an off-grid lookup would throw away the edge of the map.
        /// </summary>
        public static void TileAt(Vector3 world, int width, int height, out int x, out int y)
        {
            x = Mathf.Clamp(Mathf.FloorToInt(world.x + width * 0.5f), 0, width - 1);
            y = Mathf.Clamp(Mathf.FloorToInt(world.z + height * 0.5f), 0, height - 1);
        }

        /// <summary>True when the tile exists and the map marks it as soil.</summary>
        public static bool IsTillable(MapState? map, int x, int y)
        {
            if (map == null || !map.Grid.InBounds(x, y))
            {
                return false;
            }

            return string.Equals(map.Grid.CodeAt(x, y), TillableCode, System.StringComparison.Ordinal);
        }

        public static WorldPos ToWorldPos(int x, int y)
        {
            return new WorldPos { MapId = FarmMapId, X = x, Y = y };
        }

        /// <summary>
        /// Reduces a facing direction to one grid step. The simulation works in
        /// tiles, so a diagonal facing has to pick a side rather than smear
        /// across two tiles.
        /// </summary>
        public static void FacingStep(Vector3 forward, out int dx, out int dy)
        {
            dx = 0;
            dy = 0;

            if (Mathf.Abs(forward.x) > Mathf.Abs(forward.z))
            {
                dx = forward.x >= 0f ? 1 : -1;
            }
            else
            {
                dy = forward.z >= 0f ? 1 : -1;
            }
        }

        /// <summary>
        /// A short, player-facing description of what is on a tile. Drives the
        /// HUD target line so the player can see what they are about to act on.
        /// </summary>
        public static string Describe(MapState? map, int x, int y, ContentDb? content = null)
        {
            if (map == null || !map.Grid.InBounds(x, y))
            {
                return "Out of bounds";
            }

            PlacedObject? placed = map.PlacedAt(x, y);

            if (placed == null)
            {
                return IsTillable(map, x, y) ? "Soil" : "Grass";
            }

            if (string.Equals(placed.Id, TilledId, System.StringComparison.Ordinal))
            {
                return placed.Watered ? "Watered soil" : "Tilled soil";
            }

            string? cropId = PlacedIdPrefix.CropIdOf(placed.Id);

            if (cropId == null)
            {
                return "Something is here";
            }

            // Ripe is a property of the crop definition, not a flag on the
            // object, so it has to be read through the content the object was
            // placed against.
            bool ripe = content != null
                && content.TryGetCrop(cropId, out CropDef def)
                && placed.Stage >= def.MatureStage;

            if (ripe)
            {
                return "Ready to harvest";
            }

            string name = content != null && content.TryGetCrop(cropId, out CropDef named)
                ? named.DisplayName
                : cropId;

            return $"{name} (stage {placed.Stage})";
        }

        /// <summary>Stable key for a tile, so views can dictionary it without a struct key.</summary>
        public static int Key(int x, int y, int width)
        {
            return (y * width) + x;
        }
    }
}
