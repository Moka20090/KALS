// the ascent PEG pass as a SYNCHRONOUS suffix of ADDONS:KALS (a partial of KalsAddon: RegisterPeg is called from
// its constructor). lib_ascent_peg.ks's asc_peg_cycle hands every pass here:
//     ADDONS:KALS:PEGSETUP(LEXICON("ASC_DTMAX", .., "ASC_DTMIN", .., "ASC_NSEG", .., "ASC_AL", .., "ASC_ETB", .., "ASC_KMISS", ..,
//         "ASC_RHOMAG", .., "ASC_PHIDOT_MAX", .., "ASC_RTLS_PHIDOT_MAX", .., "ASC_EPSTGO", .., "ASC_DTRD", ..))   -> TRUE
//     ADDONS:KALS:PEGCYCLE(p, LIST(t, rr, vv, dvs, M, VEX, ATR))   -> "" (p updated in place) or "error ..." (p untouched)
//     PEGHOLD -> TRUE: this PEG knows the TAL lexicon's "hold" / "iyef" keys (the delayed TAL's surface-plane hold);
//     lib_ascent_peg.ks hands the hold's passes to kOS when the addon has no PEGHOLD (an older DLL).
// PEGSETUP is its own (KalsAddon's SETUP needs the whole fast-time table set and only runs when the abort search starts,
// well after stage 2's first passes); the statics it sets are Peg's, which the fast-time flights (Fts.cs) read too, with
// the same values. None of the suffixes throws into kOS.
using System;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;

namespace KalsCoproc
{
    public partial class KalsAddon
    {
        bool pegReady;
        string pegErr = "";

        partial void RegisterPeg()
        {
            AddSuffix("PEGSETUP", new OneArgsSuffix<BooleanValue, Lexicon>(PegSetup));
            AddSuffix("PEGREADY", new Suffix<BooleanValue>(() => pegReady));
            AddSuffix("PEGERROR", new Suffix<StringValue>(() => pegErr));
            AddSuffix("PEGCYCLE", new TwoArgsSuffix<StringValue, Lexicon, ListValue>(PegCycle));
            AddSuffix("PEGHOLD", new Suffix<BooleanValue>(() => true));   // this PEG flies the hidden TAL's hold (TalSite.Hold / Iyef)
        }

        static double PgD(Lexicon l, string k)
        {
            Structure s;
            if (!l.TryGetValue(new StringValue(k), out s)) throw new System.Collections.Generic.KeyNotFoundException(k + " missing");
            var sv = s as ScalarValue;
            if (sv == null) throw new InvalidCastException(k + " is not a number");
            double d = sv.GetDoubleValue();
            if (double.IsNaN(d) || double.IsInfinity(d)) throw new ArithmeticException(k + " is not finite");
            return d;
        }

        // the I-loads Peg.cs reads (all read first, then set: a missing one leaves the statics as they were)
        BooleanValue PegSetup(Lexicon l)
        {
            try
            {
                double dtmax = PgD(l, "ASC_DTMAX"), dtmin = PgD(l, "ASC_DTMIN"), nseg = PgD(l, "ASC_NSEG"), al = PgD(l, "ASC_AL"),
                    etb = PgD(l, "ASC_ETB"), kmiss = PgD(l, "ASC_KMISS"), rhomag = PgD(l, "ASC_RHOMAG"),
                    phidot = PgD(l, "ASC_PHIDOT_MAX"), rtphi = PgD(l, "ASC_RTLS_PHIDOT_MAX"), epstgo = PgD(l, "ASC_EPSTGO"),
                    dtrd = PgD(l, "ASC_DTRD");
                Peg.DTMAX = dtmax; Peg.DTMIN = dtmin; Peg.NSEG = nseg; Peg.AL = al; Peg.ETB = etb; Peg.KMISS = kmiss;
                Peg.RHOMAG = rhomag; Peg.PHIDOT_MAX = phidot; Peg.RTLS_PHIDOT_MAX = rtphi; Peg.EPSTGO = epstgo; Peg.DTRD = dtrd;
                pegReady = true;
                pegErr = "";
                return BooleanValue.True;
            }
            catch (Exception ex) { pegReady = false; pegErr = ex.GetType().Name + ": " + ex.Message; return BooleanValue.False; }
        }

        StringValue PegCycle(Lexicon p, ListValue a)
        {
            try
            {
                if (!pegReady) return new StringValue("PEGSETUP first (" + pegErr + ")");
                PegKos.Cycle(p, a);
                return new StringValue("");
            }
            catch (Exception ex) { pegErr = ex.GetType().Name + ": " + ex.Message; return new StringValue("error " + pegErr); }
        }

    }
}
