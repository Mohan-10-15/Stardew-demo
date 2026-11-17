#nullable enable
using UnityEngine;

namespace EmberHollow.Engine
{
    /// <summary>
    /// Marker for the shipping crate in the farm scene. Deposits are routed by
    /// the interaction layer through <c>SimulationRunner.Ship</c>; this component
    /// exists so the crate is identifiable in the built scene and can be given a
    /// hover prompt later without any rules living in the view.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class ShippingBinStation : MonoBehaviour
    {
        [TextArea(1, 3)]
        [SerializeField] private string _label = "Drop crops here; the bin pays out at sleep.";

        /// <summary>Author-facing hint shown by the future interaction prompt.</summary>
        public string Label => _label;
    }
}
