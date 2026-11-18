using System.Diagnostics;
using System.IO;

// A tiny double-clickable front door for the portable Godot build. The game
// itself is Godot/GDScript; this executable only finds the bundled engine and
// starts it with the right arguments, so a player never opens a terminal.

var exeDir = AppContext.BaseDirectory;
var root = new DirectoryInfo(exeDir);
while (root != null && !File.Exists(Path.Combine(root.FullName, "project.godot")))
    root = root.Parent;

if (root == null)
{
    Console.Error.WriteLine("Could not find the game folder (project.godot).");
    Console.Error.WriteLine("Keep Hollowbrook.exe inside the game folder.");
    Console.Error.WriteLine("Press any key to close.");
    Console.ReadKey();
    return 1;
}

var godot = Path.Combine(root.FullName, "tools", "Godot_v4.5-stable_win64_console.exe");
if (!File.Exists(godot))
{
    Console.Error.WriteLine($"Missing engine: {godot}");
    Console.Error.WriteLine("Press any key to close.");
    Console.ReadKey();
    return 1;
}

var start = new ProcessStartInfo
{
    FileName = godot,
    WorkingDirectory = root.FullName,
    UseShellExecute = false
};
// ArgumentList keeps the space in "Stardew dmeo" intact without hand-quoting,
// which Start-Process/ProcessStartInfo otherwise mangle on Windows.
start.ArgumentList.Add("--path");
start.ArgumentList.Add(root.FullName);
start.ArgumentList.Add("--rendering-driver");
start.ArgumentList.Add("opengl3");

try
{
    using var process = Process.Start(start);
    if (process == null)
    {
        Console.Error.WriteLine("Could not start Godot.");
        Console.ReadKey();
        return 1;
    }
    process.WaitForExit();
    return process.ExitCode;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Could not start the game: {ex.Message}");
    Console.Error.WriteLine("Press any key to close.");
    Console.ReadKey();
    return 1;
}
