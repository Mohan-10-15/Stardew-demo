/**
 * Day-rollover weather roll (contract m1-contracts.md section 7).
 *
 * Pure functions; every draw goes through ctx.rng.fork('weather') so a given
 * seed always replays the same forecast. applyWeatherRoll is idempotent: it
 * only fires when world.dayCount has advanced past the last rolled day, so it
 * can safely be invoked from multiple reducers (time:tick, player:sleep)
 * without double-rolling.
 */
import type { EventBus } from '@game/core/events';
import type { Rng } from '@game/core/rng';
import { seasonWeatherWeights } from '@game/core/time';
import type { GameState, Weather, WorldState } from '@game/core/types';
import { WEATHERS } from '@game/core/types';
import { readWeatherExt, writeWeatherExt } from './ext';

export interface WeatherRoll {
  weather: Weather;
  forecast: Weather[];
}

export interface WeatherChangedEvent {
  weather: Weather;
  forecast: Weather[];
  dayCount: number;
}

/** Roll the next weather for `world` and shift its 3-day forecast. */
export function rollWeatherFor(world: WorldState, rng: Rng): WeatherRoll {
  const weights = seasonWeatherWeights(world.calendar.seasonIndex);
  const entries = WEATHERS.map((w) => ({ value: w, weight: weights[w] }));
  const weather = rng.fork('weather').weighted(entries);
  const forecast: Weather[] = [
    weather,
    world.forecast[0] ?? world.weather,
    world.forecast[1] ?? world.forecast[0] ?? world.weather,
  ];
  return { weather, forecast };
}

/** Roll weather once per world day; emits `weather:changed` when it rolls. */
export function applyWeatherRoll(state: GameState, rng: Rng, bus: EventBus): GameState {
  const wext = readWeatherExt(state);
  if (wext.lastRolledDay === state.world.dayCount) return state;
  const { weather, forecast } = rollWeatherFor(state.world, rng);
  const world: WorldState = { ...state.world, weather, forecast };
  const next = writeWeatherExt({ ...state, world }, { lastRolledDay: state.world.dayCount });
  const payload: WeatherChangedEvent = { weather, forecast, dayCount: state.world.dayCount };
  bus.emit('weather:changed', payload);
  return next;
}
