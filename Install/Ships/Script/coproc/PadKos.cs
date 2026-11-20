// the bridge between kOS's structures and the pad search's plain C# (KLex). From: on the main thread, the whole input
// copied (a Lexicon / List / Vector / Scalar / Boolean / String tree; anything else, or a number not finite, throws before
// any work starts). To: the results as fresh kOS structures (ints stay ScalarIntValue, the rest ScalarDoubleValue), built on
// the main thread when kOS asks for them.
using System;
using System.Collections.Generic;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public static class PadKos
    {
        public static object From(Structure s, string at)
        {
            var lx = s as Lexicon;
            if (lx != null)
            {
                var k = new KLex();
                foreach (Structure key in lx.Keys) k[key.ToString()] = From(lx[key], at + "." + key);
                return k;
            }
            var li = s as ListValue;
            if (li != null)
            {
                var l = new List<object>();
                int i = 0;
                foreach (Structure x in li) { l.Add(From(x, at + "[" + i + "]")); i++; }
                return l;
            }
            var ve = s as kOS.Suffixed.Vector;
            if (ve != null)
            {
                if (!Fin(ve.X) || !Fin(ve.Y) || !Fin(ve.Z)) throw new ArithmeticException(at + " is not finite");
                return new Vec3(ve.X, ve.Y, ve.Z);
            }
            if (s is ScalarIntValue) return ((ScalarIntValue)s).GetIntValue();
            var sc = s as ScalarValue;
            if (sc != null)
            {
                double d = sc.GetDoubleValue();
                if (!Fin(d)) throw new ArithmeticException(at + " is not finite");
                return d;
            }
            if (s is BooleanValue) return ((BooleanValue)s).Value;
            if (s is StringValue) return s.ToString();
            throw new InvalidCastException(at + ": a " + (s == null ? "null" : s.GetType().Name) + " is not passed");
        }

        static bool Fin(double d) { return !double.IsNaN(d) && !double.IsInfinity(d); }

        public static Structure To(object o)
        {
            var k = o as KLex;
            if (k != null)
            {
                var lx = new Lexicon();
                foreach (var key in k.Keys) lx[new StringValue(key)] = To(k[key]);
                return lx;
            }
            var l = o as List<object>;
            if (l != null)
            {
                var li = new ListValue();
                foreach (var x in l) li.Add(To(x));
                return li;
            }
            if (o is Vec3) { var v = (Vec3)o; return new kOS.Suffixed.Vector(v.X, v.Y, v.Z); }
            if (o is int) return new ScalarIntValue((int)o);
            if (o is double) return new ScalarDoubleValue((double)o);
            if (o is bool) return new BooleanValue((bool)o);
            if (o is string) return new StringValue((string)o);
            throw new InvalidCastException("a " + (o == null ? "null" : o.GetType().Name) + " has no kOS form");
        }
    }
}
