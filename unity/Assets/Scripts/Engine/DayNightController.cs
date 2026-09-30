using UnityEngine;

namespace EmberHollow.Engine
{
    /// <summary>
    /// Reflects the in-game clock into the scene's lighting. Holds no rules: it
    /// is handed a normalised time of day and writes sun transform, colours,
    /// ambient and fog. T-0103 feeds it from <c>GameClock</c>.
    /// </summary>
    [ExecuteAlways]
    public sealed class DayNightController : MonoBehaviour
    {
        [Header("Scene references")]
        [SerializeField] private Light sun;
        [SerializeField] private Gradient sunColorOverDay;
        [SerializeField] private Gradient ambientColorOverDay;
        [SerializeField] private Gradient fogColorOverDay;
        [SerializeField] private Gradient ambientIntensityOverDay;

        [Header("Angles")]
        [SerializeField] private float startSunAngle = 15f;
        [SerializeField] private float endSunAngle = 195f;

        [Header("Weather")]
        [SerializeField, Range(0f, 1f)] private float overcast;
        [SerializeField, Range(0f, 1f)] private float rainIntensity;

        [Tooltip("0 = midnight, 0.5 = noon. Set by the clock; also editable for authoring.")]
        [SerializeField, Range(0f, 1f)] private float timeOfDay = 0.3f;

        public float TimeOfDay
        {
            get => timeOfDay;
            set => timeOfDay = Mathf.Repeat(value, 1f);
        }

        public float Overcast
        {
            get => overcast;
            set => overcast = Mathf.Clamp01(value);
        }

        public float RainIntensity
        {
            get => rainIntensity;
            set => rainIntensity = Mathf.Clamp01(value);
        }

        private void OnEnable()
        {
            EnsureGradients();
            Apply();
        }

        private void Update()
        {
            Apply();
        }

        private void OnValidate()
        {
            EnsureGradients();
            Apply();
        }

        public void Apply()
        {
            if (sun == null)
            {
                sun = FindSun();
            }

            float angle = Mathf.Lerp(startSunAngle, endSunAngle, timeOfDay);
            if (sun != null)
            {
                sun.transform.rotation = Quaternion.Euler(angle, 170f, 0f);

                Color color = sunColorOverDay.Evaluate(timeOfDay);
                sun.color = Color.Lerp(color, Color.gray, overcast * 0.7f);
                sun.intensity = Mathf.Lerp(ambientIntensityOverDay.Evaluate(timeOfDay).grayscale, 0.35f, overcast);
            }

            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = ambientColorOverDay.Evaluate(timeOfDay);
            RenderSettings.ambientEquatorColor = ambientColorOverDay.Evaluate(timeOfDay) * 0.8f;
            RenderSettings.ambientGroundColor = ambientColorOverDay.Evaluate(timeOfDay) * 0.55f;

            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogColor = Color.Lerp(fogColorOverDay.Evaluate(timeOfDay), Color.gray, overcast);
            RenderSettings.fogDensity = Mathf.Lerp(0.0016f, 0.0075f, Mathf.Max(overcast, rainIntensity));
        }

        private Light FindSun()
        {
            Light[] lights = FindObjectsByType<Light>(FindObjectsSortMode.None);
            foreach (Light light in lights)
            {
                if (light.type == LightType.Directional)
                {
                    return light;
                }
            }

            return null;
        }

        private void EnsureGradients()
        {
            if (sunColorOverDay == null || sunColorOverDay.colorKeys.Length == 0)
            {
                sunColorOverDay = new Gradient();
                sunColorOverDay.SetKeys(
                    new[]
                    {
                        new GradientColorKey(new Color(0.20f, 0.24f, 0.42f), 0f),
                        new GradientColorKey(new Color(0.98f, 0.72f, 0.48f), 0.28f),
                        new GradientColorKey(new Color(1.00f, 0.96f, 0.88f), 0.5f),
                        new GradientColorKey(new Color(0.92f, 0.52f, 0.32f), 0.75f),
                        new GradientColorKey(new Color(0.20f, 0.24f, 0.42f), 1f),
                    },
                    new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
            }

            if (ambientColorOverDay == null || ambientColorOverDay.colorKeys.Length == 0)
            {
                ambientColorOverDay = new Gradient();
                ambientColorOverDay.SetKeys(
                    new[]
                    {
                        new GradientColorKey(new Color(0.16f, 0.18f, 0.30f), 0f),
                        new GradientColorKey(new Color(0.46f, 0.50f, 0.60f), 0.3f),
                        new GradientColorKey(new Color(0.68f, 0.72f, 0.80f), 0.5f),
                        new GradientColorKey(new Color(0.40f, 0.38f, 0.44f), 0.78f),
                        new GradientColorKey(new Color(0.16f, 0.18f, 0.30f), 1f),
                    },
                    new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
            }

            if (fogColorOverDay == null || fogColorOverDay.colorKeys.Length == 0)
            {
                fogColorOverDay = new Gradient();
                fogColorOverDay.SetKeys(
                    new[]
                    {
                        new GradientColorKey(new Color(0.10f, 0.12f, 0.22f), 0f),
                        new GradientColorKey(new Color(0.70f, 0.78f, 0.86f), 0.42f),
                        new GradientColorKey(new Color(0.72f, 0.66f, 0.60f), 0.72f),
                        new GradientColorKey(new Color(0.10f, 0.12f, 0.22f), 1f),
                    },
                    new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
            }

            if (ambientIntensityOverDay == null || ambientIntensityOverDay.colorKeys.Length == 0)
            {
                ambientIntensityOverDay = new Gradient();
                ambientIntensityOverDay.SetKeys(
                    new[]
                    {
                        new GradientColorKey(Color.black, 0f),
                        new GradientColorKey(new Color(0.30f, 0.30f, 0.30f), 0.28f),
                        new GradientColorKey(Color.white, 0.5f),
                        new GradientColorKey(new Color(0.28f, 0.28f, 0.28f), 0.76f),
                        new GradientColorKey(Color.black, 1f),
                    },
                    new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(1f, 1f) });
            }
        }
    }
}
