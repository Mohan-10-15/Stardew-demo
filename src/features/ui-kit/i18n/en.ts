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
  summary: {
    title: 'Day complete',
    header: 'Day {dayCount} - {date}',
    weather: 'Weather: {weather}',
    goldEarned: 'Gold earned: {gold}',
    shipping: 'Shipping',
    harvest: 'Harvest',
    forage: 'Forage',
    experience: 'Experience',
    empty: 'Nothing to report.',
    row: '{name} x{qty}',
    rowGold: '{name} x{qty} - {gold}',
    xpRow: '{name} +{amount} XP',
    unknownItem: 'Unknown item',
    done: 'Done',
    skills: {
      farming: 'Farming',
      foraging: 'Foraging',
      mining: 'Mining',
      fishing: 'Fishing',
      combat: 'Combat',
    },
  },
  shop: {
    money: 'Gold: {gold}',
    buySection: 'Buy',
    sellSection: 'Sell',
    stockLeft: 'Left: {count}',
    stockUnlimited: 'Unlimited',
    buy: 'Buy',
    sell: 'Sell',
    sellEmpty: 'Nothing to sell.',
    noShop: 'No shop is open right now.',
    unknownItem: 'Unknown item',
    qtyBadge: 'x{qty}',
  },
  people: {
    dialogue: {
      continueLabel: 'Continue',
      closeLabel: 'Close',
      hint: 'Space or click to continue',
      counter: '{current} / {total}',
      empty: 'There is nothing to say right now.',
    },
  },
  journal: {
    title: 'Journal',
    tabQuests: 'Quests',
    tabPeople: 'People',
    tabSkills: 'Skills',
    available: 'Available',
    ready: 'Ready to turn in',
    done: 'Completed today',
    progress: '{current} / {total}',
    completed: 'Completed {days} day(s) ago',
    hearts: '{hearts} hearts',
    loves: 'Loves: {items}',
    skillLevel: '{skill} · Level {level}',
    xp: '{xp} xp',
  },
  crafting: {
    title: 'Crafting',
    sectionCrafts: 'Crafting',
    sectionCooking: 'Cooking',
    craft: 'Craft',
    qtyBadge: 'x{qty}',
    unlockAt: 'Unlocks at {skill} Level {level}',
    ingredients: '{ingredients}',
    foodStats: '+{energy} energy · +{health} health',
    buffLine: '{stat} +{amount} ({hours}h)',
    shortBadge: ' (have {have})',
    noRecipes: 'No recipes here yet.',
    unknownItem: 'Unknown item',
  },
} as const;

export type Messages = typeof en;

export const MESSAGES: Messages = en;