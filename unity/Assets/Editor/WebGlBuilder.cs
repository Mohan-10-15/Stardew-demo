using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace EmberHollow.EditorTools
{
    public static class WebGlBuilder
    {
        private const string SceneRoot = "Assets/Scenes";
        private const string BuildRoot = "Builds/WebGL";

        public static void Build()
        {
            try
            {
                Run();
            }
            catch (Exception ex)
            {
                Debug.LogError($"[WebGLBuild] Unhandled exception: {ex}");
                EditorApplication.Exit(2);
            }
        }

        private static void Run()
        {
            RegisterScenesIfMissing();

            var scenes = EditorBuildSettings.scenes
                .Where(s => s.enabled)
                .Select(s => s.path)
                .ToArray();

            if (scenes.Length == 0)
            {
                Debug.LogError("[WebGLBuild] No enabled scenes in Editor Build Settings.");
                EditorApplication.Exit(3);
                return;
            }

            string projectRoot = Directory.GetParent(Application.dataPath)!.FullName;
            string outputDir = Path.Combine(projectRoot, BuildRoot);
            Directory.CreateDirectory(outputDir);

            Debug.Log($"[WebGLBuild] Target={BuildTarget.WebGL} Output={outputDir}");
            Debug.Log($"[WebGLBuild] Scenes={string.Join(", ", scenes)}");

            var options = new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = outputDir,
                target = BuildTarget.WebGL,
                targetGroup = BuildTargetGroup.WebGL,
                options = BuildOptions.None
            };

            BuildReport report = BuildPipeline.BuildPlayer(options);
            BuildSummary summary = report.summary;

            Debug.Log(
                $"[WebGLBuild] RESULT={summary.result} Errors={summary.totalErrors} " +
                $"Warnings={summary.totalWarnings} SizeBytes={summary.totalSize} " +
                $"DurationSeconds={summary.totalTime.TotalSeconds:F1} Output={summary.outputPath}");

            int exitCode = summary.result == BuildResult.Succeeded && summary.totalErrors == 0 ? 0 : 1;
            EditorApplication.Exit(exitCode);
        }

        private static void RegisterScenesIfMissing()
        {
            if (EditorBuildSettings.scenes.Any(s => s.enabled))
            {
                return;
            }

            if (!AssetDatabase.IsValidFolder(SceneRoot))
            {
                return;
            }

            string[] guids = AssetDatabase.FindAssets("t:Scene", new[] { SceneRoot });
            var paths = guids
                .Select(AssetDatabase.GUIDToAssetPath)
                .OrderBy(p => p, StringComparer.Ordinal)
                .ToArray();

            if (paths.Length == 0)
            {
                return;
            }

            EditorBuildSettings.scenes = paths
                .Select(p => new EditorBuildSettingsScene(p, true))
                .ToArray();

            Debug.Log($"[WebGLBuild] Registered {paths.Length} scene(s) from {SceneRoot}.");
        }
    }
}
