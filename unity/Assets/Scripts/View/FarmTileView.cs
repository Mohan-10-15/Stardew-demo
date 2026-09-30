#nullable enable
using System.Collections.Generic;
using EmberHollow.Core;
using EmberHollow.Engine;
using UnityEngine;

namespace EmberHollow.View
{
    /// <summary>
    /// Draws the farm's tillable tiles: bare soil, tilled soil, water, and a crop
    /// per planted tile. Reads <see cref="MapState.Placed"/> and nothing else, so
    /// what the player sees is the simulation's own record rather than a parallel
    /// copy that could drift.
    ///
    /// Overlays come from a pool and are reused, because a full playthrough fills
    /// and empties hundreds of tiles and allocating a quad per action would put
    /// garbage straight into the frame the player is watching.
    ///
    /// The crop mesh is a plain scaled quad. There is no crop art in the project
    /// yet, and a green sprout that grows in four steps is honest about what is
    /// being simulated; it is not standing in for art that does not exist.
    /// </summary>
    [DisallowMultipleComponent]
    public sealed class FarmTileView : MonoBehaviour
    {
        [Tooltip("Materials are assigned by the scene builder.")]
        [SerializeField] private Material? _soilMaterial;
        [SerializeField] private Material? _tilledMaterial;
        [SerializeField] private Material? _wateredMaterial;
        [SerializeField] private Material? _cropMaterial;
        [SerializeField] private Material? _ripeMaterial;
        [SerializeField] private Material? _targetValidMaterial;
        [SerializeField] private Material? _targetInvalidMaterial;

        [SerializeField] private float _lift = 0.03f;
        [SerializeField] private float _cropMaxHeight = 0.9f;
        [SerializeField] private float _puffSeconds = 0.35f;

        private readonly Dictionary<int, Transform> _overlays = new Dictionary<int, Transform>();
        private readonly Stack<Transform> _pool = new Stack<Transform>();

        private SimulationRunner? _runner;
        private System.IDisposable? _subscription;
        private Transform? _target;
        private Transform? _puff;
        private float _puffUntil;
        private int _width = 32;
        private int _height = 24;
        private readonly List<int> _dead = new List<int>();

        private void Start()
        {
            _runner = GetComponentInParent<SimulationRunner>() ?? FindFirstObjectByType<SimulationRunner>();

            if (_runner != null)
            {
                _runner.EnsureInitialised();
                _subscription = _runner.Subscribe(GameEvents.StateChanged, OnStateChanged);
            }

            EnsureTargetMarker();
            EnsurePuff();
            Refresh();
        }

        private void OnStateChanged(object? payload)
        {
            Refresh();
        }

        private void OnDestroy()
        {
            _subscription?.Dispose();
        }

        /// <summary>Rebuilds every overlay from simulation state.</summary>
        public void Refresh()
        {
            if (_runner == null)
            {
                return;
            }

            MapState? map = _runner.State.Map(FarmGrid.FarmMapId);

            if (map == null)
            {
                return;
            }

            _width = map.Grid.Width;
            _height = map.Grid.Height;

            HashSet<int> live = new HashSet<int>();

            for (int i = 0; i < map.Placed.Count; i++)
            {
                PlacedObject placed = map.Placed[i];
                int key = FarmGrid.Key(placed.X, placed.Y, _width);

                if (live.Add(key))
                {
                    ApplyOverlay(placed);
                }
                else
                {
                    // Two objects on one tile: the first one placed owns the
                    // overlay, and the later one is a content bug rather than
                    // something to draw twice.
                    Debug.LogWarning(
                        $"[FarmTileView] two objects on tile {placed.X},{placed.Y}; keeping the first");
                }
            }

            // Anything the sim no longer has a record of must stop being drawn,
            // which is how a harvest and a wither both look right.
            _dead.Clear();
            foreach (int key in _overlays.Keys)
            {
                if (!live.Contains(key))
                {
                    _dead.Add(key);
                }
            }

            foreach (int key in _dead)
            {
                Recycle(_overlays[key]);
                _overlays.Remove(key);
            }
        }

        private void ApplyOverlay(PlacedObject placed)
        {
            int key = FarmGrid.Key(placed.X, placed.Y, _width);
            Transform overlay = Acquire(key);

            Vector3 centre = FarmGrid.TileCenter(placed.X, placed.Y, _width, _height);
            overlay.position = new Vector3(centre.x, _lift, centre.z);
            overlay.localScale = Vector3.one;
            overlay.localRotation = Quaternion.Euler(90f, 0f, 0f);

            string? cropId = PlacedIdPrefix.CropIdOf(placed.Id);

            if (cropId == null)
            {
                // Bare tilled soil. Water is the only other thing that shows here.
                SetMaterial(overlay, placed.Watered ? _wateredMaterial : _tilledMaterial);
                return;
            }

            bool ripe = _runner!.Content.TryGetCrop(cropId, out CropDef def)
                && placed.Stage >= def.MatureStage;

            SetMaterial(overlay, ripe ? _ripeMaterial : _cropMaterial);

            float stages = Mathf.Max(1, def?.MatureStage ?? 4);
            float growth = ripe ? 1f : Mathf.Clamp01(placed.Stage / stages);
            float height = Mathf.Lerp(_cropMaxHeight * 0.2f, _cropMaxHeight, growth);

            // Stand the crop up rather than laying it flat, so growth reads as
            // height from a top-down camera.
            overlay.localRotation = Quaternion.identity;
            overlay.localScale = new Vector3(0.8f, height, 0.8f);
            overlay.position = new Vector3(centre.x, height * 0.5f, centre.z);
        }

        private Transform Acquire(int key)
        {
            if (_overlays.TryGetValue(key, out Transform? existing))
            {
                existing.gameObject.SetActive(true);
                return existing;
            }

            Transform overlay = _pool.Count > 0
                ? _pool.Pop()
                : CreateOverlay();

            overlay.gameObject.SetActive(true);
            _overlays[key] = overlay;
            return overlay;
        }

        private Transform CreateOverlay()
        {
            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            go.name = "Tile";
            Object.Destroy(go.GetComponent<Collider>());
            go.transform.SetParent(transform, false);
            return go.transform;
        }

        private void Recycle(Transform overlay)
        {
            overlay.gameObject.SetActive(false);
            _pool.Push(overlay);
        }

        private static void SetMaterial(Transform overlay, Material? material)
        {
            if (material == null)
            {
                return;
            }

            Renderer renderer = overlay.GetComponent<Renderer>();

            if (renderer != null)
            {
                renderer.sharedMaterial = material;
            }
        }

        private void EnsureTargetMarker()
        {
            if (_target != null || _targetValidMaterial == null)
            {
                return;
            }

            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            go.name = "TargetTile";
            Object.Destroy(go.GetComponent<Collider>());
            go.transform.SetParent(transform, false);
            _target = go.transform;
            _target.localRotation = Quaternion.Euler(90f, 0f, 0f);
        }

        private void EnsurePuff()
        {
            if (_puff != null)
            {
                return;
            }

            GameObject go = GameObject.CreatePrimitive(PrimitiveType.Quad);
            go.name = "ToolPuff";
            Object.Destroy(go.GetComponent<Collider>());
            go.transform.SetParent(transform, false);
            _puff = go.transform;
            _puff.gameObject.SetActive(false);
        }

        /// <summary>
        /// Moves the tile highlight under the player and flashes the result of an
        /// action. Success and failure use different colours *and* different
        /// timings, so they cannot be confused at a glance or with the sound off.
        /// </summary>
        public void ShowTarget(WorldPos tile, bool valid)
        {
            EnsureTargetMarker();

            if (_target == null)
            {
                return;
            }

            Vector3 centre = FarmGrid.TileCenter(tile.X, tile.Y, _width, _height);
            _target.position = new Vector3(centre.x, _lift + 0.01f, centre.z);
            SetMaterial(_target, valid ? _targetValidMaterial : _targetInvalidMaterial);
        }

        public void ShowResult(WorldPos tile, ToolResult result)
        {
            EnsurePuff();

            if (_puff == null)
            {
                return;
            }

            Vector3 centre = FarmGrid.TileCenter(tile.X, tile.Y, _width, _height);
            _puff.position = new Vector3(centre.x, _lift + 0.02f, centre.z);
            _puff.localRotation = Quaternion.Euler(90f, 0f, 0f);
            _puff.localScale = Vector3.one * 0.9f;
            _puff.gameObject.SetActive(true);
            _puffUntil = Time.time + _puffSeconds;

            SetMaterial(
                _puff,
                result.Succeeded ? _targetValidMaterial : _targetInvalidMaterial);
        }

        private void Update()
        {
            if (_puff != null && _puff.gameObject.activeSelf && Time.time >= _puffUntil)
            {
                _puff.gameObject.SetActive(false);
            }
        }
    }
}
