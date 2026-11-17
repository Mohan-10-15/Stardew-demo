using System;
using System.Collections.Generic;
using System.Reflection;

namespace EmberCoreVerify
{
    /// <summary>
    /// Reflects over the pure EditMode test classes and runs their [Test]
    /// methods with the small NUnit shim in this folder. Unity's own test runner
    /// remains authoritative; this is the fallback when no Editor is installed.
    /// </summary>
    public static class Runner
    {
        public static int Main()
        {
            int passed = 0;
            int failed = 0;

            Assembly assembly = typeof(EmberHollow.Core.GameState).Assembly;
            foreach (Type type in assembly.GetTypes())
            {
                MethodInfo[] methods = type.GetMethods(BindingFlags.Public | BindingFlags.Instance);
                var tests = new List<MethodInfo>();
                var setups = new List<MethodInfo>();
                var teardowns = new List<MethodInfo>();
                foreach (MethodInfo method in methods)
                {
                    if (Attribute.IsDefined(method, typeof(NUnit.Framework.TestAttribute))) tests.Add(method);
                    if (Attribute.IsDefined(method, typeof(NUnit.Framework.SetUpAttribute))) setups.Add(method);
                    if (Attribute.IsDefined(method, typeof(NUnit.Framework.TearDownAttribute))) teardowns.Add(method);
                }

                if (tests.Count == 0)
                {
                    continue;
                }

                foreach (MethodInfo test in tests)
                {
                    object instance = Activator.CreateInstance(type)!;
                    string name = type.Name + "." + test.Name;
                    try
                    {
                        foreach (MethodInfo setup in setups) setup.Invoke(instance, null);
                        test.Invoke(instance, null);
                        foreach (MethodInfo teardown in teardowns) teardown.Invoke(instance, null);
                        passed++;
                        Console.WriteLine("PASS  " + name);
                    }
                    catch (TargetInvocationException ex)
                    {
                        failed++;
                        Console.WriteLine("FAIL  " + name + "  " + (ex.InnerException?.Message ?? ex.Message));
                    }
                }
            }

            Console.WriteLine($"RESULT: {passed} passed, {failed} failed");
            return failed == 0 && passed > 0 ? 0 : 1;
        }
    }
}
