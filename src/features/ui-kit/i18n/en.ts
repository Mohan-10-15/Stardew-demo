/**
 * English UI strings (M1, WORKER-3 lane). Every display string rendered by the
 * ui-kit and the HUD must live here — components never hardcode display text.
 * The tables are data so localization / remapping land without a refactor.
 */

export const en = {
  hud: {
    date: {
      format: '{season} {day}, Year {year}',
      aria: 'Date: {season} {day}, Year {year}',
    },
    clock: {
      aria: 'Time of day',
      hour12: false,
      padHour: true,
      am: 'AM',
      pm: 'PM',
    },
    weather: {
      aria: 'Weather: {weather}',
      label: {
        sun: 'Clear',
        rain: 'Rain',
        storm: 'Storm',
        snow: 'Snow',
        wind: 'Windy',
      },
    },
    money: {
      format: '{amount}g',
      aria: 'Gold: {amount}',
    },
    bar: {
      amount: '{current}/{max}',
    },
    energy: {
      label: 'Energy',
      aria: 'Energy {current} of {max}',
    },
    health: {
      label: 'Health',
      aria: 'Health {current} of {max}',
    },
    hotbar: {
      label: 'Hotbar',
      ariaSeparator: ' - ',
      slotAria: 'Hotbar slot {number}',
      emptySlot: 'Empty',
      itemAria: '{name}, x{qty}',
      qtyBadge: '{qty}',
      selectedAria: 'selected',
    },
    tooltip: {
      unknownItem: 'Unknown item',
      nameLine: '{name}',
      descLine: '{description}',
      qtyLine: 'Count: {qty}',
    },
    shipping: {
      aria: 'Shipping bin, {count} items',
      count: 'Items: {count}',
    },
  },
  uiKit: {
    dialog: {
      closeLabel: 'Close',
      closeAria: 'Close dialog',
    },
    tablist: {
      aria: 'Tabs',
    },
    slider: {
      aria: '{label}: {min} to {max}',
    },
  },
} as const;

export type Messages = typeof en;

export const MESSAGES: Messages = en;