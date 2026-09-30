using UnityEngine;
using UnityEngine.InputSystem;

namespace EmberHollow.Engine.Movement
{
    /// <summary>
    /// Third-person movement view/controller. It reads input, hands the numbers
    /// to <see cref="MovementMath"/>, and reflects the result into the
    /// CharacterController, the visual facing and the Animator parameters.
    /// There is no gameplay rule here: nothing decides what the player is
    /// allowed to do, only where they end up this frame.
    ///
    /// The rig is split so the Cinemachine follow target never spins with the
    /// character: the root transform keeps the fixed camera heading, and a child
    /// "Visual" carries the KayKit model and turns to face travel. That means
    /// the camera reads the root's rotation and the Animator reads the visual's,
    /// which is what lets one 2D blend tree cover all eight directions.
    /// </summary>
    [DisallowMultipleComponent]
    [RequireComponent(typeof(CharacterController))]
    public sealed class PlayerMovement : MonoBehaviour
    {
        /// <summary>
        /// Yaw the follow camera sits at. Shared with the camera rig so the two
        /// halves of the rig cannot disagree about which way "forward" is.
        /// </summary>
        public const float CameraYawDegrees = 40f;

        private const string MoveKeyboardAction = "MoveKeyboard";
        private const string MoveArrowsAction = "MoveArrows";
        private const string MovePadAction = "MovePad";
        private const string MoveXParameter = "MoveX";
        private const string MoveZParameter = "MoveZ";
        private const string SpeedParameter = "Speed";
        private const string IsMovingParameter = "IsMoving";

        [Header("Rig")]
        [SerializeField] private CharacterController controller;
        [SerializeField] private Transform visual;
        [SerializeField] private Animator animator;

        [Header("Tuning")]
        [SerializeField] private float moveSpeed = 4.4f;
        [SerializeField] private float acceleration = 26f;
        [SerializeField] private float turnDegreesPerSecond = 900f;
        [SerializeField] private float gravity = -22f;
        [SerializeField] private float groundedStick = -2f;

        [Header("Input")]
        [Tooltip("Optional. When empty a WASD / arrow / left-stick map is built in code. " +
                 "WORKER-3's shared .inputactions asset should be assigned here once it exists.")]
        [SerializeField] private InputActionAsset inputActions;

        private InputActionMap ownedMap;
        private InputAction keyboardAction;
        private InputAction arrowsAction;
        private InputAction padAction;

        private Vector2 injectedInput;
        private bool injected = false;
        private Vector3 velocity;
        private float visualBaseYaw;
        private bool animatorHasMoveX;
        private bool animatorHasMoveZ;
        private bool animatorHasSpeed;
        private bool animatorHasIsMoving;

        /// <summary>World-space ground velocity in metres per second.</summary>
        public Vector3 Velocity => velocity;

        /// <summary>Planar speed in metres per second.</summary>
        public float Speed => MovementMath.Length(velocity.x, velocity.z);

        /// <summary>True when no stick or key is being held.</summary>
        public bool IsIdle => Speed <= MovementMath.Epsilon;

        /// <summary>The character model that turns to face travel.</summary>
        public Transform Visual => visual;

        /// <summary>Fixed heading the follow camera is built around.</summary>
        public float CameraYaw => CameraYawDegrees;

        private void Reset()
        {
            controller = GetComponent<CharacterController>();
            if (animator == null)
            {
                animator = GetComponentInChildren<Animator>(true);
            }
        }

        private void Awake()
        {
            if (controller == null)
            {
                controller = GetComponent<CharacterController>();
            }

            if (animator == null)
            {
                animator = GetComponentInChildren<Animator>(true);
            }

            visualBaseYaw = visual == null ? 0f : visual.localEulerAngles.y;
            CacheAnimatorParameters();
            BuildInputIfNeeded();
            ApplyFacingHeading();
        }

        private void OnEnable()
        {
            EnableActions(true);
        }

        private void OnDisable()
        {
            EnableActions(false);
        }

        private void OnDestroy()
        {
            ownedMap?.Dispose();
        }

        /// <summary>
        /// Drive movement without a device. The PlayMode suite and the M8 bot
        /// both need to walk the farmer without a human at the keyboard, and
        /// T-0103's SimulationRunner can push simulation intent in the same way.
        /// </summary>
        public void SetMoveInput(Vector2 value)
        {
            injectedInput = Vector2.ClampMagnitude(value, 1f);
            injected = true;
        }

        /// <summary>Go back to reading the Input System.</summary>
        public void ClearInjectedInput()
        {
            injectedInput = Vector2.zero;
            injected = false;
        }

        /// <summary>The last direction handed to <see cref="MovementMath"/>, for tests and debugging.</summary>
        public Vector2 LastWorldDirection { get; private set; }

        private void Update()
        {
            float dt = Time.deltaTime;
            if (dt <= 0f)
            {
                return;
            }

            Vector2 stick = injected ? injectedInput : ReadDeviceInput();
            MovementMath.RotateYaw(stick.x, stick.y, CameraYawDegrees, out float dirX, out float dirZ);
            MovementMath.ClampLength(dirX, dirZ, 1f, out dirX, out dirZ);
            LastWorldDirection = new Vector2(dirX, dirZ);

            float targetSpeed = moveSpeed * MovementMath.Length(dirX, dirZ);
            float maxDelta = acceleration * dt;
            velocity.x = MovementMath.MoveTowards(velocity.x, dirX * moveSpeed, maxDelta);
            velocity.z = MovementMath.MoveTowards(velocity.z, dirZ * moveSpeed, maxDelta);

            if (controller.isGrounded && velocity.y < groundedStick)
            {
                velocity.y = groundedStick;
            }

            velocity.y += gravity * dt;

            controller.Move(velocity * dt);

            ApplyFacing(dt);
            ApplyAnimatorParams(dirX, dirZ);
        }

        private void ApplyFacing(float dt)
        {
            if (visual == null)
            {
                return;
            }

            float planarSpeed = MovementMath.Length(velocity.x, velocity.z);
            float currentLocal = MovementMath.Wrap180(visual.localEulerAngles.y - visualBaseYaw);
            float targetLocal = planarSpeed <= MovementMath.Epsilon
                ? currentLocal
                : MovementMath.Wrap180(MovementMath.FacingYaw(velocity.x, velocity.z, 0f) - CameraYawDegrees);

            float next = MovementMath.MoveTowardsAngle(currentLocal, targetLocal, turnDegreesPerSecond * dt);
            visual.localRotation = Quaternion.Euler(0f, visualBaseYaw + next, 0f);
        }

        private void ApplyAnimatorParams(float worldDirX, float worldDirZ)
        {
            if (animator == null)
            {
                return;
            }

            Vector3 world = new Vector3(worldDirX, 0f, worldDirZ);
            Vector3 local = visual == null ? world : visual.InverseTransformDirection(world);
            float speed01 = MovementMath.Clamp(MovementMath.Length(worldDirX, worldDirZ), 0f, 1f);

            if (animatorHasMoveX)
            {
                animator.SetFloat(MoveXParameter, local.x);
            }

            if (animatorHasMoveZ)
            {
                animator.SetFloat(MoveZParameter, local.z);
            }

            if (animatorHasSpeed)
            {
                animator.SetFloat(SpeedParameter, speed01);
            }

            if (animatorHasIsMoving)
            {
                animator.SetBool(IsMovingParameter, speed01 > MovementMath.Epsilon);
            }
        }

        private void ApplyFacingHeading()
        {
            transform.rotation = Quaternion.Euler(0f, CameraYawDegrees, 0f);
        }

        private Vector2 ReadDeviceInput()
        {
            Vector2 value = Vector2.zero;
            if (keyboardAction != null && keyboardAction.enabled)
            {
                value += keyboardAction.ReadValue<Vector2>();
            }

            if (arrowsAction != null && arrowsAction.enabled)
            {
                value += arrowsAction.ReadValue<Vector2>();
            }

            if (padAction != null && padAction.enabled)
            {
                value += padAction.ReadValue<Vector2>();
            }

            return Vector2.ClampMagnitude(value, 1f);
        }

        private void EnableActions(bool enable)
        {
            if (enable)
            {
                keyboardAction?.Enable();
                arrowsAction?.Enable();
                padAction?.Enable();
                return;
            }

            keyboardAction?.Disable();
            arrowsAction?.Disable();
            padAction?.Disable();
        }

        private void BuildInputIfNeeded()
        {
            if (inputActions != null)
            {
                keyboardAction = inputActions.FindAction(MoveKeyboardAction, false);
                arrowsAction = inputActions.FindAction(MoveArrowsAction, false);
                padAction = inputActions.FindAction(MovePadAction, false);
                return;
            }

            ownedMap = new InputActionMap("FarmMovement");

            keyboardAction = ownedMap.AddAction(MoveKeyboardAction, InputActionType.Value, expectedControlLayout: "Vector2");
            keyboardAction.AddCompositeBinding("2DVector")
                .With("Up", "<Keyboard>/w")
                .With("Down", "<Keyboard>/s")
                .With("Left", "<Keyboard>/a")
                .With("Right", "<Keyboard>/d");

            arrowsAction = ownedMap.AddAction(MoveArrowsAction, InputActionType.Value, expectedControlLayout: "Vector2");
            arrowsAction.AddCompositeBinding("2DVector")
                .With("Up", "<Keyboard>/upArrow")
                .With("Down", "<Keyboard>/downArrow")
                .With("Left", "<Keyboard>/leftArrow")
                .With("Right", "<Keyboard>/rightArrow");

            padAction = ownedMap.AddAction(MovePadAction, InputActionType.Value, "<Gamepad>/leftStick");
        }

        private void CacheAnimatorParameters()
        {
            animatorHasMoveX = false;
            animatorHasMoveZ = false;
            animatorHasSpeed = false;
            animatorHasIsMoving = false;
            if (animator == null || animator.runtimeAnimatorController == null)
            {
                return;
            }

            foreach (AnimatorControllerParameter parameter in animator.parameters)
            {
                switch (parameter.name)
                {
                    case MoveXParameter:
                        animatorHasMoveX = true;
                        break;
                    case MoveZParameter:
                        animatorHasMoveZ = true;
                        break;
                    case SpeedParameter:
                        animatorHasSpeed = true;
                        break;
                    case IsMovingParameter:
                        animatorHasIsMoving = true;
                        break;
                }
            }
        }
    }
}
