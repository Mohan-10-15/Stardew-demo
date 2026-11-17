#nullable enable
using System;
using System.Collections;
using EmberHollow.Core;
using EmberHollow.Engine;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace EmberHollow.Tests.PlayMode
{
    /// <summary>
    /// Drives the shipping/sleep loop through the real farm scene and the real
    /// components. The public controller methods are called directly rather than
    /// by synthesising keystrokes, so a failure here is a wiring bug and not a
    /// flaky input-timing bug.
    ///
    /// The bed fixture is resolved at runtime so the test works both before and
    /// after Farm.unity is regenerated with the builder's new bed.
    /// </summary>
    public sealed class ShippingSleepPlayModeTests
    {
        private const string SceneName = "Farm";
        private SimulationRunner _runner = null!;
        private PlayerInteractionController _player = null!;
        private GameObject? _createdBed;

        [UnitySetUp]
        public IEnumerator SetUp()
        {
            SceneManager.LoadScene(SceneName, LoadSceneMode.Single);
            yield return null;
            yield return null;

            _runner = UnityEngine.Object.FindFirstObjectByType<SimulationRunner>();
            Assert.That(_runner, Is.Not.Null, "no SimulationRunner in the farm scene");
            _runner.EnsureInitialised();

            _player = UnityEngine.Object.FindFirstObjectByType<PlayerInteractionController>();
            Assert.That(_player, Is.Not.Null, "no PlayerInteractionController in the farm scene");
            _createdBed = null;
        }

        [UnityTest]
        public IEnumerator OpenShippingPublishesTheOpenEvent()
        {
            yield return null;

            int calls = 0;
            object? payload = new object();
            using (IDisposable subscription = _runner.Bus.On(GameEvents.ShippingOpened, p =>
            {
                calls++;
                payload = p;
            }))
            {
                _player.OpenShipping();
            }

            Assert.That(calls, Is.EqualTo(1), "opening shipping should publish exactly one event");
            Assert.That(payload, Is.Null, "the open event carries no payload");
        }

        [UnityTest]
        public IEnumerator SleepingAwayFromTheBedFailsWithNoBed()
        {
            yield return null;

            BedStation bed = ResolveBed();
            _player.transform.position = bed.transform.position + new Vector3(100f, 0f, 0f);

            SleepBlockedEvent? blocked = null;
            SleepResult result;
            using (IDisposable subscription = _runner.Bus.On<SleepBlockedEvent>(GameEvents.SleepBlocked, p => blocked = p))
            {
                result = _player.TrySleep();
            }

            Assert.That(result.Succeeded, Is.False, "sleeping far from the bed must be refused");
            Assert.That(result.Reason, Is.EqualTo("no-bed"), "the refusal must name a distinct reason");
            Assert.That(blocked, Is.Not.Null, "the refusal must publish its own failure event");
            Assert.That(blocked!.Reason, Is.EqualTo("no-bed"), "the event carries the same reason");
        }

        [UnityTest]
        public IEnumerator SleepingNextToTheBedAdvancesTheDay()
        {
            yield return null;

            BedStation bed = ResolveBed();
            _player.transform.position = bed.transform.position + new Vector3(1f, 0f, 0f);

            int dayBefore = _runner.State.World.DayCount;
            SleepResult result = _player.TrySleep();

            Assert.That(result.Succeeded, Is.True, $"sleeping by the bed failed: {result.Reason}");
            Assert.That(result.DayCount, Is.GreaterThan(dayBefore), "the result should carry the new day");
            Assert.That(_runner.State.World.DayCount, Is.GreaterThan(dayBefore), "the clock should reach the next morning");
        }

        [UnityTearDown]
        public IEnumerator TearDown()
        {
            if (_createdBed != null)
            {
                UnityEngine.Object.Destroy(_createdBed);
                _createdBed = null;
                yield return null;
            }
        }

        /// <summary>Uses the scene's bed when present, otherwise mounts one for the test.</summary>
        private BedStation ResolveBed()
        {
            BedStation? bed = UnityEngine.Object.FindFirstObjectByType<BedStation>();
            if (bed != null)
            {
                return bed;
            }

            _createdBed = new GameObject("TestBed");
            _createdBed.transform.position = new Vector3(-10f, 0f, -2f);
            return _createdBed.AddComponent<BedStation>();
        }
    }
}
