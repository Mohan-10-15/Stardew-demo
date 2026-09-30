using System.Collections;
using System.Linq;
using NUnit.Framework;
using Unity.Cinemachine;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace EmberHollow.Tests.PlayMode
{
    /// <summary>
    /// Drives the real farm scene over real frames. This is the substitute for a
    /// playtest: nobody on this team can watch the game, so the loop has to be
    /// exercised by machine.
    ///
    /// Covers the two things that are easy to get wrong and impossible to see in
    /// a still image: continuous 8-directional movement, and the Cinemachine
    /// follow actually tracking the player.
    ///
    /// Note that batchmode frames are very short (a few milliseconds), so
    /// anything that waits for convergence polls a tolerance over a generous
    /// frame budget instead of assuming a wall-clock duration.
    /// </summary>
    public sealed class FarmScenePlayModeTests
    {
        private const string FarmScene = "Assets/Scenes/Farm.unity";
        private const int MaxSettleFrames = 900;

        private static readonly Vector2[] EightDirections =
        {
            new Vector2(1f, 0f), new Vector2(-1f, 0f),
            new Vector2(0f, 1f), new Vector2(0f, -1f),
            new Vector2(1f, 1f), new Vector2(-1f, 1f),
            new Vector2(1f, -1f), new Vector2(-1f, -1f),
        };

        private GameObject _player;
        private Engine.PlayerMovementController _movement;

        [UnitySetUp]
        public IEnumerator LoadFarm()
        {
            SceneManager.LoadScene("Farm", LoadSceneMode.Single);

            float deadline = Time.time + 20f;
            _player = null;
            while (_player == null && Time.time < deadline)
            {
                _player = GameObject.Find("Player");
                yield return null;
            }

            Assert.That(_player, Is.Not.Null, $"Player not found in {FarmScene}");
            _movement = _player.GetComponent<Engine.PlayerMovementController>();
            Assert.That(_movement, Is.Not.Null, "Player has no PlayerMovementController");
        }

        [UnityTest]
        public IEnumerator PlayerResolvesAllEightDirectionsToUnitVectors()
        {
            foreach (Vector2 input in EightDirections)
            {
                _movement.ApplyInput(input, false);

                Vector3 resolved = _movement.CurrentMoveDirection;
                Vector3 expected = new Vector3(input.x, 0f, input.y).normalized;

                Assert.That(_movement.HasInput, Is.True, $"Direction {input} was not recognised as input");
                Assert.That(resolved.y, Is.EqualTo(0f).Within(0.0001f),
                    $"Direction {input} produced vertical movement {resolved.y}");
                Assert.That(resolved.magnitude, Is.EqualTo(1f).Within(0.0001f),
                    $"Direction {input} resolved to {resolved}, which is not unit length");
                Assert.That(Vector3.Distance(resolved, expected), Is.LessThan(0.0001f),
                    $"Direction {input} resolved to {resolved}, expected {expected}");
            }

            _movement.ApplyInput(Vector2.zero, false);
            yield return null;
        }

        [UnityTest]
        public IEnumerator DiagonalInputIsNormalisedSoItIsNotFaster()
        {
            Vector2[] inputs = EightDirections.Concat(new[] { new Vector2(3f, 4f), new Vector2(5f, 5f) }).ToArray();

            foreach (Vector2 input in inputs)
            {
                _movement.ApplyInput(input, false);

                Assert.That(_movement.CurrentMoveDirection.magnitude, Is.EqualTo(1f).Within(0.0001f),
                    $"Input {input} resolved to magnitude {_movement.CurrentMoveDirection.magnitude}, not 1. " +
                    "An unnormalised diagonal is a speed exploit.");
            }

            _movement.ApplyInput(Vector2.zero, false);
            yield return null;
        }

        [UnityTest]
        public IEnumerator HeldInputActuallyTranslatesThePlayer()
        {
            foreach (Vector2 input in EightDirections)
            {
                Vector3 before = _player.transform.position;

                for (int i = 0; i < 5; i++)
                {
                    _movement.ApplyInput(input, false);
                    yield return null;
                }

                Vector3 delta = _player.transform.position - before;
                Vector3 horizontal = new Vector3(delta.x, 0f, delta.z);
                Vector3 expected = new Vector3(input.x, 0f, input.y).normalized;

                Assert.That(horizontal.magnitude, Is.GreaterThan(0.001f),
                    $"Direction {input} produced no horizontal movement over 5 frames");
                Assert.That(delta.y, Is.GreaterThan(-0.001f),
                    $"Direction {input} sank the player by {delta.y:F4}m");
                Assert.That(Vector3.Distance(horizontal.normalized, expected), Is.LessThan(0.01f),
                    $"Direction {input} moved along {horizontal.normalized}, expected {expected}");
            }
        }

        [UnityTest]
        public IEnumerator PlayerTurnsToFaceTheDirectionOfTravel()
        {
            float forwardAngle = 0f;
            float rightAngle = 0f;

            foreach (Vector3 target in new[] { Vector3.forward, Vector3.right })
            {
                Vector2 input = new Vector2(target.x, target.z).normalized;
                float angle = Vector3.Angle(_player.transform.forward, target);

                for (int i = 0; i < MaxSettleFrames && angle >= 15f; i++)
                {
                    _movement.ApplyInput(input, false);
                    yield return null;
                    angle = Vector3.Angle(_player.transform.forward, target);
                }

                _movement.ApplyInput(Vector2.zero, false);

                if (target == Vector3.forward)
                {
                    forwardAngle = angle;
                }
                else
                {
                    rightAngle = angle;
                }
            }

            Assert.That(forwardAngle, Is.LessThan(15f),
                $"Player still faces {forwardAngle:F1}deg from forward after walking forward");
            Assert.That(rightAngle, Is.LessThan(15f),
                $"Player still faces {rightAngle:F1}deg from right after walking right");
        }

        [UnityTest]
        public IEnumerator NoInputStopsThePlayerDead()
        {
            _movement.ApplyInput(new Vector2(1f, 1f), false);
            yield return null;

            _movement.ApplyInput(Vector2.zero, false);
            Vector3 before = _player.transform.position;
            yield return null;
            yield return null;

            Assert.That(Vector3.Distance(before, _player.transform.position), Is.LessThan(0.0001f),
                "The player drifted after input was released");
            Assert.That(_movement.HasInput, Is.False, "HasInput is still true with no input");
        }

        [UnityTest]
        public IEnumerator CameraFollowsThePlayerAtAnAngle()
        {
            var rig = Object.FindAnyObjectByType<CinemachineCamera>();
            Assert.That(rig, Is.Not.Null, "No CinemachineCamera in the farm scene");
            Assert.That(rig.Target.TrackingTarget, Is.EqualTo(_player.transform),
                "The virtual camera is not tracking the Player");

            _movement.ApplyInput(new Vector2(1f, 0f), false);

            Vector3 playerBefore = _player.transform.position;
            for (int i = 0; i < MaxSettleFrames; i++)
            {
                _movement.ApplyInput(new Vector2(1f, 0f), false);
                yield return null;
            }

            _movement.ApplyInput(Vector2.zero, false);

            Assert.That(Vector3.Distance(playerBefore, _player.transform.position), Is.GreaterThan(0.5f),
                "The player barely moved, so the camera test proved nothing");

            Vector3 playerPosition = _player.transform.position;
            Vector3 cameraPosition = Camera.main.transform.position;
            Vector3 offset = cameraPosition - playerPosition;

            float distance = offset.magnitude;
            Assert.That(distance, Is.InRange(3f, 14f),
                $"Camera is {distance:F2}m from the player, which is not a third-person distance");

            float horizontal = new Vector2(offset.x, offset.z).magnitude;
            Assert.That(horizontal, Is.GreaterThan(1f),
                "The camera is directly overhead rather than behind and above");
            Assert.That(offset.y, Is.GreaterThan(0.5f),
                "The camera is not above the player, so the view is not angled down");
        }
    }
}
