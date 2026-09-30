using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Unity.Cinemachine;
using EmberHollow.Engine;
using EmberHollow.UI;
using EmberHollow.View;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;
using UnityEngine.UIElements;

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

        // The authored farm map is 32x24 with a two-tile impassable ring, so the
        // playable soil is the inner 28x20. These must agree with
        // DefaultContent.FarmMap or the player can walk onto a tile the
        // simulation believes is wall.
        private const float TillableWidth = 28f;
        private const float TillableHeight = 20f;

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
            placed += BuildSimulation();
            placed += BuildHud();
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

            // The tillable region of the 32x24 farm is every tile inside the
            // two-tile impassable ring, which is 28x20 world units. It is drawn as
            // one quad rather than one quad per tile: 560 GameObjects of static
            // geometry would cost more than the entire rest of the scene, and the
            // tile grid is only visible once soil has been turned anyway.
            var plot = new GameObject("FarmPlot");
            plot.transform.position = Vector3.zero;

            GameObject soil = GameObject.CreatePrimitive(PrimitiveType.Quad);
            soil.name = "Soil_Bed";
            soil.transform.SetParent(plot.transform, false);
            soil.transform.position = new Vector3(0f, 0.02f, 0f);
            soil.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            soil.transform.localScale = new Vector3(TillableWidth, TillableHeight, 1f);
            soil.isStatic = true;
            UnityEngine.Object.DestroyImmediate(soil.GetComponent<Collider>());
            ApplyMaterial(soil, MaterialFor("Farm/Mat_Soil_Bed", SoilColor()));

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

            // Interaction lives on the player so it can read the facing and the
            // transform the camera is already following.
            if (player.GetComponent<PlayerInteractionController>() == null)
            {
                player.AddComponent<PlayerInteractionController>();
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

        /// <summary>
        /// Owns GameState, the EventBus and the clock for the whole scene. One
        /// runner per session, so views and UI can resolve it from the scene
        /// instead of each keeping their own copy of the state.
        /// </summary>
        private static int BuildSimulation()
        {
            var go = new GameObject("Simulation");
            go.AddComponent<SimulationRunner>();
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

        private static Color SoilColor() => new Color(0.42f, 0.30f, 0.19f);

        /// <summary>
        /// Loads or creates a flat unlit material under <c>Assets/Art/Materials</c>.
        /// Tile overlays are unlit on purpose: they are read at a glance from a
        /// top-down camera, and lighting them would make tilled soil and watered
        /// soil differ by shadow as well as by colour.
        /// </summary>
        private static Material MaterialFor(string name, Color color, bool transparent = false)
        {
            string path = $"{MaterialDir}/{name}.mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (existing != null)
            {
                return existing;
            }

            EnsureFolder(MaterialDir);

            var shader = Shader.Find("Universal Render Pipeline/Unlit")
                ?? Shader.Find("Unlit/Color")
                ?? Shader.Find("Sprites/Default");

            if (shader == null)
            {
                Debug.LogError($"[FarmScene] no unlit shader available for {name}");
                return null;
            }

            var material = new Material(shader) { name = name };

            if (material.HasProperty("_BaseColor"))
            {
                material.SetColor("_BaseColor", color);
            }

            if (material.HasProperty("_Color"))
            {
                material.SetColor("_Color", color);
            }

            if (transparent)
            {
                // Surfaced through the standard URP transparent path, so the
                // highlight and the tool puff read as an overlay on the soil
                // rather than replacing it.
                SetMaterialFloat(material, "_Surface", 1f);
                SetMaterialFloat(material, "_Blend", 0f);
                SetMaterialFloat(material, "_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
                SetMaterialFloat(material, "_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
                SetMaterialFloat(material, "_ZWrite", 0f);
                material.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                material.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
            }

            material.enableInstancing = true;
            AssetDatabase.CreateAsset(material, path);
            return material;
        }

        private static void SetMaterialFloat(Material material, string property, float value)
        {
            if (material.HasProperty(property))
            {
                material.SetFloat(property, value);
            }
        }

        /// <summary>
        /// Builds the UI Toolkit HUD: writes the uxml and uss, creates the panel
        /// settings, and assembles the object the HUD lives on.
        ///
        /// The markup is generated here rather than committed as hand-placed
        /// files so a single <c>FarmSceneBuilder.Build</c> reproduces the whole
        /// playable game, markup included. Nobody can click in the Editor, so
        /// "add a UI document by hand" is not an option anyone has.
        /// </summary>
        private static int BuildHud()
        {
            string uiDir = "Assets/UI";
            EnsureFolder(uiDir);

            WriteIfChanged($"{uiDir}/Hud.uxml", HudMarkup());
            WriteIfChanged($"{uiDir}/Hud.uss", HudStylesheet());
            AssetDatabase.ImportAsset($"{uiDir}/Hud.uxml", ImportAssetOptions.ForceSynchronousImport);
            AssetDatabase.ImportAsset($"{uiDir}/Hud.uss", ImportAssetOptions.ForceSynchronousImport);

            var visualTree = AssetDatabase.LoadAssetAtPath<VisualTreeAsset>($"{uiDir}/Hud.uxml");
            if (visualTree == null)
            {
                Debug.LogError("[FarmScene] Hud.uxml failed to import; the HUD will be blank");
                return 0;
            }

            PanelSettings panel = PanelSettingsFor($"{uiDir}/HudPanel.asset", uiDir);
            if (panel == null)
            {
                return 0;
            }

            var hudGo = new GameObject("Hud");
            var document = hudGo.AddComponent<UIDocument>();
            document.panelSettings = panel;
            document.visualTreeAsset = visualTree;
            document.sortingOrder = 10;

            hudGo.AddComponent<HudController>();

            // The tile overlays are a world-space object, so it hangs off the
            // simulation rather than the HUD.
            var sim = GameObject.Find("Simulation");
            var viewGo = new GameObject("FarmTiles");
            viewGo.transform.position = Vector3.zero;
            viewGo.transform.SetParent(sim != null ? sim.transform : null, false);

            var tileView = viewGo.AddComponent<FarmTileView>();
            AssignTileMaterials(tileView);

            return 2;
        }

        private static void AssignTileMaterials(FarmTileView view)
        {
            SetPrivate(view, "_soilMaterial", MaterialFor("Farm/Mat_Soil_Bed", SoilColor()));
            SetPrivate(view, "_tilledMaterial", MaterialFor("Farm/Mat_Soil_Tilled", new Color(0.30f, 0.20f, 0.12f)));
            SetPrivate(view, "_wateredMaterial", MaterialFor("Farm/Mat_Soil_Watered", new Color(0.17f, 0.14f, 0.11f)));
            SetPrivate(view, "_cropMaterial", MaterialFor("Farm/Mat_Crop", new Color(0.30f, 0.66f, 0.24f)));
            SetPrivate(view, "_ripeMaterial", MaterialFor("Farm/Mat_Crop_Ripe", new Color(0.85f, 0.78f, 0.22f)));
            SetPrivate(view, "_targetValidMaterial", MaterialFor("Farm/Mat_Target_Ok", new Color(0.30f, 0.90f, 0.40f, 0.35f), transparent: true));
            SetPrivate(view, "_targetInvalidMaterial", MaterialFor("Farm/Mat_Target_Bad", new Color(0.95f, 0.28f, 0.25f, 0.35f), transparent: true));
        }

        /// <summary>
        /// Writes a serialized field the HUD's inspector would normally own.
        /// SerializedObject rather than reflection so the field is recorded the
        /// same way a hand-dragged reference would be, and survives a reload.
        /// </summary>
        private static void SetPrivate(UnityEngine.Object target, string field, UnityEngine.Object value)
        {
            var so = new SerializedObject(target);
            SerializedProperty property = so.FindProperty(field);

            if (property == null)
            {
                Debug.LogError($"[FarmScene] {target.GetType().Name} has no serialized field '{field}'");
                return;
            }

            property.objectReferenceValue = value;
            so.ApplyModifiedPropertiesWithoutUndo();
        }

        private static PanelSettings PanelSettingsFor(string assetPath, string uiDir)
        {
            var existing = AssetDatabase.LoadAssetAtPath<PanelSettings>(assetPath);
            if (existing != null)
            {
                return existing;
            }

            var panel = ScriptableObject.CreateInstance<PanelSettings>();
            panel.scaleMode = PanelScaleMode.ScaleWithScreenSize;
            panel.referenceResolution = new Vector2Int(1280, 720);
            panel.screenMatchMode = PanelScreenMatchMode.MatchWidthOrHeight;
            panel.match = 0.5f;
            panel.sortingOrder = 10f;

            // Without a theme the panel still renders, but every element arrives
            // with no default styling, so the HUD relies entirely on its own uss.
            panel.themeStyleSheet = LoadRuntimeTheme(uiDir);

            AssetDatabase.CreateAsset(panel, assetPath);
            return panel;
        }

        private static ThemeStyleSheet LoadRuntimeTheme(string uiDir)
        {
            // The editor's own "create panel settings" path assigns a default
            // runtime theme from com.unity.ui, which is not installed here
            // because UI Toolkit ships as a built-in module in Unity 6. A theme
            // sheet that imports the built-in theme gives the same result.
            string themePath = $"{uiDir}/UnityDefaultRuntimeTheme.tss";
            WriteIfChanged(themePath, "@import url(\"unity-theme://default\");\n");

            AssetDatabase.ImportAsset(themePath, ImportAssetOptions.ForceSynchronousImport);

            var theme = AssetDatabase.LoadAssetAtPath<ThemeStyleSheet>(themePath);
            if (theme == null)
            {
                Debug.LogWarning("[FarmScene] runtime theme did not import; the HUD relies on its own stylesheet");
            }

            return theme;
        }

        private static void WriteIfChanged(string path, string contents)
        {
            if (File.Exists(path) && string.Equals(File.ReadAllText(path), contents, StringComparison.Ordinal))
            {
                return;
            }

            File.WriteAllText(path, contents);
        }

        private static string HudMarkup() =>
@"<ui:UXML xmlns:ui=""UnityEngine.UIElements"">
    <ui:VisualElement name=""root"" class=""hud"">
        <ui:VisualElement name=""top-left"" class=""panel stats"">
            <ui:Label name=""date"" class=""date"" />
            <ui:VisualElement class=""row"">
                <ui:Label name=""time"" class=""stat time"" />
                <ui:Label name=""weather"" class=""stat weather"" />
            </ui:VisualElement>
            <ui:VisualElement class=""row"">
                <ui:Label name=""energy"" class=""stat energy"" />
                <ui:Label name=""money"" class=""stat money"" />
            </ui:VisualElement>
        </ui:VisualElement>

        <ui:VisualElement name=""notice"" class=""notice"">
            <ui:Label name=""notice-text"" class=""notice-text"" />
        </ui:VisualElement>

        <ui:Label name=""target"" class=""target"" />

        <ui:VisualElement name=""hotbar"" class=""hotbar"">
        </ui:VisualElement>

        <ui:VisualElement class=""controls"">
            <ui:Label text=""WASD move    SPACE use    1-8 select    Q stow"" class=""hint"" />
        </ui:VisualElement>
    </ui:VisualElement>
</ui:UXML>
";

        private static string HudStylesheet() =>
@"/* Parchment and wood, kept in the two palettes the rest of the UI uses. */
.hud {
    position: absolute;
    left: 0;
    top: 0;
    right: 0;
    bottom: 0;
}

.panel {
    position: absolute;
    background-color: rgba(46, 33, 24, 0.88);
    border-left-width: 3px;
    border-right-width: 3px;
    border-top-width: 3px;
    border-bottom-width: 3px;
    border-left-color: rgb(122, 88, 55);
    border-right-color: rgb(122, 88, 55);
    border-top-color: rgb(122, 88, 55);
    border-bottom-color: rgb(122, 88, 55);
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    border-bottom-left-radius: 6px;
    border-bottom-right-radius: 6px;
    padding: 8px 12px 8px 12px;
}

.stats {
    left: 14px;
    top: 14px;
    min-width: 190px;
}

.date {
    color: rgb(240, 226, 196);
    font-size: 19px;
    -unity-font-style: bold;
    margin-bottom: 3px;
}

.row {
    flex-direction: row;
}

.stat {
    color: rgb(214, 198, 166);
    font-size: 15px;
    margin-right: 14px;
    margin-bottom: 2px;
}

.energy {
    color: rgb(126, 208, 130);
}

.money {
    color: rgb(240, 205, 110);
}

.hotbar {
    position: absolute;
    left: 50%;
    bottom: 18px;
    flex-direction: row;
}

.slot {
    width: 76px;
    margin: 0 3px 0 3px;
    padding: 5px 4px 5px 4px;
    background-color: rgba(46, 33, 24, 0.88);
    border-left-width: 2px;
    border-right-width: 2px;
    border-top-width: 2px;
    border-bottom-width: 2px;
    border-left-color: rgb(96, 70, 46);
    border-right-color: rgb(96, 70, 46);
    border-top-color: rgb(96, 70, 46);
    border-bottom-color: rgb(96, 70, 46);
    border-top-left-radius: 5px;
    border-top-right-radius: 5px;
    border-bottom-left-radius: 5px;
    border-bottom-right-radius: 5px;
    align-items: center;
}

.slot.selected {
    border-left-color: rgb(240, 205, 110);
    border-right-color: rgb(240, 205, 110);
    border-top-color: rgb(240, 205, 110);
    border-bottom-color: rgb(240, 205, 110);
    background-color: rgba(72, 54, 32, 0.95);
}

.slot-key {
    color: rgb(150, 128, 96);
    font-size: 11px;
}

.slot-name {
    color: rgb(240, 226, 196);
    font-size: 12px;
    -unity-text-align: middle-center;
    white-space: normal;
    margin-top: 2px;
    margin-bottom: 2px;
}

.slot-qty {
    color: rgb(240, 205, 110);
    font-size: 11px;
}

.target {
    position: absolute;
    left: 50%;
    bottom: 118px;
    color: rgb(214, 198, 166);
    font-size: 14px;
    -unity-text-align: middle-center;
}

.notice {
    position: absolute;
    left: 50%;
    top: 96px;
    display: none;
    padding: 8px 18px 8px 18px;
    background-color: rgba(38, 60, 40, 0.92);
    border-left-width: 2px;
    border-right-width: 2px;
    border-top-width: 2px;
    border-bottom-width: 2px;
    border-left-color: rgb(126, 208, 130);
    border-right-color: rgb(126, 208, 130);
    border-top-color: rgb(126, 208, 130);
    border-bottom-color: rgb(126, 208, 130);
    border-top-left-radius: 6px;
    border-top-right-radius: 6px;
    border-bottom-left-radius: 6px;
    border-bottom-right-radius: 6px;
}

.notice.visible {
    display: flex;
}

.notice.failure {
    background-color: rgba(66, 30, 28, 0.92);
    border-left-color: rgb(226, 106, 98);
    border-right-color: rgb(226, 106, 98);
    border-top-color: rgb(226, 106, 98);
    border-bottom-color: rgb(226, 106, 98);
}

.notice-text {
    color: rgb(226, 240, 226);
    font-size: 16px;
    -unity-font-style: bold;
}

.notice.failure .notice-text {
    color: rgb(244, 206, 202);
}

.controls {
    position: absolute;
    right: 16px;
    top: 16px;
}

.hint {
    color: rgba(214, 198, 166, 0.7);
    font-size: 12px;
}
";
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
