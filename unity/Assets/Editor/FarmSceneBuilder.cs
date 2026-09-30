using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Unity.Cinemachine;
using EmberHollow.Engine;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

namespace EmberHollow.EditorTools
{
    /// <summary>
    /// Builds Assets/Scenes/Farm.unity entirely in code, from the prefabs that
    /// <see cref="ArtPackImporter"/> produced.
    ///
    /// Nobody on this team can open the Editor and click, so the scene is a
    /// build product, not an authored one. Re-running is idempotent: the scene is
    /// created fresh from scratch every time.
    ///
    ///   Unity.exe -batchmode -quit -projectPath unity \
    ///     -executeMethod EmberHollow.EditorTools.FarmSceneBuilder.Build
    /// </summary>
    public static class FarmSceneBuilder
    {
        public const string ScenePath = "Assets/Scenes/Farm.unity";

        private const string CharacterDir = "Assets/Prefabs/Characters";
        private const string FarmPropDir = "Assets/Prefabs/Props/FarmBuildings";
        private const string AccessoryDir = "Assets/Prefabs/Props/AdventurerAccessories";
        private const string MaterialDir = "Assets/Art/Materials";
        private const string GroundMaterialPath = MaterialDir + "/Farm/Mat_Ground_Grass.mat";

        private const string PlayerPrefabName = "KayKit_Adventurer_Knight";
        private const float PlotSize = 14f;
        private const float YardRadius = 26f;

        private static readonly (string name, float x, float z, float yaw)[] FarmLayout =
        {
            ("Quaternius_Farm_Barn", -14f, -9f, 18f),
            ("Quaternius_Farm_OpenBarn", -20f, -3f, 90f),
            ("Quaternius_Farm_ChickenCoop", 9f, -11f, -24f),
            ("Quaternius_Farm_Silo", -7f, -17f, 0f),
            ("Quaternius_Farm_Well", 4f, 6f, 0f),
            ("Quaternius_Farm_WaterTower", 13f, 3f, 0f),
            ("Quaternius_Farm_Windmill", -3f, -24f, 45f),
            ("Quaternius_Farm_TowerWindmill", 19f, -14f, -60f),
        };

        public static void Build()
        {
            try
            {
                Run();
            }
            catch (Exception ex)
            {
                Debug.LogError($"[FarmScene] Unhandled exception: {ex}");
                EditorApplication.Exit(2);
            }
        }

        private static void Run()
        {
            var scene = EditorSceneManager.NewScene(
                NewSceneSetup.EmptyScene, NewSceneMode.Single);

            int placed = 0;
            placed += BuildEnvironment();
            placed += BuildFarmstead();
            placed += BuildPlayer();
            placed += BuildLighting();
            placed += BuildCamera();

            EditorSceneManager.MarkSceneDirty(scene);

            Directory.CreateDirectory(Path.Combine("Assets", "Scenes"));
            if (!EditorSceneManager.SaveScene(scene, ScenePath))
            {
                Debug.LogError($"[FarmScene] SaveScene failed for {ScenePath}");
                EditorApplication.Exit(3);
                return;
            }

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);

            RegisterInBuildSettings();

            Debug.Log(
                $"[FarmScene] RESULT Succeeded Scene={ScenePath} Objects={placed} " +
                $"OnDisk={File.Exists(ScenePath)}");
            EditorApplication.Exit(0);
        }

        /// <summary>
        /// The farm must be the first enabled scene so WebGlBuilder picks it up
        /// instead of shipping whatever happened to be registered before.
        /// </summary>
        private static void RegisterInBuildSettings()
        {
            var others = EditorBuildSettings.scenes
                .Where(s => s.path != ScenePath)
                .ToList();

            others.Insert(0, new EditorBuildSettingsScene(ScenePath, true));
            EditorBuildSettings.scenes = others.ToArray();

            Debug.Log($"[FarmScene] Build Settings now: {string.Join(", ", EditorBuildSettings.scenes.Select(s => s.path))}");
        }

        private static int BuildEnvironment()
        {
            var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ground.name = "Ground";
            ground.transform.position = Vector3.zero;
            ground.transform.localScale = new Vector3(12f, 1f, 12f);
            ground.isStatic = true;
            ApplyMaterial(ground, GroundMaterial());

            var water = GameObject.CreatePrimitive(PrimitiveType.Plane);
            water.name = "Water";
            water.transform.position = new Vector3(-4f, -0.35f, 26f);
            water.transform.localScale = new Vector3(9f, 1f, 5f);
            water.isStatic = true;
            ApplyMaterial(water, GroundMaterial());

            int fences = 0;
            float step = 8f;
            for (float x = -YardRadius; x <= YardRadius + 0.01f; x += step)
            {
                fences += PlaceProp("Fence", $"Fence_North_{x:0}", new Vector3(x, 0f, -YardRadius), 0f);
                fences += PlaceProp("Fence", $"Fence_South_{x:0}", new Vector3(x, 0f, YardRadius), 0f);
            }

            for (float z = -YardRadius; z <= YardRadius + 0.01f; z += step)
            {
                fences += PlaceProp("Fence2", $"Fence_West_{z:0}", new Vector3(-YardRadius, 0f, z), 90f);
                fences += PlaceProp("Fence2", $"Fence_East_{z:0}", new Vector3(YardRadius, 0f, z), 90f);
            }

            return 2 + fences;
        }

        private static int BuildFarmstead()
        {
            int placed = 0;

            var plot = new GameObject("FarmPlot");
            plot.transform.position = Vector3.zero;

            for (int x = 0; x < 8; x++)
            {
                for (int z = 0; z < 8; z++)
                {
                    var tile = GameObject.CreatePrimitive(PrimitiveType.Quad);
                    tile.name = $"Soil_{x}_{z}";
                    tile.transform.SetParent(plot.transform);
                    tile.transform.position = new Vector3(
                        -PlotSize / 2f + x + 0.5f, 0.02f, -PlotSize / 2f + z + 0.5f);
                    tile.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
                    tile.isStatic = true;
                    ApplyMaterial(tile, GroundMaterial());
                }
            }

            placed++;

            foreach ((string name, float x, float z, float yaw) in FarmLayout)
            {
                placed += PlaceProp(name, $"Farm_{name}", new Vector3(x, 0f, z), yaw);
            }

            return placed;
        }

        private static int BuildPlayer()
        {
            string prefabPath = FindPrefab(CharacterDir, PlayerPrefabName);
            if (prefabPath == null)
            {
                Debug.LogError($"[FarmScene] Player prefab '{PlayerPrefabName}' not found under {CharacterDir}");
                EditorApplication.Exit(4);
                return 0;
            }

            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(prefabPath);
            var player = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
            player.name = "Player";
            player.transform.position = new Vector3(0f, 0f, 6f);
            player.transform.rotation = Quaternion.Euler(0f, 200f, 0f);

            if (player.GetComponent<PlayerMovementController>() == null)
            {
                player.AddComponent<PlayerMovementController>();
            }

            var collider = player.GetComponent<CharacterController>();
            if (collider == null)
            {
                collider = player.AddComponent<CharacterController>();
                collider.height = 1.8f;
                collider.radius = 0.35f;
                collider.center = new Vector3(0f, 0.9f, 0f);
                collider.slopeLimit = 50f;
                collider.stepOffset = 0.4f;
            }

            string axe = FindPrefab(AccessoryDir, "KayKit_Accessory_axe_1handed");
            if (axe != null)
            {
                var axePrefab = AssetDatabase.LoadAssetAtPath<GameObject>(axe);
                var hand = player.transform.Find("RightHand") ?? player.transform;
                var held = (GameObject)PrefabUtility.InstantiatePrefab(axePrefab);
                held.name = "HeldAxe";
                held.transform.SetParent(hand, false);
                held.transform.localPosition = new Vector3(0.25f, 0.55f, 0.15f);
                held.transform.localRotation = Quaternion.Euler(-20f, 0f, 65f);
            }

            return 1;
        }

        private static int BuildLighting()
        {
            var sunGo = new GameObject("Sun");
            sunGo.transform.rotation = Quaternion.Euler(35f, 170f, 0f);

            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.75f;

            var dayNight = sunGo.AddComponent<DayNightController>();
            sunGo.AddComponent<CinemachineBrain>();
            dayNight.Apply();

            var fill = new GameObject("Fill");
            fill.transform.rotation = Quaternion.Euler(30f, -20f, 0f);
            var fillLight = fill.AddComponent<Light>();
            fillLight.type = LightType.Directional;
            fillLight.intensity = 0.18f;
            fillLight.color = new Color(0.72f, 0.80f, 1f);
            fillLight.shadows = LightShadows.None;

            SetUpSky();

            return 3;
        }

        private static void SetUpSky()
        {
            var sky = RenderSettings.skybox;
            if (sky != null)
            {
                return;
            }

            var material = new Material(Shader.Find("Skybox/Procedural"))
            {
                name = "Mat_Sky_Valley"
            };
            if (material.HasProperty("_SkyTint"))
            {
                material.SetColor("_SkyTint", new Color(0.42f, 0.58f, 0.78f));
            }

            if (material.HasProperty("_GroundColor"))
            {
                material.SetColor("_GroundColor", new Color(0.32f, 0.36f, 0.28f));
            }

            if (material.HasProperty("_Exposure"))
            {
                material.SetFloat("_Exposure", 1.15f);
            }

            material.enableInstancing = true;

            EnsureFolder(MaterialDir + "/Farm");
            AssetDatabase.CreateAsset(material, GroundMaterialPath.Replace(".mat", "_Sky.mat"));
            RenderSettings.skybox = material;
        }

        private static int BuildCamera()
        {
            var mainGo = new GameObject("MainCamera")
            {
                tag = "MainCamera"
            };

            var camera = mainGo.AddComponent<Camera>();
            camera.fieldOfView = 50f;
            camera.nearClipPlane = 0.15f;
            camera.farClipPlane = 400f;
            mainGo.AddComponent<CinemachineBrain>();
            mainGo.AddComponent<AudioListener>();

            var rigGo = new GameObject("FarmVirtualCamera");
            var rig = rigGo.AddComponent<CinemachineCamera>();
            rig.Priority = 10;
            rig.Lens.FieldOfView = 50f;
            rig.Lens.NearClipPlane = 0.15f;

            var player = GameObject.Find("Player");
            if (player != null)
            {
                rig.Target = new CameraTarget
                {
                    TrackingTarget = player.transform,
                    LookAtTarget = null,
                    CustomLookAtTarget = false
                };

                var follow = rigGo.AddComponent<CinemachineThirdPersonFollow>();
                follow.CameraDistance = 6.5f;
                follow.VerticalArmLength = 1.6f;
                follow.CameraSide = 0.55f;
                follow.Damping = new Vector3(0.5f, 0.4f, 0.5f);
            }
            else
            {
                rig.Target = new CameraTarget { TrackingTarget = rigGo.transform };
                Debug.LogWarning("[FarmScene] Player not found; virtual camera has no follow target");
            }

            rigGo.AddComponent<CinemachineDeoccluder>();

            return 2;
        }

        private static int PlaceProp(string name, string instanceName, Vector3 position, float yaw)
        {
            string prefabPath = FindPrefab(FarmPropDir, name) ?? FindPrefab(FarmPropDir, $"Quaternius_Farm_{name}");
            if (prefabPath == null)
            {
                Debug.LogWarning($"[FarmScene] Prop '{name}' not found under {FarmPropDir}, skipped");
                return 0;
            }

            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(prefabPath);
            var instance = (GameObject)PrefabUtility.InstantiatePrefab(prefab);
            instance.name = instanceName;
            instance.transform.position = position;
            instance.transform.rotation = Quaternion.Euler(0f, yaw, 0f);
            MarkStaticRecursive(instance);
            return 1;
        }

        private static void MarkStaticRecursive(GameObject go)
        {
            go.isStatic = true;
            foreach (Transform child in go.transform)
            {
                MarkStaticRecursive(child.gameObject);
            }
        }

        private static string FindPrefab(string folder, string name)
        {
            string[] guids = AssetDatabase.FindAssets("t:Prefab", new[] { folder });
            foreach (string guid in guids)
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                if (string.Equals(Path.GetFileNameWithoutExtension(path), name, StringComparison.Ordinal))
                {
                    return path;
                }
            }

            return null;
        }

        private static void ApplyMaterial(GameObject go, Material material)
        {
            var renderer = go.GetComponent<Renderer>();
            if (renderer == null || material == null)
            {
                return;
            }

            renderer.sharedMaterial = material;
            renderer.shadowCastingMode = go.name.StartsWith("Soil", StringComparison.Ordinal)
                ? ShadowCastingMode.Off
                : ShadowCastingMode.On;
        }

        private static Material GroundMaterial()
        {
            var existing = AssetDatabase.LoadAssetAtPath<Material>(GroundMaterialPath);
            if (existing != null)
            {
                return existing;
            }

            EnsureFolder(MaterialDir + "/Farm");

            var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            var material = new Material(shader) { name = "Mat_Ground_Grass" };
            material.SetColor("_BaseColor", new Color(0.32f, 0.44f, 0.22f));
            if (material.HasProperty("_Smoothness"))
            {
                material.SetFloat("_Smoothness", 0.02f);
            }

            material.enableInstancing = true;
            AssetDatabase.CreateAsset(material, GroundMaterialPath);
            return material;
        }

        private static void EnsureFolder(string assetPath)
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
