import { describe, expect, it } from 'vitest';
import { createSim } from './harness';
import { addStackToInventory, summarizeInventory } from '@game/features/inventory/sim/InventorySim';

interface SelectedEvent {
  slot: number;
}
interface MovedEvent {
  from: number;
  to: number;
}

describe('inventory + hotbar', () => {
  it('select-slot clamps into range and emits inventory:selected', async () => {
    const sim = await createSim();
    const selected = sim.capture<SelectedEvent>('inventory:selected');

    sim.selectSlot(-4);
    expect(sim.state.player.inventory.selected).toBe(0);
    sim.selectSlot(999);
    expect(sim.state.player.inventory.selected).toBe(11);
    sim.selectSlot(3);
    expect(sim.state.player.inventory.selected).toBe(3);
    expect(selected.map((s) => s.slot)).toEqual([0, 11, 3]);
  });

  it('inventory:move swaps two different stacks', async () => {
    const sim = await createSim();
    const moved = sim.capture<MovedEvent>('inventory:moved');

    sim.moveSlot(0, 1);
    expect(sim.state.player.inventory.slots[0]?.id).toBe('watering-can-t0');
    expect(sim.state.player.inventory.slots[1]?.id).toBe('hoe-t0');
    expect(moved).toHaveLength(1);
    expect(moved[0]).toEqual({ from: 0, to: 1 });
  });

  it('inventory:move merges identical stacks up to 999 and keeps the leftover', async () => {
    const sim = await createSim();
    const a = sim.giveItem('wood', 990);
    const b = sim.giveItem('wood', 15);
    expect(a).not.toBe(b);

    sim.moveSlot(b, a);
    expect(sim.state.player.inventory.slots[a]?.qty).toBe(999);
    expect(sim.state.player.inventory.slots[b]?.qty).toBe(6);
  });

  it('inventory:move moves a stack into an empty slot', async () => {
    const sim = await createSim();
    const slot = sim.giveItem('stone', 4);
    sim.moveSlot(slot, 11);
    expect(sim.state.player.inventory.slots[11]).toEqual({ id: 'stone', qty: 4, quality: 0 });
    expect(sim.state.player.inventory.slots[slot]).toBeNull();
  });

  it('inventory:move is null-safe and clamps out-of-range indices', async () => {
    const sim = await createSim();
    const moved = sim.capture<MovedEvent>('inventory:moved');

    sim.moveSlot(5, 5);
    expect(moved).toHaveLength(0);

    sim.moveSlot(5, 99);
    expect(sim.state.player.inventory.slots[11]?.id).toBe('fishing-rod-t0');
    expect(sim.state.player.inventory.slots[5]).toBeNull();

    sim.moveSlot(4, 4);
    sim.moveSlot(11, 0);
    expect(sim.state.player.inventory.slots[0]?.id).toBe('fishing-rod-t0');
    expect(sim.state.player.inventory.slots[11]?.id).toBe('hoe-t0');
    expect(moved).toHaveLength(2);
  });

  it('selecting the already-selected slot does not rewrite state', async () => {
    const sim = await createSim();
    const before = sim.state.player.inventory;
    sim.selectSlot(0);
    expect(sim.state.player.inventory).toBe(before);
  });

  it('addStackToInventory refuses when the bag is full', async () => {
    const sim = await createSim();
    for (let i = 0; i < 4; i++) sim.giveItem(`filler-${i}`, 1);
    expect(sim.state.player.inventory.slots.every((s) => s !== null)).toBe(true);

    const result = addStackToInventory(sim.state, { id: 'gold', qty: 1, quality: 0 });
    expect(result.added).toBe(false);
    expect(result.state).toBe(sim.state);
  });

  it('summarizeInventory merges stacks by id + quality', async () => {
    const sim = await createSim();
    sim.giveItem('wood', 10, 0);
    sim.giveItem('wood', 5, 0);
    sim.giveItem('wood', 2, 1);
    sim.giveItem('stone', 3, 0);

    const summary = summarizeInventory(sim.state);
    const woodNormal = summary.find((s) => s.id === 'wood' && s.quality === 0);
    const woodSilver = summary.find((s) => s.id === 'wood' && s.quality === 1);
    const stone = summary.find((s) => s.id === 'stone');

    expect(woodNormal?.qty).toBe(15);
    expect(woodSilver?.qty).toBe(2);
    expect(woodSilver?.quality).toBe(1);
    expect(stone?.qty).toBe(3);
    expect(summary.some((s) => s.id === 'parsnip-seed')).toBe(true);
    expect(summary.every((s) => s.qty > 0)).toBe(true);
  });
});
