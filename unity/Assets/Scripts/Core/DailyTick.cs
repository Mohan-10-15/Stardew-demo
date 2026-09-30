using System;
using System.Collections.Generic;

namespace EmberHollow.Core
{
    /// <summary>
    /// The once-per-day rules that no individual tool action owns: crops grow,
    /// unwatered crops wither, and tomorrow's weather is decided.
    ///
    /// This lives in <c>EmberHollow.Core</c> and takes its randomness from an
    /// injected <see cref="Rng"/>, so a day can be advanced in an EditMode test
    /// with no scene, and replaying the same seed replays the same week.
    /// </summary>
    public static class DailyTick
    {
        /// <summary>
        /// Consecutive unwatered days a crop survives. The next one kills it,
        /// so a crop dies on the third missed watering.
        /// </summary>
        public const int MaxMissedWaterDays = 2;

        /// <summary>Days of forecast kept ahead of the player.</summary>
        public const int ForecastLength = 3;

        /// <summary>
        /// Advances every crop on every map and rolls the weather. Call once
        /// per day boundary, after the clock has rolled over.
        /// </summary>
        public static void Run(GameState state, ContentDb content, Rng rng, EventBus bus)
        {
            if (state == null)
            {
                throw new ArgumentNullException(nameof(state));
            }

            if (rng == null)
            {
                throw new ArgumentNullException(nameof(rng));
            }

            RollWeather(state, rng, bus);
            GrowCrops(state, content, bus);
        }

        /// <summary>
        /// Today's weather was already forecast yesterday, so the new day
        /// consumes the second entry of the forecast and rolls a new day onto
        /// the end. The player is therefore never surprised by weather they
        /// could have read off the almanac.
        /// </summary>
        private static void RollWeather(GameState state, Rng rng, EventBus bus)
        {
            WorldState world = state.World;
            List<Weather> forecast = world.Forecast;

            List<Weather> previous = new List<Weather>(forecast);

            // Today's weather was already predicted yesterday, so it comes off
            // the forecast rather than being rolled again.
            Weather today = previous.Count >= 2
                ? previous[1]
                : previous.Count == 1 ? previous[0] : Weather.Sun;

            WeightedEntry<Weather>[] weights = GameClock.SeasonWeatherWeights(world.Calendar.SeasonIndex);
            Weather rolled = weights.Length > 0 ? rng.Weighted(weights) : Weather.Sun;

            forecast.Clear();
            forecast.Add(today);
            for (int i = 2; i < previous.Count; i++)
            {
                forecast.Add(previous[i]);
            }

            while (forecast.Count < ForecastLength)
            {
                forecast.Add(rolled);
            }

            Weather old = world.Weather;
            world.Weather = today;

            if (old != today)
            {
                bus?.Emit(GameEvents.WeatherChanged, today);
            }
        }

        private static void GrowCrops(GameState state, ContentDb content, EventBus bus)
        {
            for (int m = 0; m < state.Maps.Count; m++)
            {
                MapState map = state.Maps[m];

                // Walk a copy: withering removes entries from the live list.
                List<PlacedObject> placed = new List<PlacedObject>(map.Placed);
                for (int i = 0; i < placed.Count; i++)
                {
                    PlacedObject obj = placed[i];
                    string? cropId = PlacedIdPrefix.CropIdOf(obj.Id);
                    if (cropId == null)
                    {
                        // Soil, machines and decorations do not grow. Their
                        // watered flag still resets so stale moisture does not
                        // carry across a day.
                        if (obj.Watered)
                        {
                            obj.Watered = false;
                        }

                        continue;
                    }

                    if (content == null || !content.TryGetCrop(cropId, out CropDef def))
                    {
                        continue;
                    }

                    if (obj.Watered)
                    {
                        obj.MissedWater = 0;
                        AdvanceStage(map, obj, def, bus);
                    }
                    else
                    {
                        obj.MissedWater++;
                        if (obj.MissedWater > MaxMissedWaterDays)
                        {
                            map.RemovePlaced(obj.X, obj.Y);
                            bus?.Emit(GameEvents.CropWithered, new CropWitheredEvent
                            {
                                Tile = new WorldPos(map.Id, obj.X, obj.Y),
                                CropId = cropId,
                            });
                            continue;
                        }
                    }

                    obj.Watered = false;
                }
            }
        }

        private static void AdvanceStage(MapState map, PlacedObject obj, CropDef def, EventBus bus)
        {
            if (obj.Stage >= def.MatureStage)
            {
                // Already ripe and waiting to be picked. Regrowing crops are put
                // back to the previous stage by the harvest, so this only holds
                // for a one-shot crop left standing.
                return;
            }

            int stageLength = def.Days[obj.Stage];
            if (stageLength <= 0)
            {
                stageLength = 1;
            }

            obj.GrownDays++;
            if (obj.GrownDays < stageLength)
            {
                return;
            }

            obj.GrownDays = 0;
            obj.Stage++;
            bus?.Emit(GameEvents.CropAdvanced, new CropAdvancedEvent
            {
                Tile = new WorldPos(map.Id, obj.X, obj.Y),
                CropId = def.Id,
                Stage = obj.Stage,
            });
        }
    }
}
