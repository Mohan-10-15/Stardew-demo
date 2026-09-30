using UnityEngine;
using UnityEngine.InputSystem;

namespace EmberHollow.Engine
{
    /// <summary>
    /// Reads movement input and reflects it into a transform. This is a *view*
    /// concern: it owns no rules. Speed, stamina cost and collision resolution
    /// belong to the simulation; T-0103 wires <c>SimulationRunner</c> in as the
    /// authority for those and this component becomes a thin caller.
    ///
    /// Uses the Input System package, never the legacy Input Manager.
    /// </summary>
    [RequireComponent(typeof(Animator))]
    public sealed class PlayerMovementController : MonoBehaviour
    {
        [SerializeField] private float moveSpeed = 4.5f;
        [SerializeField] private float turnSpeed = 900f;
        [SerializeField] private float animatorDamp = 0.12f;

        private Animator _animator;
        private InputAction _move;
        private InputAction _sprint;
        private Vector3 _facing;
        private int _speedHash;
        private int _moveXHash;
        private int _moveZHash;

        public float MoveSpeed
        {
            get => moveSpeed;
            set => moveSpeed = Mathf.Max(0f, value);
        }

        /// <summary>The last resolved world-space move direction. Zero when idle.</summary>
        public Vector3 CurrentMoveDirection { get; private set; }

        public bool HasInput { get; private set; }

        private void Awake()
        {
            _animator = GetComponent<Animator>();
            _speedHash = Animator.StringToHash("Speed");
            _moveXHash = Animator.StringToHash("MoveX");
            _moveZHash = Animator.StringToHash("MoveZ");

            _move = new InputAction("Move", InputActionType.Value);
            _move.AddCompositeBinding("2DVector")
                .With("Up", "<Keyboard>/w")
                .With("Down", "<Keyboard>/s")
                .With("Left", "<Keyboard>/a")
                .With("Right", "<Keyboard>/d");
            _move.AddCompositeBinding("2DVector")
                .With("Up", "<Keyboard>/upArrow")
                .With("Down", "<Keyboard>/downArrow")
                .With("Left", "<Keyboard>/leftArrow")
                .With("Right", "<Keyboard>/rightArrow");
            _move.AddBinding("<Gamepad>/leftStick");

            _sprint = new InputAction("Sprint", InputActionType.Button, "<Keyboard>/leftShift");
            _sprint.AddBinding("<Gamepad>/rightStickPress");
        }

        private void OnEnable()
        {
            _move.Enable();
            _sprint.Enable();
        }

        private void OnDisable()
        {
            _move.Disable();
            _sprint.Disable();
        }

        private void Update()
        {
            Vector2 raw = _move.ReadValue<Vector2>();
            ApplyInput(raw, _sprint.IsPressed());
            FaceLastDirection(Time.deltaTime);
        }

        /// <summary>
        /// Resolves a raw input vector into movement. Exposed so a PlayMode test
        /// can drive all eight directions deterministically without synthesising
        /// device input.
        /// </summary>
        public void ApplyInput(Vector2 raw, bool sprinting)
        {
            Vector3 direction = new Vector3(raw.x, 0f, raw.y);

            if (direction.sqrMagnitude > 1f)
            {
                direction.Normalize();
            }

            HasInput = direction.sqrMagnitude > 0.0001f;
            CurrentMoveDirection = HasInput ? direction.normalized : Vector3.zero;

            float speed = moveSpeed * (sprinting ? 1.5f : 1f);
            transform.position += CurrentMoveDirection * (speed * Time.deltaTime);

            if (CurrentMoveDirection.sqrMagnitude > 0.0001f)
            {
                _facing = CurrentMoveDirection;
                FaceLastDirection(Time.deltaTime);
            }

            ReflectToAnimator();
        }

        /// <summary>
        /// Keeps turning toward the last heading while input is released, so the
        /// player settles facing where they walked rather than where the mouse
        /// happened to stop.
        /// </summary>
        private void FaceLastDirection(float deltaTime)
        {
            if (_facing.sqrMagnitude <= 0.0001f || deltaTime <= 0f)
            {
                return;
            }

            Quaternion target = Quaternion.LookRotation(_facing, Vector3.up);
            transform.rotation = Quaternion.RotateTowards(
                transform.rotation, target, turnSpeed * deltaTime);
        }

        private void ReflectToAnimator()
        {
            if (_animator == null || _animator.runtimeAnimatorController == null)
            {
                return;
            }

            // Relative to facing, so forward is +Z and strafe is +/-X.
            Vector3 local = transform.InverseTransformDirection(CurrentMoveDirection);
            float speed = CurrentMoveDirection.magnitude * SpeedFactor();

            _animator.SetFloat(_speedHash, speed, animatorDamp, Time.deltaTime);
            _animator.SetFloat(_moveXHash, local.x, animatorDamp, Time.deltaTime);
            _animator.SetFloat(_moveZHash, local.z, animatorDamp, Time.deltaTime);
        }

        private float SpeedFactor()
        {
            return moveSpeed <= 0.0001f ? 1f : moveSpeed;
        }
    }
}
