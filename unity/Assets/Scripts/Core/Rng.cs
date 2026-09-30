#nullable enable
using System;

namespace EmberHollow.Core
{
    /// <summary>
    /// Deterministic seeded PRNG for the simulation (port of src/core/rng.ts).
    ///
    /// All randomness that affects simulation outcomes MUST flow through an
    /// <see cref="Rng"/> built from the save's seed so replays and the headless
    /// bot are bit-for-bit reproducible. The arithmetic below is a deliberate
    /// line-for-line port of the verified TypeScript mulberry32 generator,
    /// including its 32-bit wraparound, so C# and the legacy web build produce
    /// identical sequences for a given seed.
    /// </summary>
    public sealed class Rng
    {
        private uint _s;

        private const uint Gamma = 0x6d2b79f5u;
        private const double InverseTwoTo32 = 1.0 / 4294967296.0;

        public Rng(int seed)
        {
            unchecked
            {
                uint u = (uint)seed;
                _s = u != 0u ? u : 0x9e3779b9u;
            }
        }

        /// <summary>Current internal state, for save/load round-tripping.</summary>
        public int Seed
        {
            get { return unchecked((int)_s); }
            set
            {
                unchecked
                {
                    uint u = (uint)value;
                    _s = u != 0u ? u : 0x9e3779b9u;
                }
            }
        }

        /// <summary>Next float in [0, 1).</summary>
        public double Next()
        {
            unchecked
            {
                _s += Gamma;
                uint t = _s;
                t = (uint)Imul((int)(t ^ (t >> 15)), (int)(t | 1u));
                t = (uint)((int)t ^ ((int)t + Imul((int)(t ^ (t >> 7)), (int)(t | 61u))));
                return (t ^ (t >> 14)) * InverseTwoTo32;
            }
        }

        /// <summary>Next integer in [min, max], inclusive.</summary>
        public int Int(int min = 0, int max = int.MaxValue)
        {
            if (max < min)
            {
                throw new ArgumentOutOfRangeException(nameof(max), "max must be >= min");
            }

            long span = (long)max - min + 1L;
            return (int)(min + (long)(Next() * span));
        }

        /// <summary>Returns true with probability <paramref name="p"/> (0..1).</summary>
        public bool Chance(double p)
        {
            return Next() < p;
        }

        /// <summary>Uniform random element, or <c>default</c> for an empty array.</summary>
        public T Pick<T>(T[] items)
        {
            if (items == null || items.Length == 0)
            {
                throw new ArgumentException("Rng.Pick on empty array", nameof(items));
            }

            return items[Int(0, items.Length - 1)];
        }

        /// <summary>
        /// Element chosen by relative weight. Weights are clamped at zero and at
        /// least one entry must carry a positive weight.
        /// </summary>
        public T Weighted<T>(WeightedEntry<T>[] entries)
        {
            if (entries == null || entries.Length == 0)
            {
                throw new ArgumentException("Rng.Weighted on empty array", nameof(entries));
            }

            double total = 0.0;
            for (int i = 0; i < entries.Length; i++)
            {
                total += Math.Max(0.0, entries[i].Weight);
            }

            if (total <= 0.0)
            {
                throw new ArgumentException("Rng.Weighted on zero total weight", nameof(entries));
            }

            double r = Next() * total;
            for (int i = 0; i < entries.Length; i++)
            {
                r -= Math.Max(0.0, entries[i].Weight);
                if (r <= 0.0)
                {
                    return entries[i].Value;
                }
            }

            return entries[entries.Length - 1].Value;
        }

        /// <summary>Fisher-Yates shuffle in place; returns the same array.</summary>
        public T[] Shuffle<T>(T[] items)
        {
            if (items == null)
            {
                throw new ArgumentNullException(nameof(items));
            }

            for (int i = items.Length - 1; i > 0; i--)
            {
                int j = Int(0, i);
                T tmp = items[i];
                items[i] = items[j];
                items[j] = tmp;
            }

            return items;
        }

        /// <summary>
        /// Spawns an independent child stream, so one subsystem cannot shift
        /// another's results. The child captures a seed at fork time and is
        /// therefore immune to anything the parent does afterwards; note that
        /// forking itself consumes exactly one draw from the parent, which keeps
        /// the parent's own sequence deterministic for a fixed call order.
        /// </summary>
        public Rng Fork(string? label = null)
        {
            int baseSeed = Int(1, int.MaxValue);
            if (!string.IsNullOrEmpty(label))
            {
                baseSeed = unchecked(baseSeed ^ (int)HashSeed(label!));
            }

            return new Rng(baseSeed);
        }

        private static int Imul(int a, int b)
        {
            unchecked
            {
                return a * b;
            }
        }

        /// <summary>Stable non-crypto FNV-1a hash, used to derive seeds from ids.</summary>
        public static uint HashSeed(string text)
        {
            if (text == null)
            {
                throw new ArgumentNullException(nameof(text));
            }

            unchecked
            {
                uint h = 2166136261u;
                for (int i = 0; i < text.Length; i++)
                {
                    h ^= text[i];
                    h *= 16777619u;
                }

                return h;
            }
        }
    }

    /// <summary>A candidate value plus its selection weight, for <see cref="Rng.Weighted{T}"/>.</summary>
    public readonly struct WeightedEntry<T>
    {
        public WeightedEntry(T value, double weight)
        {
            Value = value;
            Weight = weight;
        }

        public T Value { get; }

        public double Weight { get; }
    }
}
