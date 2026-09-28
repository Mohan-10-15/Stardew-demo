/**
 * T-0511 day-loop specs (WORKER-3 lane). The dialogs are browser-only, so the
 * headless gate pins the pure layer under them plus the keymap wiring that
 * reaches them: which stack actions are offered, what the bin will pay, what
 * the herd and the machines look like, that every denial has a sentence, and
 * that a day cannot be lost to one stray keypress.
 */
import { describe, expect, it } from 'vitest';
import '@game/features/day-loop';
import { animalsSim, MIN_HEARTS_TO_PRODUCE } from '@game/features/animals/sim/AnimalsSim';
import { machinesSim } from '@game/features/machines/sim/MachinesSim';
import { craftingSim } from '@game/features/crafting/sim/CraftingSim';
import { tileKey } from '@game/features/farming/sim/utils';
import { actionToSim, DEFAULT_KEYMAP, findBinding, keyForAction, keyGlyph } from '@game/features/input/keymap';
import { MESSAGES } from '@game/features/ui-kit/i18n/en';
import {
  animalProductText,
  BARN_ACTION_LABELS,
  barnActionForKey,
  barnRowHint,
  buildAnimalBuyRows,
  buildAnimalRows,
  buildMachineRows,
  canBarnAction,
  contextActionText,
  countInInventory,
  denialScopeOf,
  denialText,
  facedContextAction,
  isShippable,
  machineCountdownText,
  moveBarnSelection,
  pressSleep,
  selectedStackActions,
  shippingBinModel,
  shippingRowText,
  SLEEP_CONFIRM_MS,
  sleepArmed,
} from '@game/features/day-loop';
import { createSim, DEFAULT_MODULES, testFarmMap, type SimFixture } from '../sim/harness';

const KEYS = { ship: 'X', eat: 'G' };

async function makeFixture(): Promise<SimFixture> {
  return createSim({ modules: [...DEFAULT_MODULES, craftingSim, animalsSim, machinesSim] });
}

describe('day-loop keymap wiring', () => {
  it('prints the real binding for every new day-loop action', () => {
    expect(keyForAction('ship')).toBe('x');
    expect(keyForAction('eat')).toBe('g');
    expect(keyForAction('sleep')).toBe('r');
    expect(keyForAction('barn')).toBe('b');
    // The keymap stores normalized lowercase keys for matching; the UI prints
    // the glyph, and only ever through keyGlyph.
    expect(keyGlyph('ship')).toBe('X');
    expect(keyGlyph('eat')).toBe('G');
    expect(keyGlyph('sleep')).toBe('R');
    expect(keyGlyph('barn')).toBe('B');
    expect(keyGlyph('interact')).toBe('Space');
  });

  it('keeps the pre-existing bindings the loop sits on top of', () => {
    for (const action of ['move', 'interact', 'crafting', 'shop', 'journal', 'settings'] as const) {
      expect(keyForAction(action), action).not.toBeNull();
    }
  });

  it('X translates to shipping:insert for the selected slot and needs a slot', () => {
    expect(actionToSim({ type: 'ship' }, 3)).toEqual({ type: 'shipping:insert', payload: { slot: 3 } });
    expect(actionToSim({ type: 'ship' })).toBeNull();
  });

  it('G translates to player:eat for the selected slot and needs a slot', () => {
    expect(actionToSim({ type: 'eat' }, 0)).toEqual({ type: 'player:eat', payload: { slot: 0 } });
    expect(actionToSim({ type: 'eat' })).toBeNull();
  });

  it('the loop-only keys are UI intents, never raw sim actions', () => {
    expect(actionToSim({ type: 'sleep' }, 1)).toBeNull();
    expect(actionToSim({ type: 'barn' }, 1)).toBeNull();
  });

  it('no key is bound twice, so the new keys cannot shadow an old action', () => {
    const seen = new Map<string, string>();
    for (const binding of DEFAULT_KEYMAP) {
      for (const key of binding.keys) {
        const owner = seen.get(key);
        expect(owner, `${key} is bound to both ${owner} and ${binding.action.type}`).toBeUndefined();
        seen.set(key, binding.action.type);
      }
    }
  });

  it('reaches the new actions by the keys the player presses', () => {
    expect(findBinding('x')?.action).toEqual({ type: 'ship' });
    expect(findBinding('g')?.action).toEqual({ type: 'eat' });
    expect(findBinding('r')?.action).toEqual({ type: 'sleep' });
    expect(findBinding('b')?.action).toEqual({ type: 'barn' });
  });

  it('the loop keys are single presses, not hold-repeat', () => {
    const repeating = DEFAULT_KEYMAP.filter((b) => b.holdRepeat).map((b) => b.action.type);
    for (const action of ['ship', 'eat', 'sleep', 'barn', 'use'] as const) {
      expect(repeating, action).not.toContain(action);
    }
  });

  it('binds the contextual use key to a key nothing else claimed', () => {
    expect(keyForAction('use')).toBe('q');
    expect(keyGlyph('use')).toBe('Q');
    expect(findBinding('q')?.action).toEqual({ type: 'use' });
  });

  it('Q resolves to one context action on the faced tile, not one key per object', () => {
    const tile = { mapId: 'farm', x: 5, y: 5 };
    expect(actionToSim({ type: 'use' }, 0, tile)).toEqual({ type: 'machines:interact', payload: { tile } });
  });

  it('Q needs a tile, so it can never dispatch against a stale position', () => {
    expect(actionToSim({ type: 'use' }, 0)).toBeNull();
  });
});

describe('contextual use on the faced tile', () => {
  async function withMachine(data: Record<string, unknown>): Promise<SimFixture> {
    const fx = await makeFixture();
    fx.store.state.maps['farm']!.placed[tileKey(5, 5)] = {
      id: 'machine:mayonnaise-machine',
      x: 5,
      y: 5,
      data,
    };
    return fx;
  }

  /** Stand the player just below the machine at 5,5, facing up at it. */
  function faceMachineFromBelow(fx: SimFixture): void {
    fx.store.state.player.position = { mapId: 'farm', x: 5, y: 6 };
    fx.store.state.player.facing = 'up';
  }

  it('offers nothing over bare ground, so the bar never promises a refusal', async () => {
    const fx = await makeFixture();
    expect(facedContextAction(fx.state, fx.content, { use: 'Q' })).toBeNull();
  });

  it('offers nothing for a non-machine object like the shipping bin', async () => {
    const fx = await makeFixture();
    fx.store.state.maps['farm']!.placed[tileKey(5, 5)] = { id: 'shipping-bin', x: 5, y: 5 };
    faceMachineFromBelow(fx);
    expect(facedContextAction(fx.state, fx.content, { use: 'Q' })).toBeNull();
  });

  it('reads an idle machine as a load', async () => {
    const fx = await withMachine({ loaded: 0, remainingTicks: 0 });
    faceMachineFromBelow(fx);
    const action = facedContextAction(fx.state, fx.content, { use: 'Q' })!;
    expect(action.kind).toBe('load');
    expect(action.key).toBe('Q');
    expect(action.name).toBe('Mayonnaise Machine');
    expect(contextActionText(action)).toBe('Load Mayonnaise Machine');
  });

  it('reads a finished machine as a collect', async () => {
    const fx = await withMachine({ loaded: 1, remainingTicks: 0 });
    faceMachineFromBelow(fx);
    const action = facedContextAction(fx.state, fx.content, { use: 'Q' })!;
    expect(action.kind).toBe('collect');
    expect(contextActionText(action)).toBe('Collect from Mayonnaise Machine');
  });

  it('reads a running machine as busy, with the countdown on the line', async () => {
    const fx = await withMachine({ loaded: 1, remainingTicks: 5 });
    faceMachineFromBelow(fx);
    const action = facedContextAction(fx.state, fx.content, { use: 'Q' })!;
    expect(action.kind).toBe('busy');
    expect(action.detail).toBe('50m');
    expect(contextActionText(action)).toBe('Q Mayonnaise Machine is working — 50m left');
  });

  it('follows the player around: facing away from the machine offers nothing', async () => {
    const fx = await withMachine({ loaded: 0, remainingTicks: 0 });
    faceMachineFromBelow(fx);
    fx.store.state.player.facing = 'down';
    expect(facedContextAction(fx.state, fx.content, { use: 'Q' })).toBeNull();
  });

  it('does not offer a machine on another map', async () => {
    const fx = await withMachine({ loaded: 0, remainingTicks: 0 });
    faceMachineFromBelow(fx);
    fx.store.state.player.position = { mapId: 'village', x: 5, y: 6 };
    expect(facedContextAction(fx.state, fx.content, { use: 'Q' })).toBeNull();
  });
});

describe('barn row keyboard routing', () => {
  it('maps the number keys onto the three barn actions', () => {
    expect(barnActionForKey('1')).toBe('feed');
    expect(barnActionForKey('2')).toBe('pet');
    expect(barnActionForKey('3')).toBe('collect');
  });

  it('ignores keys that are not barn actions', () => {
    for (const key of ['0', '4', '9', 'q', '', 'x']) {
      expect(barnActionForKey(key), key).toBeNull();
    }
  });

  it('prints the key beside every button, including the unavailable ones', async () => {
    const fx = await makeFixture();
    const rows = buildAnimalRows(fx.state, fx.content);
    expect(rows).toEqual([]);
    // A row is needed for a hint, so buy one through the sim the panel uses.
    fx.store.dispatch({ type: 'animals:buy', payload: { species: 'chicken', qty: 1 } });
    const row = buildAnimalRows(fx.state, fx.content)[0]!;
    expect(barnRowHint(row, BARN_ACTION_LABELS)).toBe('1 Feed · 2 Pet · 3 Collect');
  });

  it('wraps the highlighted row at both ends', () => {
    expect(moveBarnSelection(0, 1, 3)).toBe(1);
    expect(moveBarnSelection(2, 1, 3)).toBe(0);
    expect(moveBarnSelection(0, -1, 3)).toBe(2);
    expect(moveBarnSelection(1, -1, 3)).toBe(0);
  });

  it('has no selection to move in an empty barn', () => {
    expect(moveBarnSelection(0, 1, 0)).toBe(0);
    expect(moveBarnSelection(3, -1, 0)).toBe(0);
  });

  it('only enables a key when the sim would accept the action', async () => {
    const fx = await makeFixture();
    fx.store.dispatch({ type: 'animals:buy', payload: { species: 'chicken', qty: 1 } });
    let row = buildAnimalRows(fx.state, fx.content)[0]!;
    // No hay in the bag, so feed is off; pet and collect are on.
    expect(canBarnAction(row, 'feed')).toBe(false);
    expect(canBarnAction(row, 'pet')).toBe(true);
    expect(canBarnAction(row, 'collect')).toBe(false);

    fx.store.dispatch({ type: 'animals:pet', payload: { animalId: row.id } });
    row = buildAnimalRows(fx.state, fx.content)[0]!;
    expect(canBarnAction(row, 'pet')).toBe(false);
  });
});

describe('sleep confirmation', () => {
  it('the first press only arms the second one', () => {
    const first = pressSleep(null, 1000);
    expect(first.press).toBe('armed');
    expect(first.armedAt).toBe(1000);
    expect(sleepArmed(first.armedAt, 1000)).toBe(true);
  });

  it('a second press inside the window ends the day', () => {
    const armed = pressSleep(null, 1000);
    const second = pressSleep(armed.armedAt, 1000 + SLEEP_CONFIRM_MS - 1);
    expect(second.press).toBe('slept');
    expect(second.armedAt).toBeNull();
  });

  it('an expired press re-arms instead of sleeping', () => {
    const armed = pressSleep(null, 1000);
    const late = pressSleep(armed.armedAt, 1000 + SLEEP_CONFIRM_MS + 1);
    expect(late.press).toBe('expired');
    expect(late.armedAt).toBe(1000 + SLEEP_CONFIRM_MS + 1);
    expect(sleepArmed(late.armedAt, 1000 + SLEEP_CONFIRM_MS + 2)).toBe(true);
  });

  it('slept leaves nothing armed, so the next press arms again', () => {
    const after = pressSleep(pressSleep(null, 0).armedAt, 10);
    expect(after.press).toBe('slept');
    expect(pressSleep(after.armedAt, 20).press).toBe('armed');
  });
});

describe('selected stack actions', () => {
  it('offers ship and eat for cooked food, which is both shippable and edible', async () => {
    const fx = await makeFixture();
    const slot = fx.holdItem('fried-egg', 2);
    const row = selectedStackActions(fx.state, fx.content, KEYS);
    expect(row).not.toBeNull();
    expect(row!.slot).toBe(slot);
    expect(row!.name).toBe('Fried Egg');
    expect(row!.qty).toBe(2);
    expect(row!.actions.map((a) => a.kind).sort()).toEqual(['eat', 'ship']);
    expect(row!.actions.find((a) => a.kind === 'ship')?.key).toBe('X');
    expect(row!.actions.find((a) => a.kind === 'eat')?.key).toBe('G');
  });

  it('offers ship but not eat for a raw egg, which is not a food', async () => {
    const fx = await makeFixture();
    fx.holdItem('egg', 2);
    const row = selectedStackActions(fx.state, fx.content, KEYS);
    expect(row!.actions.map((a) => a.kind)).toEqual(['ship']);
  });

  it('offers no ship key for a tool the sim would refuse', async () => {
    const fx = await makeFixture();
    fx.holdItem('hoe', 1);
    const row = selectedStackActions(fx.state, fx.content, KEYS);
    expect(row).not.toBeNull();
    expect(row!.actions).toEqual([]);
  });

  it('offers ship but not eat for wood', async () => {
    const fx = await makeFixture();
    fx.holdItem('wood', 5);
    const row = selectedStackActions(fx.state, fx.content, KEYS);
    expect(row!.actions.map((a) => a.kind)).toEqual(['ship']);
  });

  it('offers nothing at all for an empty hand', async () => {
    const fx = await makeFixture();
    fx.holdHands();
    expect(selectedStackActions(fx.state, fx.content, KEYS)).toBeNull();
  });

  it('classifies shippability from the item table, crops included', async () => {
    const fx = await makeFixture();
    expect(isShippable(fx.content, 'egg')).toBe(true);
    expect(isShippable(fx.content, 'parsnip')).toBe(true);
    expect(isShippable(fx.content, 'hoe')).toBe(false);
    expect(isShippable(fx.content, 'no-such-item')).toBe(false);
  });
});

describe('shipping bin panel', () => {
  it('starts empty and reflects the box after a real insert', async () => {
    const fx = await makeFixture();
    expect(shippingBinModel(fx.state, fx.content)).toEqual({ rows: [], totalQty: 0, totalGold: 0 });
    const slot = fx.holdItem('egg', 4);
    fx.insertSlot(slot);
    const model = shippingBinModel(fx.state, fx.content);
    expect(model.totalQty).toBe(4);
    expect(model.rows).toHaveLength(1);
    expect(model.rows[0]!.itemId).toBe('egg');
    expect(model.totalGold).toBeGreaterThan(0);
  });

  it('prices the bin with the same numbers the payout uses', async () => {
    const fx = await makeFixture();
    const slot = fx.holdItem('egg', 4);
    fx.insertSlot(slot);
    const model = shippingBinModel(fx.state, fx.content);
    const before = fx.money();
    fx.sleepWithWeather(fx.state.world.weather);
    expect(fx.money() - before).toBe(model.totalGold);
  });

  it('renders a row with its name, count and gold', async () => {
    const fx = await makeFixture();
    const slot = fx.holdItem('egg', 2);
    fx.insertSlot(slot);
    const row = shippingBinModel(fx.state, fx.content).rows[0]!;
    expect(shippingRowText(row)).toBe(`Egg x2 · ${row.gold}g`);
  });
});

describe('barn panel', () => {
  it('is empty on a fresh farm and lists a buy row per authored species', async () => {
    const fx = await makeFixture();
    expect(buildAnimalRows(fx.state, fx.content)).toEqual([]);
    const buys = buildAnimalBuyRows(fx.state, fx.content);
    expect(buys).toHaveLength(fx.content.animals.size);
    expect(buys.map((b) => b.price)).toEqual([...buys.map((b) => b.price)].sort((a, b) => a - b));
  });

  it('buying an animal adds a row that starts unfed and unpetted', async () => {
    const fx = await makeFixture();
    fx.state.player.money = 5000;
    fx.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    const rows = buildAnimalRows(fx.state, fx.content);
    expect(rows).toHaveLength(1);
    const row = rows[0]!;
    expect(row.name).toBe('Chicken');
    expect(row.fed).toBe(false);
    expect(row.petted).toBe(false);
    expect(row.canPet).toBe(true);
    expect(row.productReady).toBe(false);
    expect(row.canCollect).toBe(false);
  });

  it('feed and pet buttons follow the sim: both flip off once done today', async () => {
    const fx = await makeFixture();
    fx.state.player.money = 5000;
    fx.giveItem('hay', 5);
    fx.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    const id = buildAnimalRows(fx.state, fx.content)[0]!.id;
    fx.dispatch('animals:feed', { animalId: id });
    fx.dispatch('animals:pet', { animalId: id });
    const row = buildAnimalRows(fx.state, fx.content)[0]!;
    expect(row.fed).toBe(true);
    expect(row.petted).toBe(true);
    expect(row.canFeed).toBe(false);
    expect(row.canPet).toBe(false);
    expect(countInInventory(fx.state, 'hay')).toBe(4);
  });

  it('cannot feed without feed in the bag, and the row says so', async () => {
    const fx = await makeFixture();
    fx.state.player.money = 5000;
    fx.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    const row = buildAnimalRows(fx.state, fx.content)[0]!;
    expect(row.feedHave).toBe(0);
    expect(row.canFeed).toBe(false);
    // Hearts gate the product before the feed question is even relevant.
    expect(animalProductText(row, fx.state.world.dayCount)).toContain(String(MIN_HEARTS_TO_PRODUCE));
    fx.giveItem('hay', 2);
    expect(buildAnimalRows(fx.state, fx.content)[0]!.canFeed).toBe(true);
  });

  it('collect is offered only once a product is ready, and hands the item over', async () => {
    const fx = await makeFixture();
    fx.state.player.money = 5000;
    fx.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    const id = buildAnimalRows(fx.state, fx.content)[0]!.id;
    // Not ready yet: the sim refuses and the row must say why.
    fx.dispatch('animals:collect', { animalId: id });
    expect(countInInventory(fx.state, 'egg')).toBe(0);
    expect(animalProductText(buildAnimalRows(fx.state, fx.content)[0]!, fx.state.world.dayCount)).toMatch(
      new RegExp(String(MIN_HEARTS_TO_PRODUCE)),
    );
    // Push the animal to the point where it has produced.
    const ext = fx.state.extensions['animals'] as { animals: Array<Record<string, unknown>> };
    const animal = ext.animals[0]!;
    animal['hearts'] = MIN_HEARTS_TO_PRODUCE;
    animal['happy'] = 100;
    animal['nextProductAt'] = fx.state.world.dayCount;
    animal['productReady'] = true;
    const ready = buildAnimalRows(fx.state, fx.content)[0]!;
    expect(ready.productReady).toBe(true);
    expect(ready.canCollect).toBe(true);
    expect(animalProductText(ready, fx.state.world.dayCount)).toMatch(/ready to collect/);
    fx.dispatch('animals:collect', { animalId: id });
    expect(countInInventory(fx.state, 'egg')).toBe(1);
    expect(buildAnimalRows(fx.state, fx.content)[0]!.canCollect).toBe(false);
  });

  it('names the day a future product lands on, and says nothing about days past', async () => {
    const fx = await makeFixture();
    fx.state.player.money = 5000;
    fx.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    const ext = fx.state.extensions['animals'] as { animals: Array<Record<string, unknown>> };
    ext.animals[0]!['hearts'] = MIN_HEARTS_TO_PRODUCE;
    ext.animals[0]!['nextProductAt'] = fx.state.world.dayCount + 3;
    const row = buildAnimalRows(fx.state, fx.content)[0]!;
    expect(animalProductText(row, fx.state.world.dayCount)).toContain(String(fx.state.world.dayCount + 3));
    expect(animalProductText(row, fx.state.world.dayCount + 9)).not.toContain(
      String(fx.state.world.dayCount + 3),
    );
  });

  it('flags affordability from the player gold, and buying spends it', async () => {
    const fx = await makeFixture();
    fx.state.player.money = 0;
    expect(buildAnimalBuyRows(fx.state, fx.content).every((b) => !b.affordable)).toBe(true);
    fx.state.player.money = 5000;
    const cheapest = buildAnimalBuyRows(fx.state, fx.content)[0]!;
    expect(cheapest.affordable).toBe(true);
    fx.dispatch('animals:buy', { species: cheapest.species, qty: 1 });
    expect(fx.money()).toBe(5000 - cheapest.price);
  });
});

describe('machine panel', () => {
  it('has no rows until a machine is placed', async () => {
    const fx = await makeFixture();
    expect(buildMachineRows(fx.state, fx.content)).toEqual([]);
  });

  it('reports empty, then busy with a countdown, then ready', async () => {
    const fx = await makeFixture();
    const map = fx.store.state.maps['farm']!;
    map.placed[tileKey(5, 5)] = { id: 'machine:mayonnaise-machine', x: 5, y: 5, data: { loaded: 0 } };
    const empty = buildMachineRows(fx.state, fx.content);
    expect(empty).toHaveLength(1);
    expect(empty[0]!.machineId).toBe('mayonnaise-machine');
    expect(empty[0]!.status).toBe('empty');
    expect(empty[0]!.remainingText).toBe('');

    map.placed[tileKey(5, 5)]!.data = { loaded: 1, remainingTicks: 5, itemId: 'egg' };
    const busy = buildMachineRows(fx.state, fx.content)[0]!;
    expect(busy.status).toBe('busy');
    expect(busy.remainingMinutes).toBe(50);
    expect(busy.remainingText).toBe('50m');
    expect(machineCountdownText(busy)).toBe('50m left');

    map.placed[tileKey(5, 5)]!.data = { loaded: 1, remainingTicks: 0, itemId: 'egg' };
    const ready = buildMachineRows(fx.state, fx.content)[0]!;
    expect(ready.status).toBe('ready');
    expect(ready.remainingText).toBe('');
    expect(machineCountdownText(ready)).toBe('');
  });

  it('ignores placed objects that are not machines', async () => {
    const fx = await makeFixture();
    fx.store.state.maps['farm'] = testFarmMap();
    const rows = buildMachineRows(fx.state, fx.content);
    expect(rows.every((r) => r.machineId !== 'shipping-bin')).toBe(true);
  });
});

describe('denial sentences', () => {
  it('routes every refusal event to a table', () => {
    expect(denialScopeOf('shipping:denied')).toBe('shipping');
    expect(denialScopeOf('crafting:denied')).toBe('crafting');
    expect(denialScopeOf('animals:denied')).toBe('animals');
    expect(denialScopeOf('machines:denied')).toBe('machines');
    expect(denialScopeOf('farming:blocked')).toBe('farming');
    expect(denialScopeOf('inventory:full')).toBe('inventory');
    expect(denialScopeOf('day:started')).toBeNull();
  });

  it('never leaks a machine code to the player', () => {
    for (const scope of ['shipping', 'crafting', 'animals', 'machines', 'farming', 'inventory']) {
      for (const reason of ['no-slot', 'not-ready', 'no-feed', 'busy', 'no-gold', 'made-up-reason']) {
        const text = denialText(scope, reason, { name: 'Egg', gold: 400, key: 'Space', time: '20m' });
        expect(text.length, `${scope}/${reason}`).toBeGreaterThan(0);
        expect(text, `${scope}/${reason}`).not.toContain(reason);
        expect(text, `${scope}/${reason}`).not.toContain('{');
      }
    }
  });

  it('names the thing the player was trying to act on', () => {
    expect(denialText('animals', 'already-fed', { name: 'Chicken' })).toContain('Chicken');
    expect(denialText('animals', 'no-gold', { gold: 400 })).toContain('400');
    expect(denialText('machines', 'busy', { time: '20m' })).toContain('20m');
  });

  it('falls back for an unknown scope instead of printing nothing', () => {
    expect(denialText('nonsense', 'whatever')).toBe(MESSAGES.denied.unknown);
    expect(denialText('shipping', undefined)).toBe(MESSAGES.denied.shipping.unknown);
  });
});
