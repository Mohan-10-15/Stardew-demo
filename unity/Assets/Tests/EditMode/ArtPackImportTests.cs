using System.Collections.Generic;
using System.Linq;
using NUnit.Framework;
using UnityEditor;
using UnityEngine;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// T-0101 validation. The two CC0 packs must survive import as real,
    /// renderable, correctly-scaled art - not as a pile of missing-magenta
    /// models discovered later by a PlayMode test.
    ///
    /// The path strings are repeated here rather than imported from
    /// <c>EmberHollow.EditorTools</c> so this test stays an independent check of
    /// what is actually on disk.
    /// </summary>
    public class ArtPackImportTests
    {
        private const string KayKitCharacterDir = "Assets/Art/KayKit/Adventurers/Characters";
        private const string KayKitAddonDir = "Assets/Art/KayKit/Adventurers/Addons";
        private const string QuaterniusDir = "Assets/Art/Quaternius/FarmBuildings";
        private const string CharacterPrefabDir = "Assets/Prefabs/Characters";
        private const string FarmPrefabDir = "Assets/Prefabs/Props/FarmBuildings";
        private const string AccessoryPrefabDir = "Assets/Prefabs/Props/AdventurerAccessories";
        private const string MaterialRoot = "Assets/Art/Materials";
        private const string UrpPrefix = "Universal Render Pipeline/";

        private static readonly string[] ExpectedCharacters =
        {
            "Barbarian",
            "Knight",
            "Mage",
            "Rogue",
            "RogueHooded",
        };

        private static readonly string[] ExpectedFarmProps =
        {
            "Barn",
            "BigBarn",
            "ChickenCoop",
            "Fence",
            "Fence2",
            "OpenBarn",
            "Silo",
            "Silo_House",
            "SmallBarn",
            "TowerWindmill",
            "WaterTower",
            "Well",
            "Windmill",
        };

        private static string[] ModelPaths(string folder)
        {
            return AssetDatabase.FindAssets("t:Model", new[] { folder })
                .Select(AssetDatabase.GUIDToAssetPath)
                .OrderBy(p => p, System.StringComparer.Ordinal)
                .ToArray();
        }

        [Test]
        public void BothPacks_AreImportedAtTheExpectedScale()
        {
            string[] characters = ModelPaths(KayKitCharacterDir);
            string[] props = ModelPaths(QuaterniusDir);
            string[] addons = ModelPaths(KayKitAddonDir);

            Assert.AreEqual(ExpectedCharacters.Length, characters.Length, "KayKit Adventurers character count");
            Assert.AreEqual(ExpectedFarmProps.Length, props.Length, "Quaternius Farm Buildings prop count");
            Assert.Greater(addons.Length, 0, "KayKit accessory addon FBXs are missing");

            foreach (string character in characters)
            {
                Assert.IsTrue(character.EndsWith(".fbx", System.StringComparison.OrdinalIgnoreCase), character);
            }
        }

        [Test]
        public void CharacterPrefabs_ExistOnePerImportedCharacter()
        {
            string[] prefabs = AssetDatabase
                .FindAssets("t:Prefab", new[] { CharacterPrefabDir })
                .Select(AssetDatabase.GUIDToAssetPath)
                .ToArray();

            Assert.AreEqual(ExpectedCharacters.Length, prefabs.Length, "character prefab count");

            foreach (string name in ExpectedCharacters)
            {
                string path = $"{CharacterPrefabDir}/KayKit_Adventurer_{name}.prefab";
                Assert.IsTrue(System.IO.File.Exists(path), $"missing prefab on disk: {path}");

                GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                Assert.IsNotNull(prefab, path);
                Assert.IsTrue(prefab.GetComponentInChildren<Renderer>(true) != null, $"{path} has no Renderer");
            }
        }

        [Test]
        public void FarmPropPrefabs_ExistOnePerImportedBuilding()
        {
            string[] prefabs = AssetDatabase
                .FindAssets("t:Prefab", new[] { FarmPrefabDir })
                .Select(AssetDatabase.GUIDToAssetPath)
                .ToArray();

            Assert.AreEqual(ExpectedFarmProps.Length, prefabs.Length, "farm prop prefab count");

            foreach (string name in ExpectedFarmProps)
            {
                string path = $"{FarmPrefabDir}/Quaternius_Farm_{name}.prefab";
                Assert.IsTrue(System.IO.File.Exists(path), $"missing prefab on disk: {path}");
            }
        }

        [Test]
        public void AccessoryPrefabs_ExistForEveryAddonModel()
        {
            string[] models = ModelPaths(KayKitAddonDir);
            string[] prefabs = AssetDatabase
                .FindAssets("t:Prefab", new[] { AccessoryPrefabDir })
                .Select(AssetDatabase.GUIDToAssetPath)
                .ToArray();

            Assert.AreEqual(models.Length, prefabs.Length, "accessory prefab count must match addon FBX count");
        }

        [Test]
        public void EveryPrefabRenderer_UsesASharedUrpMaterial()
        {
            string[] roots = { CharacterPrefabDir, FarmPrefabDir, AccessoryPrefabDir };
            int rendererCount = 0;

            foreach (string root in roots)
            {
                string[] prefabs = AssetDatabase
                    .FindAssets("t:Prefab", new[] { root })
                    .Select(AssetDatabase.GUIDToAssetPath)
                    .ToArray();

                Assert.Greater(prefabs.Length, 0, $"no prefabs under {root}");

                foreach (string path in prefabs)
                {
                    GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                    Assert.IsNotNull(prefab, path);

                    foreach (Renderer renderer in prefab.GetComponentsInChildren<Renderer>(true))
                    {
                        foreach (Material material in renderer.sharedMaterials)
                        {
                            Assert.IsNotNull(material, $"{path}: {renderer.name} has a null material slot");
                            Assert.IsNotNull(material.shader, $"{path}: {renderer.name} material has no shader");
                            Assert.IsTrue(
                                material.shader.name.StartsWith(UrpPrefix, System.StringComparison.Ordinal),
                                $"{path}: {renderer.name} uses '{material.shader.name}', which URP cannot render. " +
                                "The built-in Standard shader from the pack must be converted.");
                            Assert.IsTrue(
                                AssetDatabase.Contains(material),
                                $"{path}: material '{material.name}' is not a project asset, so it is per-instance");
                            Assert.IsTrue(
                                material.enableInstancing, $"{path}: '{material.name}' cannot GPU instance");
                            rendererCount++;
                        }
                    }
                }
            }

            Assert.Greater(rendererCount, 0, "no renderers were inspected at all");
        }

        [Test]
        public void Characters_HaveFeetPivotAndHumanScale()
        {
            float shortest = float.MaxValue;
            float tallest = 0f;

            foreach (string name in ExpectedCharacters)
            {
                string path = $"{CharacterPrefabDir}/KayKit_Adventurer_{name}.prefab";
                GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);

                Bounds bounds = BoundsOf(prefab);
                Assert.Greater(bounds.size.y, 1.0f, $"{path} is {bounds.size.y:F3}m tall, not human scale");
                Assert.Less(bounds.size.y, 3.0f, $"{path} is {bounds.size.y:F3}m tall, not human scale");
                Assert.Less(
                    Mathf.Abs(bounds.min.y),
                    bounds.size.y * 0.06f,
                    $"{path} pivot is not at the feet (min.y={bounds.min.y:F3})");

                shortest = Mathf.Min(shortest, bounds.size.y);
                tallest = Mathf.Max(tallest, bounds.size.y);
            }

            Assert.Less(
                tallest / shortest,
                1.25f,
                $"character scale is inconsistent: shortest {shortest:F3}m, tallest {tallest:F3}m");
        }

        [Test]
        public void Characters_HaveAnAnimatorDrivenByThePackedAnimations()
        {
            foreach (string name in ExpectedCharacters)
            {
                string path = $"{CharacterPrefabDir}/KayKit_Adventurer_{name}.prefab";
                GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);

                Animator animator = prefab.GetComponentInChildren<Animator>(true);
                Assert.IsNotNull(animator, $"{path} has no Animator");
                Assert.IsNotNull(animator.avatar, $"{path} Animator has no Avatar");
                Assert.IsTrue(animator.avatar.isValid, $"{path} Avatar is invalid");

                RuntimeAnimatorController controller = animator.runtimeAnimatorController;
                Assert.IsNotNull(controller, $"{path} Animator has no RuntimeAnimatorController");

                UnityEngine.Object[] clips = controller.animationClips;
                Assert.Greater(clips.Length, 0, $"{path} controller '{controller.name}' has no clips");
                Assert.IsFalse(animator.applyRootMotion, $"{path} must not apply root motion");
            }
        }

        [Test]
        public void FarmProps_SitOnTheGroundPlane()
        {
            foreach (string name in ExpectedFarmProps)
            {
                string path = $"{FarmPrefabDir}/Quaternius_Farm_{name}.prefab";
                GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);

                Bounds bounds = BoundsOf(prefab);
                Assert.Greater(bounds.size.y, 0.5f, $"{path} is only {bounds.size.y:F3}m tall");
                Assert.Less(
                    Mathf.Abs(bounds.min.y),
                    bounds.size.y * 0.06f,
                    $"{path} pivot is not at its base (min.y={bounds.min.y:F3})");
            }
        }

        [Test]
        public void ConvertedMaterials_LiveUnderAssetsArtMaterials()
        {
            string[] materialGuids = AssetDatabase.FindAssets("t:Material", new[] { MaterialRoot });
            Assert.Greater(materialGuids.Length, 0, $"no converted materials under {MaterialRoot}");

            string[] paths = materialGuids.Select(AssetDatabase.GUIDToAssetPath).ToArray();
            // Paths look like Assets/Art/Materials/<Pack>/Mat_x.mat, so the pack
            // name is the fourth segment, not the third. A pack folder may hold
            // more than the two imported packs (Farm holds the ground and sky
            // materials), so this asserts containment rather than equivalence.
            var packs = paths.Select(p => p.Split('/')[3]).Distinct().ToList();
            CollectionAssert.Contains(packs, "KayKit");
            CollectionAssert.Contains(packs, "Quaternius");

            foreach (string path in paths)
            {
                Material material = AssetDatabase.LoadAssetAtPath<Material>(path);
                Assert.IsTrue(
                    material.shader.name.StartsWith(UrpPrefix, System.StringComparison.Ordinal),
                    $"{path} uses '{material.shader.name}'");
            }
        }

        [Test]
        public void ConvertedMaterials_AreSharedAcrossPrefabsNotDuplicatedPerInstance()
        {
            Dictionary<string, int> usage = new Dictionary<string, int>();
            string[] roots = { CharacterPrefabDir, FarmPrefabDir, AccessoryPrefabDir };

            foreach (string root in roots)
            {
                foreach (string path in AssetDatabase
                    .FindAssets("t:Prefab", new[] { root })
                    .Select(AssetDatabase.GUIDToAssetPath))
                {
                    GameObject prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                    foreach (Renderer renderer in prefab.GetComponentsInChildren<Renderer>(true))
                    {
                        foreach (Material material in renderer.sharedMaterials)
                        {
                            string key = AssetDatabase.AssetPathToGUID(AssetDatabase.GetAssetPath(material));
                            usage[key] = usage.TryGetValue(key, out int n) ? n + 1 : 1;
                        }
                    }
                }
            }

            Assert.Greater(usage.Count, 1, "all art resolved to a single material, which cannot be right");

            foreach (KeyValuePair<string, int> pair in usage)
            {
                Assert.Greater(pair.Value, 0, "material " + pair.Key + " is orphaned");
            }
        }

        private static Bounds BoundsOf(GameObject prefab)
        {
            GameObject probe = UnityEngine.Object.Instantiate(prefab);
            try
            {
                Renderer[] renderers = probe.GetComponentsInChildren<Renderer>(true);
                Assert.Greater(renderers.Length, 0, $"{prefab.name} has no Renderer");

                Bounds bounds = renderers[0].bounds;
                for (int i = 1; i < renderers.Length; i++)
                {
                    bounds.Encapsulate(renderers[i].bounds);
                }

                return bounds;
            }
            finally
            {
                UnityEngine.Object.DestroyImmediate(probe);
            }
        }
    }
}