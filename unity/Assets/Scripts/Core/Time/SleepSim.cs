#nullable enable
using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>Payload for <see cref="GameEvents.SleepSucceeded"/>.</summary>
    [Serializable]
    public sealed class SleptEvent
    {
        public int DayCount;

        public int GoldEarned;

        public int Energy;
    }

    /// <summary>Payload for <see cref="GameEvents.DaySummary"/>.</summary>
    [Serializable]
    public sealed class DaySummaryEvent
    {
        public int DayCount;

        public string Date = string.Empty;

        public string Weather = string.Empty;

        public int GoldEarned;

        public List<ShippingLine> ItemsSold = new List<ShippingLine>();

        /// <summary>Copy of today's counters before they are cleared.</summary>
        public List<StatCounter> Counters = new List<StatCounter>();
    }

    /// <summary>Payload for <see cref="GameEvents.SleepBlocked"/>.</summary>
    [Serializable]
    public sealed class SleepBlockedEvent
    {
        /// <summary>Machine-readable reason: already-passed-out, no-bed.</summary>
        public string Reason = string.Empty;
    }

    /// <summary>Outcome of a sleep attempt. A blocked sleep changes no state.</summary>
    public sealed class SleepResult
    {
        public bool Succeeded { get; set; }

        public string Reason { get; set; } = string.Empty;

        public int GoldEarned { get; set; }

        public int DayCount { get; set; }

        public int Energy { get; set; }

        public static SleepResult Ok(int goldEarned, int dayCount, int energy)
        {
            return new SleepResult
            {
                Succeeded = true,
                Reason = string.Empty,
                GoldEarned = goldEarned,
                DayCount = dayCount,
                Energy = energy,
            };
        }

        public static SleepResult Fail(string reason)
        {
            return new SleepResult { Succeeded = false, Reason = reason };
        }
    }

    /// <summary>
    /// Sleep: the one explicit end-of-day action. Pays out the shipping bin,
    /// advances the calendar to the next 06:00, restores the farmer, settles
    /// crops and tomorrow's weather, and publishes a single day summary.
    ///
    /// Rules live here rather than in a MonoBehaviour so a whole 28-day season
    /// can be advanced in an EditMode test without a scene. The only engine-side
    /// concern is deciding when the player is standing at the bed; that check
    /// belongs to the input layer, which calls <see cref="Sleep"/> on success.
    /// </summary>
    public static class SleepSim
    {
        private const string DailyPrefix = "day:";

        public static SleepResult Sleep(GameState state, ContentDb content, Rng rng, EventBus bus)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (content == null)
            {
                throw new ArgumentNullException(nameof(content));
            }

            if (rng == null)
            {
                throw new ArgumentNullException(nameof(rng));
            }

            if (bus == null)
            {
                throw new ArgumentNullException(nameof(bus));
            }

            // A farmer who passed out at 2 AM was already carried home. Letting
            // them sleep again would skip a second day and double-pay the bin.
            if (state.World.PassedOut)
            {
                bus.Emit(GameEvents.SleepBlocked, new SleepBlockedEvent { Reason = "already-passed-out" });
                return SleepResult.Fail("already-passed-out");
            }

            int goldEarned = 0;
            List<ShippingLine> sold = new List<ShippingLine>();

            // Collect before the day is replaced: the payout belongs to the day
            // being ended, and the bin is empty when the player wakes up.
            if (ShippingSim.BinCount(state) > 0)
            {
                ShippingPayout payout = ShippingSim.Collect(state, content, bus);
                goldEarned = payout.Gold;
                sold.AddRange(payout.Lines);
            }

            List<StatCounter> counters = CopyDailyCounters(state);

            string date = GameClock.DescribeDate(state.World);
            string weather = state.World.Weather.ToString();
            int endedDay = state.World.DayCount;

            state.World = GameClock.NextDayMorning(state.World);
            int newDay = state.World.DayCount;

            // DailyTick owns crop growth and weather; running it here means a
            // sleep and a natural midnight rollover apply exactly the same rules.
            DailyTick.Run(state, content, rng, bus);

            state.Player.Energy = state.Player.EnergyMax;
            state.Player.Health = state.Player.HealthMax;
            state.World.PassedOut = false;

            bus.Emit(GameEvents.DayEnded, state.World);
            bus.Emit(GameEvents.DaySummary, new DaySummaryEvent
            {
                DayCount = endedDay,
                Date = date,
                Weather = weather,
                GoldEarned = goldEarned,
                ItemsSold = sold,
                Counters = counters,
            });
            bus.Emit(GameEvents.DayStarted, state.World);
            bus.Emit(GameEvents.WeatherForecastUpdated, state.World.Forecast);
            bus.Emit(GameEvents.SleepSucceeded, new SleptEvent
            {
                DayCount = newDay,
                GoldEarned = goldEarned,
                Energy = state.Player.Energy,
            });
            bus.Emit(GameEvents.NoticePosted,
                $"Day {newDay}  -  earned {goldEarned.ToString(System.Globalization.CultureInfo.InvariantCulture)}g");

            ClearDailyCounters(state);

            return SleepResult.Ok(goldEarned, newDay, state.Player.Energy);
        }

        private static List<StatCounter> CopyDailyCounters(GameState state)
        {
            List<StatCounter> copy = new List<StatCounter>();
            List<StatCounter> stats = state.Player.Stats;
            if (stats == null)
            {
                return copy;
            }

            for (int i = 0; i < stats.Count; i++)
            {
                StatCounter counter = stats[i];
                if (counter != null && counter.Key != null && counter.Key.StartsWith(DailyPrefix, StringComparison.Ordinal))
                {
                    copy.Add(new StatCounter { Key = counter.Key, Value = counter.Value });
                }
            }

            return copy;
        }

        private static void ClearDailyCounters(GameState state)
        {
            List<StatCounter> stats = state.Player.Stats;
            if (stats == null)
            {
                return;
            }

            for (int i = stats.Count - 1; i >= 0; i--)
            {
                StatCounter counter = stats[i];
                if (counter != null && counter.Key != null && counter.Key.StartsWith(DailyPrefix, StringComparison.Ordinal))
                {
                    stats.RemoveAt(i);
                }
            }
        }
    }
}
