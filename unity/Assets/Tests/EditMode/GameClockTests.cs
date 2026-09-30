using EmberHollow.Core;
using NUnit.Framework;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// Clock and calendar contract. These are the rules the sleep/pass-out
    /// rollover, NPC schedules, weather and the two-year bot all depend on, so
    /// the boundaries are asserted exactly rather than approximately.
    /// </summary>
    public class GameClockTests
    {
        private static WorldState NewWorld()
        {
            return new WorldState
            {
                Calendar = new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 1 },
                Clock = new Clock { Hour = 6, Minute = 0 },
                Weather = Weather.Sun,
                Forecast = new System.Collections.Generic.List<Weather> { Weather.Sun },
                DayCount = 1,
                PassedOut = false,
            };
        }

        [Test]
        public void SixAm_IsAbsoluteMinuteZero()
        {
            Assert.AreEqual(0, GameClock.ToAbsoluteMinutes(new Clock { Hour = 6, Minute = 0 }));
        }

        [Test]
        public void Advance_MovesForwardInGameMinutes()
        {
            ClockTransition t = GameClock.Advance(NewWorld(), 60);

            Assert.AreEqual(7, t.World.Clock.Hour);
            Assert.AreEqual(0, t.World.Clock.Minute);
            Assert.IsFalse(t.DayRolled);
            Assert.IsFalse(t.PassedOut);
        }

        [Test]
        public void Advance_CountsTenMinuteTicks()
        {
            WorldState world = NewWorld();
            for (int i = 0; i < 6; i++)
            {
                world = GameClock.Advance(world, GameConstants.TickMinutes).World;
            }

            Assert.AreEqual(7, world.Clock.Hour);
            Assert.AreEqual(0, world.Clock.Minute);
            Assert.AreEqual(1, world.Calendar.DayOfMonth);
        }

        [Test]
        public void Advance_AtMidnight_RollsTheDay()
        {
            // 6:00 AM plus 18 hours lands exactly on midnight.
            ClockTransition t = GameClock.Advance(NewWorld(), 18 * 60);

            Assert.IsTrue(t.DayRolled);
            Assert.IsFalse(t.SeasonRolled);
            Assert.IsFalse(t.PassedOut);
            Assert.AreEqual(0, t.World.Clock.Hour);
            Assert.AreEqual(0, t.World.Clock.Minute);
            Assert.AreEqual(2, t.World.Calendar.DayOfMonth);
            Assert.AreEqual(2, t.World.DayCount);
        }

        [Test]
        public void Advance_BeforeMidnight_DoesNotRollTheDay()
        {
            ClockTransition t = GameClock.Advance(NewWorld(), (18 * 60) - 10);

            Assert.IsFalse(t.DayRolled);
            Assert.AreEqual(23, t.World.Clock.Hour);
            Assert.AreEqual(50, t.World.Clock.Minute);
        }

        [Test]
        public void Advance_AtTwoAm_CollapsesTheFarmerAndRollsTheDay()
        {
            ClockTransition t = GameClock.Advance(NewWorld(), 20 * 60);

            Assert.IsTrue(t.PassedOut);
            Assert.IsTrue(t.DayRolled);
            Assert.AreEqual(2, t.World.Clock.Hour);
            Assert.AreEqual(0, t.World.Clock.Minute);
            Assert.AreEqual(2, t.World.Calendar.DayOfMonth);
        }

        [Test]
        public void Advance_PastTwoAm_ClampsAtTheCollapsePoint()
        {
            // A huge tick (e.g. a stalled frame) must not run the clock into the
            // small hours of the next day.
            ClockTransition t = GameClock.Advance(NewWorld(), 30 * 60);

            Assert.IsTrue(t.PassedOut);
            Assert.AreEqual(2, t.World.Clock.Hour);
            Assert.AreEqual(0, t.World.Clock.Minute);
        }

        [Test]
        public void PassedOut_StaysSetOnceCollapsed()
        {
            WorldState world = GameClock.Advance(NewWorld(), 20 * 60).World;
            Assert.IsTrue(world.PassedOut);

            world = GameClock.StartNewDay(world);
            Assert.IsFalse(world.PassedOut, "waking up clears the collapse flag");
        }

        [Test]
        public void Advance_RollsTheSeasonOnDayTwentyNine()
        {
            WorldState world = NewWorld();
            world.Calendar.DayOfMonth = GameConstants.DaysPerSeason;

            ClockTransition t = GameClock.Advance(world, 18 * 60);

            Assert.IsTrue(t.SeasonRolled);
            Assert.IsFalse(t.YearRolled);
            Assert.AreEqual(SeasonIndex.Summer, t.World.Calendar.SeasonIndex);
            Assert.AreEqual(1, t.World.Calendar.DayOfMonth);
            Assert.AreEqual(1, t.World.Calendar.Year);
        }

        [Test]
        public void Advance_RollsTheYearAfterWinter()
        {
            WorldState world = NewWorld();
            world.Calendar.SeasonIndex = SeasonIndex.Winter;
            world.Calendar.DayOfMonth = GameConstants.DaysPerSeason;

            ClockTransition t = GameClock.Advance(world, 18 * 60);

            Assert.IsTrue(t.SeasonRolled);
            Assert.IsTrue(t.YearRolled);
            Assert.AreEqual(2, t.World.Calendar.Year);
            Assert.AreEqual(SeasonIndex.Spring, t.World.Calendar.SeasonIndex);
            Assert.AreEqual(1, t.World.Calendar.DayOfMonth);
        }

        [Test]
        public void NextDayMorning_ResetsToSixAmAndAdvancesTheCalendar()
        {
            WorldState world = NewWorld();
            world.Clock = new Clock { Hour = 23, Minute = 40 };
            world.PassedOut = true;

            WorldState next = GameClock.NextDayMorning(world);

            Assert.AreEqual(6, next.Clock.Hour);
            Assert.AreEqual(0, next.Clock.Minute);
            Assert.AreEqual(2, next.Calendar.DayOfMonth);
            Assert.AreEqual(2, next.DayCount);
            Assert.IsFalse(next.PassedOut);
        }

        [Test]
        public void NextDayMorning_ReachesTheNextMorningEvenFromLateNight()
        {
            // Unlike Advance, this must not clamp at the 2 AM collapse point.
            WorldState world = NewWorld();
            world.Clock = new Clock { Hour = 1, Minute = 30 };

            WorldState next = GameClock.NextDayMorning(world);

            Assert.AreEqual(6, next.Clock.Hour);
            Assert.AreEqual(2, next.Calendar.DayOfMonth);
        }

        [Test]
        public void NextDayMorning_LeavesTheOriginalUntouched()
        {
            WorldState world = NewWorld();
            GameClock.NextDayMorning(world);

            Assert.AreEqual(1, world.Calendar.DayOfMonth, "sim returns copies, it does not mutate in place");
            Assert.AreEqual(6, world.Clock.Hour);
        }

        [Test]
        public void WeatherAndForecast_SurviveTheAdvance()
        {
            WorldState world = NewWorld();
            world.Weather = Weather.Rain;
            world.Forecast[0] = Weather.Storm;

            WorldState next = GameClock.Advance(world, 60).World;

            Assert.AreEqual(Weather.Rain, next.Weather);
            Assert.AreEqual(Weather.Storm, next.Forecast[0]);
        }

        [Test]
        public void AddMinutes_WrapsAtMidnight()
        {
            Clock result = GameClock.AddMinutes(new Clock { Hour = 23, Minute = 50 }, 20);

            Assert.AreEqual(0, result.Hour);
            Assert.AreEqual(10, result.Minute);
        }

        [Test]
        public void WeekOf_IsZeroBasedWithinTheSeason()
        {
            Assert.AreEqual(0, GameClock.WeekOf(1));
            Assert.AreEqual(0, GameClock.WeekOf(7));
            Assert.AreEqual(1, GameClock.WeekOf(8));
            Assert.AreEqual(3, GameClock.WeekOf(28));
        }

        [Test]
        public void DaysUntil_CountsForwardAndBackward()
        {
            TimeCalendar start = new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 1 };
            TimeCalendar later = new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 11 };
            TimeCalendar nextYear = new TimeCalendar { Year = 2, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 1 };

            Assert.AreEqual(10, GameClock.DaysUntil(start, later));
            Assert.AreEqual(112, GameClock.DaysUntil(start, nextYear));
            Assert.AreEqual(-10, GameClock.DaysUntil(later, start));
            Assert.AreEqual(0, GameClock.DaysUntil(start, start));
        }

        [Test]
        public void DayIndex_IsZeroBased()
        {
            Assert.AreEqual(0, GameClock.DayIndex(new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 1 }));
            Assert.AreEqual(111, GameClock.DayIndex(new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Winter, DayOfMonth = 28 }));
            Assert.AreEqual(112, GameClock.DayIndex(new TimeCalendar { Year = 2, SeasonIndex = SeasonIndex.Spring, DayOfMonth = 1 }));
        }

        [Test]
        public void DayOfWeek_CyclesAcrossSevenDays()
        {
            for (int day = 1; day <= 7; day++)
            {
                TimeCalendar calendar = new TimeCalendar { Year = 1, SeasonIndex = SeasonIndex.Spring, DayOfMonth = day };
                Assert.AreEqual(day - 1, GameClock.DayOfWeek(calendar));
            }
        }

        [Test]
        public void DayOfWeek_StaysInRangeAcrossAYear()
        {
            for (int day = 1; day <= GameConstants.DaysPerYear; day++)
            {
                TimeCalendar calendar = new TimeCalendar
                {
                    Year = 1,
                    SeasonIndex = (SeasonIndex)((day - 1) / GameConstants.DaysPerSeason),
                    DayOfMonth = ((day - 1) % GameConstants.DaysPerSeason) + 1,
                };

                int dow = GameClock.DayOfWeek(calendar);
                Assert.GreaterOrEqual(dow, 0);
                Assert.LessOrEqual(dow, 6);
            }
        }

        [Test]
        public void ToGameMinutes_IsMonotonicAcrossMidnight()
        {
            // Schedule windows must never go backwards, so post-midnight hours
            // are offset into the 2400+ range.
            Assert.AreEqual(600, GameClock.ToGameMinutes(new Clock { Hour = 6, Minute = 0 }));
            Assert.AreEqual(2400, GameClock.ToGameMinutes(new Clock { Hour = 0, Minute = 0 }));
            Assert.AreEqual(2500, GameClock.ToGameMinutes(new Clock { Hour = 1, Minute = 0 }));
            Assert.AreEqual(2600, GameClock.ToGameMinutes(new Clock { Hour = 2, Minute = 0 }));

            int elevenPm = GameClock.ToGameMinutes(new Clock { Hour = 23, Minute = 0 });
            int midnight = GameClock.ToGameMinutes(new Clock { Hour = 0, Minute = 0 });
            Assert.Greater(midnight, elevenPm);
        }

        [Test]
        public void IsAfterPassOut_FlipsAtTwoAm()
        {
            Assert.IsFalse(GameClock.IsAfterPassOut(new Clock { Hour = 1, Minute = 50 }));
            Assert.IsTrue(GameClock.IsAfterPassOut(new Clock { Hour = 2, Minute = 0 }));
        }

        [Test]
        public void WinterWeights_ExcludeRainAndStorm()
        {
            WeightedEntry<Weather>[] winter = GameClock.SeasonWeatherWeights(SeasonIndex.Winter);

            Assert.AreEqual(0.0, WeatherWeight(winter, Weather.Rain));
            Assert.AreEqual(0.0, WeatherWeight(winter, Weather.Storm));
            Assert.Greater(WeatherWeight(winter, Weather.Snow), 0.0, "winter must be able to snow");
        }

        [Test]
        public void SummerWeights_AreTheDriest()
        {
            Assert.AreEqual(0.0, WeatherWeight(GameClock.SeasonWeatherWeights(SeasonIndex.Summer), Weather.Snow));
            Assert.AreEqual(0.0, WeatherWeight(GameClock.SeasonWeatherWeights(SeasonIndex.Summer), Weather.Wind));
        }

        [Test]
        public void DescribeDate_ReadsAsYearSeasonDay()
        {
            WorldState world = NewWorld();
            world.Calendar.DayOfMonth = 4;

            Assert.AreEqual("Year 1 Spring 4", GameClock.DescribeDate(world));
        }

        [Test]
        public void AFullDayOfTenMinuteTicks_AdvancesExactlyOneDay()
        {
            // The real tick cadence: from 6:00 AM, only 120 ticks reach the 2 AM
            // collapse. Anything more would mean the tick loop is wrong.
            WorldState world = NewWorld();
            bool passedOut = false;
            int ticks = 0;

            while (!passedOut && ticks < 1000)
            {
                ClockTransition t = GameClock.Advance(world, GameConstants.TickMinutes);
                world = t.World;
                passedOut = t.PassedOut;
                ticks++;
            }

            Assert.AreEqual(120, ticks);
            Assert.IsTrue(passedOut);
        }

        private static double WeatherWeight(WeightedEntry<Weather>[] entries, Weather weather)
        {
            for (int i = 0; i < entries.Length; i++)
            {
                if (entries[i].Value == weather)
                {
                    return entries[i].Weight;
                }
            }

            Assert.Fail($"weather {weather} missing from the weight table");
            return 0.0;
        }
    }
}
