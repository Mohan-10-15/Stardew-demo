using System.Linq;
using Unity.Cinemachine;
using EmberHollow.Engine;
using NUnit.Framework;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace EmberHollow.Tests.EditMode
{
    /// <summary>
    /// Validates Assets/Scenes/Farm.unity on disk. Nobody can open the scene and
    /// look at it, so these assertions are the substitute for a visual review.
    /// </summary>
    [TestFixture]
    public sealed class FarmSceneTests
    {
        private const string ScenePath = "Assets/Scenes/Farm.unity";

        private static Scene OpenFarm()
        {
            Assert.That(System.IO.File.Exists(ScenePath), Is.True,
                $"{ScenePath} does not exist. Run EmberHollow.EditorTools.FarmSceneBuilder.Build");
            return EditorSceneManager.OpenScene(ScenePath, OpenSceneMode.Single);
        }

        [Test]
        public void FarmSceneExistsAndIsInBuildSettings()
        {
            Assert.That(System.IO.File.Exists(ScenePath), Is.True, ScenePath);

            bool registered = EditorBuildSettings.scenes
                .Any(s => s.enabled && s.path == ScenePath);
            Assert.That(registered, Is.True, $"{ScenePath} is not an enabled scene in Build Settings");
        }

        [Test]
        public void EveryRendererUsesASharedUrpMaterial()
        {
            Scene scene = OpenFarm();

            foreach (GameObject root in scene.GetRootGameObjects())
            {
                foreach (Renderer renderer in root.GetComponentsInChildren<Renderer>(true))
                {
                    foreach (Material material in renderer.sharedMaterials)
                    {
                        Assert.That(material, Is.Not.Null,
                            $"{FullName(renderer.transform)} has a null material slot (magenta)");
                        Assert.That(material.shader, Is.Not.Null,
                            $"{FullName(renderer.transform)} material '{material.name}' has no shader");
                        Assert.That(material.shader.name, Does.StartWith("Universal Render Pipeline/"),
                            $"{FullName(renderer.transform)} uses '{material.shader.name}', which is not a URP shader");
                        Assert.That(AssetDatabase.Contains(material), Is.True,
                            $"'{material.name}' is not a project asset, so it is duplicated per instance");
                        Assert.That(material.enableInstancing, Is.True,
                            $"'{material.name}' has GPU instancing off");
                    }
                }
            }
        }

        [Test]
        public void PlayerIsPresentAndControllable()
        {
            Scene scene = OpenFarm();

            var player = GameObject.Find("Player");
            Assert.That(player, Is.Not.Null, "No Player object in the farm scene");

            var movement = player.GetComponent<PlayerMovementController>();
            Assert.That(movement, Is.Not.Null, "Player has no PlayerMovementController");
            Assert.That(player.GetComponent<Animator>(), Is.Not.Null, "Player has no Animator");
            Assert.That(player.GetComponent<CharacterController>(), Is.Not.Null,
                "Player has no CharacterController, so it will fall through the world");

            Assert.That(player.GetComponent<Animator>().runtimeAnimatorController, Is.Not.Null,
                "Player Animator has no controller, so the character will not animate");
        }

        [Test]
        public void CinemachineFollowIsAngledAndThirdPerson()
        {
            Scene scene = OpenFarm();

            var rig = Object.FindObjectsByType<CinemachineCamera>(FindObjectsSortMode.None)
                .FirstOrDefault();
            Assert.That(rig, Is.Not.Null, "No CinemachineCamera in the farm scene");

            Assert.That(rig.Target.TrackingTarget, Is.Not.Null, "CinemachineCamera has no follow target");
            Assert.That(rig.Target.TrackingTarget.name, Is.EqualTo("Player"),
                "The camera is not following the Player");

            Assert.That(rig.Lens.FieldOfView, Is.InRange(40f, 70f),
                $"Field of view {rig.Lens.FieldOfView} is not a reasonable third-person lens");

            var follow = rig.GetComponent<CinemachineThirdPersonFollow>();
            Assert.That(follow, Is.Not.Null, "The camera has no CinemachineThirdPersonFollow body");
            Assert.That(follow.CameraDistance, Is.InRange(3f, 12f),
                $"CameraDistance {follow.CameraDistance} is not a third-person distance");
            Assert.That(follow.VerticalArmLength, Is.GreaterThan(0f),
                "VerticalArmLength must be positive so the camera looks down at an angle");

            Assert.That(rig.GetComponent<CinemachineDeoccluder>(), Is.Not.Null,
                "The camera has no CinemachineDeoccluder, so it will clip through buildings");

            var brains = Object.FindObjectsByType<CinemachineBrain>(FindObjectsSortMode.None);
            Assert.That(brains, Is.Not.Empty, "No CinemachineBrain in the scene");
        }

        [Test]
        public void LightingAndAtmosphereAreConfigured()
        {
            Scene scene = OpenFarm();

            var dayNight = Object.FindObjectsByType<DayNightController>(FindObjectsSortMode.None)
                .FirstOrDefault();
            Assert.That(dayNight, Is.Not.Null, "No DayNightController in the farm scene");

            var sun = dayNight.GetComponent<Light>();
            Assert.That(sun, Is.Not.Null, "The DayNightController has no Light");
            Assert.That(sun.type, Is.EqualTo(LightType.Directional),
                $"The clock-driven light is a {sun.type}, not a directional sun");
            Assert.That(sun.shadows, Is.Not.EqualTo(LightShadows.None),
                "The sun casts no shadows, so the scene will look flat");

            Assert.That(RenderSettings.fog, Is.True, "Fog is not enabled");
            Assert.That(RenderSettings.skybox, Is.Not.Null, "No skybox assigned");
        }

        [Test]
        public void FarmBuildingsFromTheQuaterniusPackArePlaced()
        {
            Scene scene = OpenFarm();

            var names = scene.GetRootGameObjects().Select(o => o.name).ToList();

            Assert.That(names.Any(n => n.StartsWith("Farm_Quaternius_Farm_Barn")), Is.True,
                "The Barn prefab is not placed in the farm scene");
            Assert.That(names.Count(n => n.StartsWith("Fence")), Is.GreaterThan(10),
                "The farm is not fenced in");
        }

        [Test]
        public void GroundIsLargeEnoughToWalkOn()
        {
            Scene scene = OpenFarm();

            var ground = GameObject.Find("Ground");
            Assert.That(ground, Is.Not.Null, "No ground in the farm scene");

            var renderer = ground.GetComponent<Renderer>();
            Assert.That(renderer, Is.Not.Null, "Ground has no Renderer");
            Assert.That(renderer.bounds.size.x, Is.GreaterThan(50f),
                $"Ground is only {renderer.bounds.size.x:F1}m wide, which is a cramped farm");
        }

        private static string FullName(Transform t)
        {
            string name = t.name;
            while (t.parent != null)
            {
                t = t.parent;
                name = $"{t.name}/{name}";
            }

            return name;
        }
    }
}
