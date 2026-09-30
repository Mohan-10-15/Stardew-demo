using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace EmberHollow.EditorTools
{
    /// <summary>
    /// Builds a native Windows player so the game can be launched as a real
    /// application, with a desktop shortcut's worth of window and input handling,
    /// rather than through a browser.
    ///
    /// Defaults to the Mono scripting backend: a Windows build is for local play
    /// and iteration, where a two-minute build beats an IL2CPP compile, and Mono
    /// keeps working when the IL2CPP toolchain is unhappy. Pass
    /// <c>-il2cpp</c> for a release build once the game is further along.
    /// </summary>
    public static class WindowsBuilder
    {
        private const string SceneRoot = "Assets/Scenes";
        private const string BuildRoot = "Builds/Windows";
        private const string ExecutableName = "EmberHollow.exe";

        public static void Build()
        {
            try
            {
                Run(UseIl2Cpp());
            }
            catch (Exception ex)
            {
                Debug.LogError($"[WindowsBuild] Unhandled exception: {ex}");
                EditorApplication.Exit(2);
            }
        }

        /// <summary>Release build: strips the editor and compiles to native code.</summary>
        public static void BuildRelease()
        {
            try
            {
                Run(true);
            }
            catch (Exception ex)
            {
                Debug.LogError($"[WindowsBuild] Unhandled exception: {ex}");
                EditorApplication.Exit(2);
            }
        }

        private static bool UseIl2Cpp()
        {
            return Array.IndexOf(Environment.GetCommandLineArgs(), "-il2cpp") >= 0;
        }

        private static void Run(bool il2cpp)
        {
            RegisterScenesIfMissing();

            string[] scenes = EditorBuildSettings.scenes
                .Where(s => s.enabled)
                .Select(s => s.path)
                .ToArray();

            if (scenes.Length == 0)
            {
                Debug.LogError("[WindowsBuild] No enabled scenes in Editor Build Settings.");
                EditorApplication.Exit(3);
                return;
            }

            string projectRoot = Directory.GetParent(Application.dataPath)!.FullName;
            string outputDir = Path.Combine(projectRoot, BuildRoot);
            Directory.CreateDirectory(outputDir);
            string exePath = Path.Combine(outputDir, ExecutableName);

            PlayerSettings.companyName = "Ember Hollow";
            PlayerSettings.productName = "Ember Hollow";
            PlayerSettings.defaultScreenWidth = 1280;
            PlayerSettings.defaultScreenHeight = 720;
            PlayerSettings.runInBackground = true;
            PlayerSettings.resizableWindow = true;
            PlayerSettings.fullScreenMode = FullScreenMode.Windowed;

            // Mono is a dev-build choice; IL2CPP is what a release needs.
            PlayerSettings.SetScriptingBackend(
                UnityEditor.Build.NamedBuildTarget.Standalone,
                il2cpp ? ScriptingImplementation.IL2CPP : ScriptingImplementation.Mono2x);

            Debug.Log($"[WindowsBuild] Target=StandaloneWindows64 Backend={(il2cpp ? "IL2CPP" : "Mono")} Output={exePath}");
            Debug.Log($"[WindowsBuild] Scenes={string.Join(", ", scenes)}");

            var options = new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = exePath,
                target = BuildTarget.StandaloneWindows64,
                targetGroup = BuildTargetGroup.Standalone,
                options = il2cpp ? BuildOptions.None : BuildOptions.Development
            };

            BuildReport report = BuildPipeline.BuildPlayer(options);
            BuildSummary summary = report.summary;

            Debug.Log(
                $"[WindowsBuild] RESULT={summary.result} Errors={summary.totalErrors} " +
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
            string[] paths = guids
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

            Debug.Log($"[WindowsBuild] Registered {paths.Length} scene(s) from {SceneRoot}.");
        }
    }
}
