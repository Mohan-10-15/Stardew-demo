#nullable enable
using UnityEngine;

namespace EmberHollow.Engine
{
    /// <summary>
    /// Marks the bed the player can sleep in. Owns no rules: it only answers the
    /// proximity question the interaction controller asks, so the sleep sim
    /// stays engine-free and a PlayMode test can place a bed at a known point.
    /// The scene builder puts this on the bed it creates in Farm.unity.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class BedStation : MonoBehaviour
    {
        [Tooltip("How close the player must stand to use the bed, in world units.")]
        [SerializeField] private float _interactRadius = 2.5f;

        /// <summary>True when <paramref name="world"/> is close enough to use the bed.</summary>
        public bool InRange(Vector3 world)
        {
            return Vector3.Distance(transform.position, world) <= _interactRadius;
        }
    }
}
