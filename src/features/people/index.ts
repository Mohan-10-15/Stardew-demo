import { registerFeature } from '../../core/registry';
import { peopleSim } from './sim/PeopleSim';
import { peopleUi } from './ui/dialogue';
import { journalUi } from './ui/journal';

registerFeature(peopleSim);
registerFeature(peopleUi);
registerFeature(journalUi);

export {
  advancePeople,
  ensurePeopleExt,
  giftToNpc,
  initializePeople,
  npcAtFront,
  peopleFeature,
  peopleSim,
  peopleTickReducer,
  readPeopleExt,
  scheduleContextFromState,
  talkToNpc,
  tickPeople,
  writePeopleExt,
} from './sim/PeopleSim';
export { createDialogueUi, peopleUi } from './ui/dialogue';
export { createJournalUi, journalUi } from './ui/journal';
export * from './sim/schedule';
export * from './sim/dialogue';
export * from './sim/friendship';
export * from './sim/quests';
export * from './sim/events';
