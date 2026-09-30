using System;
using System.Collections.Generic;
using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// The determinism contract: every simulation draw flows through a seeded
    /// <c>Rng</c>, so the same seed must replay identically. The headless
    /// two-year bot in M8 depends on this.
    /// </summary>
    public class RngTests
    {
        [Test]
        public void SameSeed_ProducesIdenticalSequence()
        {
            Rng a = new Rng(1234);
            Rng b = new Rng(1234);

            for (int i = 0; i < 500; i++)
            {
                Assert.AreEqual(a.Next(), b.Next(), $"diverged at draw {i}");
            }
        }

        [Test]
        public void DifferentSeeds_ProduceDifferentSequences()
        {
            Rng a = new Rng(1);
            Rng b = new Rng(2);

            bool differed = false;
            for (int i = 0; i < 20 && !differed; i++)
            {
                differed = a.Next() != b.Next();
            }

            Assert.IsTrue(differed, "two seeds produced the same stream");
        }

        [Test]
        public void Next_StaysInUnitRange()
        {
            Rng rng = new Rng(99);
            for (int i = 0; i < 5000; i++)
            {
                double v = rng.Next();
                Assert.GreaterOrEqual(v, 0.0);
                Assert.Less(v, 1.0);
            }
        }

        [Test]
        public void Int_IsInclusiveOnBothEnds()
        {
            Rng rng = new Rng(7);
            bool sawMin = false;
            bool sawMax = false;

            for (int i = 0; i < 2000; i++)
            {
                int v = rng.Int(3, 5);
                Assert.GreaterOrEqual(v, 3);
                Assert.LessOrEqual(v, 5);
                sawMin |= v == 3;
                sawMax |= v == 5;
            }

            Assert.IsTrue(sawMin, "never produced the inclusive minimum");
            Assert.IsTrue(sawMax, "never produced the inclusive maximum");
        }

        [Test]
        public void Int_SingleValueRange_ReturnsThatValue()
        {
            Rng rng = new Rng(11);
            for (int i = 0; i < 50; i++)
            {
                Assert.AreEqual(9, rng.Int(9, 9));
            }
        }

        [Test]
        public void Int_InvertedRange_Throws()
        {
            Rng rng = new Rng(11);
            Assert.Throws<ArgumentOutOfRangeException>(() => rng.Int(10, 1));
        }

        [Test]
        public void ZeroSeed_FallsBackToGoldenRatioConstant()
        {
            Rng zero = new Rng(0);
            Rng golden = new Rng(unchecked((int)0x9e3779b9));
            Assert.AreEqual(golden.Next(), zero.Next());
        }

        [Test]
        public void Fork_IsIndependentOfParentStream()
        {
            Rng parent = new Rng(42);
            Rng childA = parent.Fork("crop:quality");
            double expected = childA.Next();

            Rng parentAgain = new Rng(42);
            Rng childB = parentAgain.Fork("crop:quality");
            Assert.AreEqual(expected, childB.Next());
        }

        [Test]
        public void Fork_ChildIsUnaffectedByLaterParentDraws()
        {
            Rng parent = new Rng(8080);
            Rng child = parent.Fork("crop:quality");
            double childValue = child.Next();

            Rng parentAgain = new Rng(8080);
            Rng childAgain = parentAgain.Fork("crop:quality");

            // The parent keeps working after the fork.
            parentAgain.Next();
            parentAgain.Next();
            parentAgain.Next();

            Assert.AreEqual(childValue, childAgain.Next(), "a forked stream must not depend on parent activity");
        }

        [Test]
        public void Weighted_RespectsZeroWeights()
        {
            Rng rng = new Rng(77);
            WeightedEntry<Weather>[] entries =
            {
                new WeightedEntry<Weather>(Weather.Snow, 0),
                new WeightedEntry<Weather>(Weather.Sun, 1),
            };

            for (int i = 0; i < 500; i++)
            {
                Assert.AreEqual(Weather.Sun, rng.Weighted(entries));
            }
        }

        [Test]
        public void Weighted_ZeroTotal_Throws()
        {
            Rng rng = new Rng(77);
            WeightedEntry<Weather>[] entries = { new WeightedEntry<Weather>(Weather.Sun, 0) };
            Assert.Throws<ArgumentException>(() => rng.Weighted(entries));
        }

        [Test]
        public void Shuffle_IsAPermutation()
        {
            Rng rng = new Rng(31337);
            int[] values = { 1, 2, 3, 4, 5, 6, 7, 8 };
            rng.Shuffle(values);

            Array.Sort(values);
            CollectionAssert.AreEqual(new[] { 1, 2, 3, 4, 5, 6, 7, 8 }, values);
        }

        [Test]
        public void Pick_EmptyArray_Throws()
        {
            Rng rng = new Rng(5);
            Assert.Throws<ArgumentException>(() => rng.Pick(Array.Empty<Weather>()));
        }

        [Test]
        public void HashSeed_IsStable()
        {
            Assert.AreEqual(Rng.HashSeed("parsnip"), Rng.HashSeed("parsnip"));
            Assert.AreNotEqual(Rng.HashSeed("parsnip"), Rng.HashSeed("parsnin"));
        }

        [Test]
        public void QualityRoll_MatchesDocumentedDistribution()
        {
            // ~94% normal / ~5% silver / ~1% gold. Asserted with a tolerance so
            // the test is not flaky but a skewed table still fails.
            const int Rolls = 20000;
            int normal = 0;
            int silver = 0;
            int gold = 0;

            Rng rng = new Rng(20260930);
            for (int i = 0; i < Rolls; i++)
            {
                switch (FarmingSim.RollQuality(rng))
                {
                    case QualityTier.Normal: normal++; break;
                    case QualityTier.Silver: silver++; break;
                    case QualityTier.Gold: gold++; break;
                }
            }

            double normalRate = (double)normal / Rolls;
            double silverRate = (double)silver / Rolls;
            double goldRate = (double)gold / Rolls;

            Assert.AreEqual(0.94, normalRate, 0.02);
            Assert.AreEqual(0.05, silverRate, 0.015);
            Assert.AreEqual(0.01, goldRate, 0.008);
        }
    }
}
