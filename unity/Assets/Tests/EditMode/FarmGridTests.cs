#nullable enable
using System.Collections.Generic;
using EmberHollow.Core;
using EmberHollow.Engine;
using NUnit.Framework;
using UnityEngine;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// The tile grid is the contract between the simulation and everything the
    /// player sees. If the mapping is off by one, the player tills the tile they
    /// are standing next to and the whole game reads as broken, so the round trip
    /// is pinned down here rather than discovered by eye.
    /// </summary>
    public sealed class FarmGridTests
    {
        private const int Width = 32;
        private const int Height = 24;

        [Test]
        public void TheMapIsSymmetricAboutTheOrigin()
        {
            // With the origin on a tile corner no single tile centre lands on
            // (0,0); what has to hold is that the grid is balanced around it, so
            // the field stays centred under the follow camera rather than
            // sitting off in one corner of the screen.
            for (int x = 0; x < Width; x++)
            {
                for (int y = 0; y < Height; y++)
                {
                    Vector3 a = FarmGrid.TileCenter(x, y, Width, Height);
                    Vector3 b = FarmGrid.TileCenter(Width - 1 - x, Height - 1 - y, Width, Height);

                    Assert.That(b.x, Is.EqualTo(-a.x).Within(0.001f), $"x symmetry broken at {x},{y}");
                    Assert.That(b.z, Is.EqualTo(-a.z).Within(0.001f), $"z symmetry broken at {x},{y}");
                }
            }
        }

        [Test]
        public void WorldOriginSitsOnTheCornerOfTheFourCentralTiles()
        {
            FarmGrid.TileAt(Vector3.zero, Width, Height, out int x, out int y);

            Assert.That(x, Is.EqualTo(Width / 2));
            Assert.That(y, Is.EqualTo(Height / 2));

            // One step in any direction lands in the adjacent tile, which is only
            // true if the origin falls on the shared corner.
            FarmGrid.TileAt(new Vector3(-0.01f, 0f, -0.01f), Width, Height, out x, out y);
            Assert.That(new[] { x, y }, Is.EqualTo(new[] { Width / 2 - 1, Height / 2 - 1 }));
        }

        [Test]
        public void CentreTileRoundTripsThroughWorldSpace()
        {
            FarmGrid.TileAt(new Vector3(0f, 0f, 0f), Width, Height, out int x, out int y);

            Assert.That(x, Is.EqualTo(Width / 2));
            Assert.That(y, Is.EqualTo(Height / 2));
        }

        [Test]
        public void EveryTileRoundTripsThroughWorldSpace()
        {
            for (int x = 0; x < Width; x++)
            {
                for (int y = 0; y < Height; y++)
                {
                    Vector3 centre = FarmGrid.TileCenter(x, y, Width, Height);
                    FarmGrid.TileAt(centre, Width, Height, out int rx, out int ry);

                    Assert.That(rx, Is.EqualTo(x), $"x round trip failed for {x},{y}");
                    Assert.That(ry, Is.EqualTo(y), $"z round trip failed for {x},{y}");
                }
            }
        }

        [Test]
        public void OffGridPositionsClampInsteadOfEscaping()
        {
            FarmGrid.TileAt(new Vector3(-500f, 0f, -500f), Width, Height, out int minX, out int minY);
            Assert.That(minX, Is.EqualTo(0));
            Assert.That(minY, Is.EqualTo(0));

            FarmGrid.TileAt(new Vector3(500f, 0f, 500f), Width, Height, out int maxX, out int maxY);
            Assert.That(maxX, Is.EqualTo(Width - 1));
            Assert.That(maxY, Is.EqualTo(Height - 1));
        }

        [Test]
        public void CardinalFacingsMapToOneGridStep()
        {
            FarmGrid.FacingStep(Vector3.forward, out int dx, out int dy);
            Assert.That(dx, Is.EqualTo(0));
            Assert.That(dy, Is.EqualTo(1));

            FarmGrid.FacingStep(Vector3.right, out dx, out dy);
            Assert.That(dx, Is.EqualTo(1));
            Assert.That(dy, Is.EqualTo(0));

            FarmGrid.FacingStep(Vector3.back, out dx, out dy);
            Assert.That(dx, Is.EqualTo(0));
            Assert.That(dy, Is.EqualTo(-1));

            FarmGrid.FacingStep(Vector3.left, out dx, out dy);
            Assert.That(dx, Is.EqualTo(-1));
            Assert.That(dy, Is.EqualTo(0));
        }

        [Test]
        public void DiagonalFacingPicksOneSideRatherThanSmearing()
        {
            FarmGrid.FacingStep(new Vector3(1f, 0f, 0.4f), out int dx, out int dy);
            Assert.That(Mathf.Abs(dx) + Mathf.Abs(dy), Is.EqualTo(1));
            Assert.That(dx, Is.EqualTo(1));

            FarmGrid.FacingStep(new Vector3(0.4f, 0f, 1f), out dx, out dy);
            Assert.That(Mathf.Abs(dx) + Mathf.Abs(dy), Is.EqualTo(1));
            Assert.That(dy, Is.EqualTo(1));
        }

        [Test]
        public void TheEdgeRingIsNotTillableButTheInteriorIs()
        {
            MapState map = StateFactory.MapFromDef(Content.DefaultContent.FarmMap());

            Assert.That(FarmGrid.IsTillable(map, 0, 0), Is.False, "corner must be impassable");
            Assert.That(FarmGrid.IsTillable(map, 1, 12), Is.False, "edge ring must be impassable");
            Assert.That(FarmGrid.IsTillable(map, Width - 1, Height - 1), Is.False);
            Assert.That(FarmGrid.IsTillable(map, 2, 2), Is.True);
            Assert.That(FarmGrid.IsTillable(map, Width / 2, Height / 2), Is.True);
        }

        [Test]
        public void DescribeReportsWhatIsActuallyOnTheTile()
        {
            MapState map = StateFactory.MapFromDef(Content.DefaultContent.FarmMap());

            Assert.That(FarmGrid.Describe(map, 10, 10), Is.EqualTo("Soil"));

            map.SetPlaced(new PlacedObject { Id = FarmGrid.TilledId, X = 10, Y = 10 });
            Assert.That(FarmGrid.Describe(map, 10, 10), Is.EqualTo("Tilled soil"));

            map.PlacedAt(10, 10)!.Watered = true;
            Assert.That(FarmGrid.Describe(map, 10, 10), Is.EqualTo("Watered soil"));

            Assert.That(FarmGrid.Describe(map, 0, 0), Is.EqualTo("Grass"));
        }

        [Test]
        public void TileKeysAreUnique()
        {
            HashSet<int> keys = new HashSet<int>();

            for (int x = 0; x < Width; x++)
            {
                for (int y = 0; y < Height; y++)
                {
                    Assert.That(keys.Add(FarmGrid.Key(x, y, Width)), Is.True, $"collision at {x},{y}");
                }
            }
        }
    }
}
