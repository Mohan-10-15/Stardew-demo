using System;

namespace EmberHollow.Core
{
    /// <summary>What a clock advance did to the calendar.</summary>
    public readonly struct ClockTransition
    {
        public ClockTransition(bool dayRolled, bool seasonRolled, bool yearRolled, bool passedOut, WorldState world)
        {
            DayRolled = dayRolled;
            SeasonRolled = seasonRolled;
            YearRolled = yearRolled;
            PassedOut = passedOut;
            World = world;
        }

        public bool DayRolled { get; }

        public bool SeasonRolled { get; }

        public bool YearRolled { get; }

        public bool PassedOut { get; }

        /// <summary>The world after the advance. Never null.</summary>
        public WorldState World { get; }
    }

    /// <summary>
    /// Deterministic clock and calendar (port of src/core/time.ts).
    ///
    /// Model: <see cref="Clock.Hour"/> is a display hour in 0..23 where 6 means
    /// 6:00 AM. Times before 6 AM only occur after midnight while the farmer
    /// stays awake. Internally the clock is converted to "absolute minutes"
    /// measured from the 6:00 AM day start: midnight is minute 1080 and the
    /// 2:00 AM pass-out point is minute 1200. Same input always yields the same
    /// output, so the headless bot and a real playthrough stay in lockstep.
    /// </summary>
    public static class GameClock
    {
        /// <summary>Minutes in a day, in absolute-minute space.</summary>
        public const int DayLengthMinutes = 24 * 60;

        /// <summary>Absolute minute of midnight, counting from 6:00 AM.</summary>
        public const int MidnightAbsoluteMinutes = 18 * 60;

        /// <summary>Absolute minute at which the farmer collapses.</summary>
        public static int PassOutAbsoluteMinutes
        {
            get { return (18 + GameConstants.PassOutHour) * 60; }
        }

        /// <summary>Converts a display clock to absolute minutes from 6:00 AM.</summary>
        public static int ToAbsoluteMinutes(Clock clock)
        {
            int m = (clock.Hour * 60) + clock.Minute;
            return m < (6 * 60) ? m + (18 * 60) : m - (6 * 60);
        }

        /// <summary>Adds minutes to a display clock, wrapping at midnight.</summary>
        public static Clock AddMinutes(Clock clock, int minutes)
        {
            int m = clock.Minute + minutes;
            int h = clock.Hour;
            while (m >= 60)
            {
                m -= 60;
                h++;
            }

            while (h >= 24)
            {
                h -= 24;
            }

            return new Clock { Hour = h, Minute = m };
        }

        public static bool IsAfterPassOut(Clock clock)
        {
            return ToAbsoluteMinutes(clock) >= PassOutAbsoluteMinutes;
        }

        /// <summary>
        /// Advances the world by <paramref name="minutes"/>, rolling the calendar
        /// as needed and clamping at the pass-out point. Intended to be called
        /// with a multiple of <see cref="GameConstants.TickMinutes"/>.
        /// </summary>
        public static ClockTransition Advance(WorldState world, int minutes)
        {
            if (world == null)
            {
                throw new ArgumentNullException(nameof(world));
            }

            bool passedOut = world.PassedOut;
            int abs = ToAbsoluteMinutes(world.Clock) + minutes;
            if (abs >= PassOutAbsoluteMinutes)
            {
                abs = PassOutAbsoluteMinutes;
                passedOut = true;
            }

            if (abs >= MidnightAbsoluteMinutes)
            {
                WorldState rolled = RollForward(world, abs - MidnightAbsoluteMinutes, passedOut, out bool seasonRolled, out bool yearRolled, out _);
                return new ClockTransition(true, seasonRolled, yearRolled, passedOut, rolled);
            }

            int displayMinutes = abs + (6 * 60);
            WorldState sameDay = world.Copy();
            sameDay.Clock = new Clock
            {
                Hour = displayMinutes / 60,
                Minute = displayMinutes % 60,
            };
            sameDay.PassedOut = passedOut;
            return new ClockTransition(false, false, false, passedOut, sameDay);
        }

        /// <summary>
        /// Advances the world straight to the next 6:00 AM, bypassing the
        /// pass-out clamp that <see cref="Advance"/> applies. Sleep and the
        /// day-end rollover use this; the calendar rules are identical.
        /// </summary>
        public static WorldState NextDayMorning(WorldState world)
        {
            if (world == null)
            {
                throw new ArgumentNullException(nameof(world));
            }

            WorldState next = world.Copy();
            AdvanceCalendarOneDay(next.Calendar, out _, out _);
            next.Clock = new Clock { Hour = GameConstants.DayStartHour, Minute = 0 };
            next.DayCount = world.DayCount + 1;
            next.PassedOut = false;
            return next;
        }

        /// <summary>Resets the clock to 6:00 AM on the same day, keeping weather.</summary>
        public static WorldState StartNewDay(WorldState world)
        {
            WorldState next = world.Copy();
            next.Clock = new Clock { Hour = GameConstants.DayStartHour, Minute = 0 };
            next.PassedOut = false;
            return next;
        }

        /// <summary>Zero-based week index within a season, 0..3.</summary>
        public static int WeekOf(int dayOfMonth)
        {
            return (dayOfMonth - 1) / 7;
        }

        /// <summary>Whole days from one calendar date to another.</summary>
        public static int DaysUntil(TimeCalendar from, TimeCalendar to)
        {
            return to.ToAbsoluteDay() - from.ToAbsoluteDay();
        }

        /// <summary>Absolute 0-based day index, where day 1 of year 1 is 0.</summary>
        public static int DayIndex(TimeCalendar calendar)
        {
            return ((calendar.Year - 1) * GameConstants.DaysPerYear)
                + ((int)calendar.SeasonIndex * GameConstants.DaysPerSeason)
                + calendar.DayOfMonth - 1;
        }

        /// <summary>Day of week, 0 = Sunday, matching the schedule data files.</summary>
        public static int DayOfWeek(TimeCalendar calendar)
        {
            int index = DayIndex(calendar) % 7;
            return index < 0 ? index + 7 : index;
        }

        private static readonly string[] DayNames =
        {
            "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        };

        public static string DayOfWeekName(TimeCalendar calendar)
        {
            return DayNames[DayOfWeek(calendar)];
        }

        /// <summary>Human-readable date, e.g. "Year 1 Spring 4".</summary>
        public static string DescribeDate(WorldState world)
        {
            return string.Format(
                "Year {0} {1} {2}",
                world.Calendar.Year,
                GameConstants.SeasonName(world.Calendar.SeasonIndex),
                world.Calendar.DayOfMonth);
        }

        /// <summary>
        /// Schedule-friendly game minutes where 6:00 AM is 600, midnight is 2400
        /// and 2:00 AM is 2600, so authored schedule windows stay monotonic
        /// across midnight.
        /// </summary>
        public static int ToGameMinutes(Clock clock)
        {
            int m = (clock.Hour * 100) + clock.Minute;
            return clock.Hour < 6 ? m + 2400 : m;
        }

        /// <summary>
        /// Per-season weather weights. Winter trades rain for snow; summer is
        /// driest; spring and fall share the default mix.
        /// </summary>
        public static WeightedEntry<Weather>[] SeasonWeatherWeights(SeasonIndex season)
        {
            switch (season)
            {
                case SeasonIndex.Winter:
                    return new[]
                    {
                        new WeightedEntry<Weather>(Weather.Sun, 6),
                        new WeightedEntry<Weather>(Weather.Rain, 0),
                        new WeightedEntry<Weather>(Weather.Storm, 0),
                        new WeightedEntry<Weather>(Weather.Snow, 3),
                        new WeightedEntry<Weather>(Weather.Wind, 1),
                    };

                case SeasonIndex.Summer:
                    return new[]
                    {
                        new WeightedEntry<Weather>(Weather.Sun, 7),
                        new WeightedEntry<Weather>(Weather.Rain, 2),
                        new WeightedEntry<Weather>(Weather.Storm, 1),
                        new WeightedEntry<Weather>(Weather.Snow, 0),
                        new WeightedEntry<Weather>(Weather.Wind, 0),
                    };

                default:
                    return new[]
                    {
                        new WeightedEntry<Weather>(Weather.Sun, 6),
                        new WeightedEntry<Weather>(Weather.Rain, 2),
                        new WeightedEntry<Weather>(Weather.Storm, 1),
                        new WeightedEntry<Weather>(Weather.Snow, 0),
                        new WeightedEntry<Weather>(Weather.Wind, 1),
                    };
            }
        }

        private static WorldState RollForward(
            WorldState world,
            int minutesIntoDay,
            bool passedOut,
            out bool seasonRolled,
            out bool yearRolled,
            out int daysRolled)
        {
            WorldState next = world.Copy();
            seasonRolled = false;
            yearRolled = false;

            int remaining = minutesIntoDay;
            int days = 1;
            while (remaining >= DayLengthMinutes)
            {
                remaining -= DayLengthMinutes;
                days++;
            }

            for (int i = 0; i < days; i++)
            {
                AdvanceCalendarOneDay(next.Calendar, ref seasonRolled, ref yearRolled);
            }

            next.Clock = new Clock { Hour = remaining / 60, Minute = remaining % 60 };
            next.DayCount = world.DayCount + days;
            next.PassedOut = passedOut;
            daysRolled = days;
            return next;
        }

        private static void AdvanceCalendarOneDay(TimeCalendar calendar, out bool seasonRolled, out bool yearRolled)
        {
            bool season = false;
            bool year = false;
            AdvanceCalendarOneDay(calendar, ref season, ref year);
            seasonRolled = season;
            yearRolled = year;
        }

        private static void AdvanceCalendarOneDay(TimeCalendar calendar, ref bool seasonRolled, ref bool yearRolled)
        {
            calendar.DayOfMonth++;
            if (calendar.DayOfMonth > GameConstants.DaysPerSeason)
            {
                calendar.DayOfMonth = 1;
                calendar.SeasonIndex++;
                seasonRolled = true;
                if ((int)calendar.SeasonIndex >= GameConstants.SeasonsPerYear)
                {
                    calendar.SeasonIndex = SeasonIndex.Spring;
                    calendar.Year++;
                    yearRolled = true;
                }
            }
        }
    }
}
