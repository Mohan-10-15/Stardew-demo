using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Animations;
using UnityEngine;

namespace EmberHollow.EditorTools
{
    /// <summary>
    /// Imports the two CC0 art packs into renderable, correctly-pivoted,
    /// consistently-scaled prefabs with shared URP materials and real animation.
    ///
    /// Everything is done here rather than in the Editor GUI because nobody on
    /// this team can open the Editor and click. Re-running this method is
    /// idempotent: it rebuilds the prefabs from the source FBX each time.
    ///
    /// Validate with:
    ///   Unity.exe -batchmode -quit -projectPath unity \
    ///     -executeMethod EmberHollow.EditorTools.ArtPackImporter.Build
    /// </summary>
    public static class ArtPackImporter
    {
        private const string CharacterDir = "Assets/Art/KayKit/Adventurers/Characters";
        private const string AddonDir = "Assets/Art/KayKit/Adventurers/Addons";
        private const string BuildingDir = "Assets/Art/Quaternius/FarmBuildings";

        private const string CharacterPrefabDir = "Assets/Prefabs/Characters";
        private const string FarmPrefabDir = "Assets/Prefabs/Props/FarmBuildings";
        private const string AccessoryPrefabDir = "Assets/Prefabs/Props/AdventurerAccessories";
        private const string ControllerDir = "Assets/Art/Animations";
        private const string KayKitMaterialDir = "Assets/Art/Materials/KayKit";
        private const string QuaterniusMaterialDir = "Assets/Art/Materials/Quaternius";

        private const string UrpShader = "Universal Render Pipeline/Lit";
        private const float TargetCharacterHeight = 1.8f;
        private const float PivotTolerance = 0.001f;

        public static void Build()
        {
            try
            {
                Run();
            }
            catch (Exception ex)
            {
                Debug.LogError($"[ArtPackImporter] Unhandled exception: {ex}");
                EditorApplication.Exit(2);
            }
        }

        private static void Run()
        {
            EnsureFolders();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

            var shader = Shader.Find(UrpShader);
            if (shader == null)
            {
                Debug.LogError($"[ArtPackImporter] URP shader '{UrpShader}' not found");
                EditorApplication.Exit(3);
                return;
            }

            var materialCache = new Dictionary<Material, Material>();
            var report = new List<string>();
            int characters = 0;
            int accessories = 0;
            int buildings = 0;

            characters = BuildCharacters(shader, materialCache, report);
            buildings = BuildProps(BuildingDir, FarmPrefabDir, "Quaternius_Farm_", QuaterniusMaterialDir,
                shader, materialCache, report, normalizeHeight: 0f);
            accessories = BuildProps(AddonDir, AccessoryPrefabDir, "KayKit_Accessory_", KayKitMaterialDir,
                shader, materialCache, report, normalizeHeight: 0f);

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

            Debug.Log("[ArtPackImporter] REPORT start");
            foreach (string line in report)
            {
                Debug.Log($"[ArtPackImporter] {line}");
            }

            Debug.Log(
                $"[ArtPackImporter] RESULT Succeeded Characters={characters} " +
                $"Buildings={buildings} Accessories={accessories} " +
                $"SharedMaterials={materialCache.Count}");

            EditorApplication.Exit(0);
        }

        private static int BuildCharacters(Shader shader, Dictionary<Material, Material> cache,
            List<string> report)
        {
            string[] models = FindModels(CharacterDir);
            if (models.Length == 0)
            {
                Debug.LogError($"[ArtPackImporter] No character models under {CharacterDir}");
                EditorApplication.Exit(4);
                return 0;
            }

            for (int i = 0; i < models.Length; i++)
            {
                string modelPath = models[i];
                ConfigureModelImporter(modelPath, ModelImporterAnimationType.Generic);

                var root = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
                var instance = (GameObject)UnityEngine.Object.Instantiate(root);
                string name = root.name;
                string prefabPath = $"{CharacterPrefabDir}/KayKit_Adventurer_{name}.prefab";

                AssignMaterials(instance, shader, cache);

                float scale = NormalizeHeight(instance, TargetCharacterHeight);
                SnapPivotToFeet(instance);
                AddAnimator(instance, name, modelPath);

                PrefabUtility.SaveAsPrefabAsset(instance, prefabPath);
                Bounds bounds = BoundsOf(instance);
                UnityEngine.Object.DestroyImmediate(instance);

                report.Add(
                    $"{prefabPath} | height={bounds.size.y:F3}m scale={scale:F3} " +
                    $"pivotY={bounds.min.y:F4} clips={AssetDatabase.LoadAllAssetsAtPath(modelPath).OfType<AnimationClip>().Count(IsRealClip)}");
            }

            AssetDatabase.SaveAssets();
            return models.Length;
        }

        private static int BuildProps(string sourceDir, string prefabDir, string namePrefix,
            string materialDir, Shader shader, Dictionary<Material, Material> cache,
            List<string> report, float normalizeHeight)
        {
            string[] models = FindModels(sourceDir);
            if (models.Length == 0)
            {
                Debug.LogError($"[ArtPackImporter] No models under {sourceDir}");
                EditorApplication.Exit(5);
                return 0;
            }

            foreach (string modelPath in models)
            {
                var root = AssetDatabase.LoadAssetAtPath<GameObject>(modelPath);
                var instance = (GameObject)UnityEngine.Object.Instantiate(root);
                string prefabPath = $"{prefabDir}/{namePrefix}{root.name}.prefab";

                AssignMaterials(instance, shader, cache, materialDir);

                if (normalizeHeight > 0f)
                {
                    NormalizeHeight(instance, normalizeHeight);
                }

                SnapPivotToFeet(instance);

                PrefabUtility.SaveAsPrefabAsset(instance, prefabPath);
                Bounds bounds = BoundsOf(instance);
                UnityEngine.Object.DestroyImmediate(instance);

                report.Add($"{prefabPath} | height={bounds.size.y:F3}m pivotY={bounds.min.y:F4}");
            }

            AssetDatabase.SaveAssets();
            return models.Length;
        }

        private static string[] FindModels(string folder)
        {
            return AssetDatabase
                .FindAssets("t:Model", new[] { folder })
                .Select(AssetDatabase.GUIDToAssetPath)
                .OrderBy(p => p, StringComparer.Ordinal)
                .ToArray();
        }

        private static bool IsRealClip(AnimationClip clip)
        {
            return clip != null && !clip.name.StartsWith("__preview__", StringComparison.Ordinal);
        }

        /// <summary>
        /// KayKit ships a generic bone rig, not a Humanoid one. Without this the
        /// FBX imports with no avatar and no Animator can be built.
        /// </summary>
        private static void ConfigureModelImporter(string modelPath, ModelImporterAnimationType animationType)
        {
            var importer = AssetImporter.GetAtPath(modelPath) as ModelImporter;
            if (importer == null || importer.animationType == animationType &&
                importer.avatarSetup == ModelImporterAvatarSetup.CreateFromThisModel)
            {
                return;
            }

            importer.animationType = animationType;
            importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            importer.importAnimation = true;
            importer.SaveAndReimport();
        }

        private static void AssignMaterials(GameObject instance, Shader shader,
            Dictionary<Material, Material> cache, string materialDir = KayKitMaterialDir)
        {
            foreach (Renderer r in instance.GetComponentsInChildren<Renderer>(true))
            {
                var slots = r.sharedMaterials;
                if (slots == null || slots.Length == 0)
                {
                    continue;
                }

                for (int i = 0; i < slots.Length; i++)
                {
                    Material source = slots[i];
                    if (source == null)
                    {
                        Debug.LogWarning($"[ArtPackImporter] {instance.name}: null material slot, substituting white");
                        slots[i] = CreateMaterial(shader, "Fallback", Color.white, null, materialDir);
                        continue;
                    }

                    if (!cache.TryGetValue(source, out Material target))
                    {
                        target = CreateMaterial(shader, source.name, ResolveColor(source), ResolveTexture(source), materialDir);
                        cache[source] = target;
                    }

                    slots[i] = target;
                }

                r.sharedMaterials = slots;
            }
        }

        private static Color ResolveColor(Material source)
        {
            return source.HasProperty("_BaseColor") ? source.GetColor("_BaseColor")
                : source.HasProperty("_Color") ? source.GetColor("_Color")
                : Color.white;
        }

        private static Texture ResolveTexture(Material source)
        {
            if (source.mainTexture != null)
            {
                return source.mainTexture;
            }

            return source.HasProperty("_BaseMap") ? source.GetTexture("_BaseMap") : null;
        }

        private static Material CreateMaterial(Shader shader, string sourceName, Color color,
            Texture texture, string materialDir)
        {
            string safe = Sanitize(sourceName);
            var material = new Material(shader) { name = $"Mat_{safe}" };

            if (material.HasProperty("_BaseMap") && texture != null)
            {
                material.SetTexture("_BaseMap", texture);
            }

            if (material.HasProperty("_BaseColor"))
            {
                material.SetColor("_BaseColor", texture != null ? Color.white : color);
            }

            if (material.HasProperty("_Metallic"))
            {
                material.SetFloat("_Metallic", 0f);
            }

            if (material.HasProperty("_Smoothness"))
            {
                material.SetFloat("_Smoothness", 0.05f);
            }

            material.enableInstancing = true;

            string path = AssetDatabase.GenerateUniqueAssetPath($"{materialDir}/{material.name}.mat");
            AssetDatabase.CreateAsset(material, path);
            return material;
        }

        private static string Sanitize(string name)
        {
            char[] invalid = Path.GetInvalidFileNameChars();
            var chars = name.Select(c => invalid.Contains(c) ? '_' : c).ToArray();
            return new string(chars);
        }

        private static float NormalizeHeight(GameObject instance, float targetHeight)
        {
            Bounds bounds = BoundsOf(instance);
            if (bounds.size.y <= 0.001f)
            {
                return 1f;
            }

            float scale = targetHeight / bounds.size.y;
            instance.transform.localScale *= scale;
            return scale;
        }

        private static void SnapPivotToFeet(GameObject instance)
        {
            Bounds bounds = BoundsOf(instance);
            instance.transform.localPosition -= new Vector3(0f, bounds.min.y, 0f);
        }

        private static void AddAnimator(GameObject instance, string characterName, string clipSourcePath)
        {
            var animator = instance.GetComponent<Animator>();
            if (animator == null)
            {
                animator = instance.AddComponent<Animator>();
            }

            animator.applyRootMotion = false;
            animator.cullingMode = AnimatorCullingMode.CullUpdateTransforms;

            string controllerPath = $"{ControllerDir}/Anim_{characterName}.controller";
            var controller = BuildController(controllerPath, characterName, clipSourcePath);

            animator.runtimeAnimatorController = controller;

            var avatar = animator.avatar;
            if (avatar == null || !avatar.isValid)
            {
                Debug.LogError($"[ArtPackImporter] {characterName}: no valid avatar");
            }
        }

        private static RuntimeAnimatorController BuildController(string controllerPath,
            string characterName, string clipSourcePath)
        {
            AnimationClip[] clips = AssetDatabase
                .LoadAllAssetsAtPath(clipSourcePath)
                .OfType<AnimationClip>()
                .Where(IsRealClip)
                .ToArray();

            var controller = AssetDatabase.LoadAssetAtPath<AnimatorController>(controllerPath);
            if (controller != null)
            {
                AssetDatabase.DeleteAsset(controllerPath);
                controller = null;
            }

            controller = AnimatorController.CreateAnimatorControllerAtPath(controllerPath);

            AnimatorControllerLayer layer = controller.layers[0];
            if (layer.stateMachine == null)
            {
                var machine = new AnimatorStateMachine { name = "Base" };
                AssetDatabase.AddObjectToAsset(machine, controller);
                layer.stateMachine = machine;
                controller.layers = new[] { layer };
            }

            AnimatorStateMachine stateMachine = controller.layers[0].stateMachine;

            var existing = stateMachine.states.Select(s => s.state.name).ToHashSet(StringComparer.Ordinal);
            foreach (var clip in clips)
            {
                if (existing.Contains(clip.name))
                {
                    continue;
                }

                var state = stateMachine.AddState(clip.name);
                state.motion = clip;
                state.writeDefaultValues = false;
            }

            if (stateMachine.states.Length > 0 && stateMachine.defaultState == null)
            {
                stateMachine.defaultState = stateMachine.states[0].state;
            }

            EditorUtility.SetDirty(controller);
            return controller;
        }

        private static Bounds BoundsOf(GameObject instance)
        {
            Renderer[] renderers = instance.GetComponentsInChildren<Renderer>(true);
            if (renderers.Length == 0)
            {
                return new Bounds(instance.transform.position, Vector3.zero);
            }

            Bounds bounds = renderers[0].bounds;
            for (int i = 1; i < renderers.Length; i++)
            {
                bounds.Encapsulate(renderers[i].bounds);
            }

            return bounds;
        }

        private static void EnsureFolders()
        {
            string[] folders =
            {
                CharacterPrefabDir,
                FarmPrefabDir,
                AccessoryPrefabDir,
                ControllerDir,
                KayKitMaterialDir,
                QuaterniusMaterialDir,
            };

            foreach (string folder in folders)
            {
                CreateFolder(folder);
            }
        }

        private static void CreateFolder(string assetPath)
        {
            if (AssetDatabase.IsValidFolder(assetPath))
            {
                return;
            }

            string[] parts = assetPath.Split('/');
            string current = parts[0];
            for (int i = 1; i < parts.Length; i++)
            {
                string next = $"{current}/{parts[i]}";
                if (!AssetDatabase.IsValidFolder(next))
                {
                    AssetDatabase.CreateFolder(current, parts[i]);
                }

                current = next;
            }
        }
    }
}
