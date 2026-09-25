import { registerFeature } from '../../core/registry';
import { animalsSim } from './sim/AnimalsSim';

registerFeature(animalsSim);

export {
  ANIMAL_CAP,
  ANIMALS_EXT_ID,
  animalsOf,
  animalsSim,
  buyAnimals,
  collectAnimal,
  feedAnimal,
  HAPPY_MAX,
  MIN_HEARTS_TO_PRODUCE,
  petAnimal,
  readAnimalsExt,
  rollAnimalQuality,
  rollAnimalsDay,
  writeAnimalsExt,
} from './sim/AnimalsSim';
export type { AnimalState, AnimalsExt } from './sim/AnimalsSim';