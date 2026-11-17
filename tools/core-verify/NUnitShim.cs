// Minimal stand-ins for the NUnit surface used by the pure EditMode tests, so
// the same test files can run against the engine-free Core outside a Unity
// install. This is a verification tool, not a replacement for the real
// Unity Test Framework tier.
using System;
using System.Collections;

namespace NUnit.Framework
{
    [AttributeUsage(AttributeTargets.Method)]
    public sealed class TestAttribute : Attribute
    {
    }

    [AttributeUsage(AttributeTargets.Method)]
    public sealed class SetUpAttribute : Attribute
    {
    }

    [AttributeUsage(AttributeTargets.Method)]
    public sealed class TearDownAttribute : Attribute
    {
    }

    [AttributeUsage(AttributeTargets.Class)]
    public sealed class TestFixtureAttribute : Attribute
    {
    }

    public static class CollectionAssert
    {
        public static void AreEqual(IEnumerable expected, IEnumerable actual, string? message = null)
        {
            var left = new System.Collections.Generic.List<object?>();
            var right = new System.Collections.Generic.List<object?>();
            foreach (object? item in expected) left.Add(item);
            foreach (object? item in actual) right.Add(item);
            Assert.AreEqual(left.Count, right.Count, message);
            for (int i = 0; i < left.Count; i++)
            {
                Assert.AreEqual(left[i], right[i], message);
            }
        }
    }

    public static class Assert
    {
        public static void AreEqual(object? expected, object? actual, string? message = null)
        {
            if (!object.Equals(expected, actual))
            {
                Fail($"Expected <{expected ?? "null"}> but was <{actual ?? "null"}>", message);
            }
        }

        public static void AreEqual(double expected, double actual, double tolerance, string? message = null)
        {
            if (Math.Abs(expected - actual) > tolerance)
            {
                Fail($"Expected <{expected}> within <{tolerance}> but was <{actual}>", message);
            }
        }

        public static void AreNotEqual(object? expected, object? actual, string? message = null)
        {
            if (object.Equals(expected, actual))
            {
                Fail($"Expected values to differ: <{expected ?? "null"}>", message);
            }
        }

        public static void AreSame(object? expected, object? actual, string? message = null)
        {
            if (!ReferenceEquals(expected, actual))
            {
                Fail("Expected the same instance", message);
            }
        }

        public static void IsTrue(bool condition, string? message = null)
        {
            if (!condition) Fail("Expected true", message);
        }

        public static void IsFalse(bool condition, string? message = null)
        {
            if (condition) Fail("Expected false", message);
        }

        public static void IsNull(object? value, string? message = null)
        {
            if (value != null) Fail("Expected null", message);
        }

        public static void IsNotNull(object? value, string? message = null)
        {
            if (value == null) Fail("Expected non-null", message);
        }

        public static void Greater(object? actual, object? lower, string? message = null)
        {
            if (Comparer.DefaultInvariant.Compare(actual, lower) <= 0)
            {
                Fail($"Expected <{actual}> to be greater than <{lower}>", message);
            }
        }

        public static void GreaterOrEqual(object? actual, object? lower, string? message = null)
        {
            if (Comparer.DefaultInvariant.Compare(actual, lower) < 0)
            {
                Fail($"Expected <{actual}> >= <{lower}>", message);
            }
        }

        public static void Less(object? actual, object? upper, string? message = null)
        {
            if (Comparer.DefaultInvariant.Compare(actual, upper) >= 0)
            {
                Fail($"Expected <{actual}> to be less than <{upper}>", message);
            }
        }

        public static void LessOrEqual(object? actual, object? upper, string? message = null)
        {
            if (Comparer.DefaultInvariant.Compare(actual, upper) > 0)
            {
                Fail($"Expected <{actual}> <= <{upper}>", message);
            }
        }

        public static void DoesNotThrow(Action action, string? message = null)
        {
            try
            {
                action();
            }
            catch (Exception ex)
            {
                Fail($"Unexpected {ex.GetType().Name}", message);
            }
        }

        public static T Throws<T>(Action action, string? message = null) where T : Exception
        {
            try
            {
                action();
            }
            catch (T expected)
            {
                return expected;
            }
            catch (Exception ex)
            {
                Fail($"Expected {typeof(T).Name} but got {ex.GetType().Name}", message);
            }

            Fail($"Expected {typeof(T).Name} but nothing was thrown", message);
            return default!;
        }

        public static void Fail(string message, string? detail = null)
        {
            throw new Exception(message + (detail == null ? string.Empty : ": " + detail));
        }
    }
}
