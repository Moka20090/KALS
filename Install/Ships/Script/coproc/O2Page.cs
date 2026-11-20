// ops2q's page model in C#: lib_o2ui.ks o2PgNew / o2Seg / o2Fld / o2Num / o2Choice / o2Drop / o2Act / o2Read
// as one class, so a C# page builder (O2Mnvr.cs ...) fills the same rows and cursor stops the kOS builders do, in the same
// order (the draw sorts a row's segments by column, insertion after the equal ones: the order of calls matters).
//   O2Page.ToKos()  -> the LEXICON(seg, fld) lib_o2ui builds (what o2Key / o2Find / o2StepTxt and OdHost.Draw read);
//   O2Page.Dump()   -> a canonical text of the page, for the offline tests (kOS's page dumped the same way must be identical).
// Nothing here throws into kOS; a builder that fails is the caller's to catch (it falls back to the kOS builder).
using System;
using System.Collections.Generic;
using System.Text;
using kOS.Safe.Encapsulation;

namespace KalsCoproc
{
    public class O2Seg { public int Row, Col; public string Txt, Cls; }

    public class O2Fld
    {
        public string Id, Kind, Txt;
        public int Row, Col;
        public bool On;
        // a choice ("C"): n options, the dim indices, the options' (column, word), the per-option refusal texts; a drop-down: words + Drop
        public bool IsChoice, Drop;
        public int N;
        public List<int> Dim = new List<int>();
        public List<KeyValuePair<int, string>> Items = new List<KeyValuePair<int, string>>();
        public List<string> Why = new List<string>();
        public List<string> Words = new List<string>();
    }

    public class O2Page
    {
        public readonly List<O2Seg> Segs = new List<O2Seg>();
        public readonly List<O2Fld> Flds = new List<O2Fld>();

        // o2Seg: fixed text at (row, col) in colour class cls ("" text adds nothing)
        public void Seg(int row, int col, string txt, string cls = "L")
        {
            if (txt != "") Segs.Add(new O2Seg { Row = row, Col = col, Txt = txt, Cls = cls });
        }

        // o2Fld: a cursor stop
        public O2Fld Fld(string id, string kind, int row, int col, string txt, bool on)
        {
            var f = new O2Fld { Id = id, Kind = kind, Row = row, Col = col, Txt = txt, On = on };
            Flds.Add(f);
            return f;
        }

        // o2Num: an editable number / time (kind "N" / "T" from o2Spec), txt = its shown text
        public void Num(string id, string kind, int row, int col, string txt, bool on = true)
        {
            Seg(row, col, txt, on ? "V" : "D");
            Fld(id, kind, row, col, txt, on);
        }

        // o2Choice: words at their columns (col, word); k = o2Val[id], the selected index (ROUND of it)
        public void Choice(string id, int k, int row, IList<KeyValuePair<int, string>> items, bool on, IList<int> dim = null, IList<string> why = null)
        {
            for (int i = 0; i < items.Count; i++)
            {
                string cl = "L";
                if (i == k) cl = "S";
                if ((dim != null && dim.Contains(i)) || !on) cl = "D";
                Seg(row, items[i].Key, items[i].Value, cl);
            }
            if (k >= 0 && k < items.Count)
            {
                var f = Fld(id, "C", row, items[k].Key, items[k].Value, on);
                f.IsChoice = true; f.N = items.Count;
                if (dim != null) f.Dim.AddRange(dim);
                f.Items.AddRange(items);
                if (why != null) f.Why.AddRange(why);
            }
        }

        // o2Drop: the selected word at (row, col), ENT opens a drop-down list of words (dim = indices not available)
        public void DropDown(string id, int row, int col, string txt, IList<string> words, bool on = true, IList<int> dim = null)
        {
            Seg(row, col, txt, on ? "V" : "D");
            var f = Fld(id, "C", row, col, txt, on);
            f.N = words.Count; f.Drop = true;
            if (dim != null) f.Dim.AddRange(dim);
            f.Words.AddRange(words);
        }

        // o2Act: an action word; on = FALSE draws it dim, ENT refused
        public void Act(string id, int row, int col, string txt, bool on = true)
        {
            Seg(row, col, txt, on ? "L" : "D");
            Fld(id, "A", row, col, txt, on);
        }

        // o2Read: a live value the cursor never visits
        public void Read(int row, int col, string txt, string cls = "V") { Seg(row, col, txt, cls); }

        // the last segment's class (a builder's "armed: the brightest class" tweak)
        public void SetLastCls(string cls) { if (Segs.Count > 0) Segs[Segs.Count - 1].Cls = cls; }

        // ---- the kOS side
        static StringValue Sv(string s) { return new StringValue(s); }
        static ScalarValue Nv(double x) { return ScalarValue.Create(x); }

        public Lexicon ToKos()
        {
            var seg = new ListValue();
            foreach (var s in Segs)
            {
                var l = new ListValue();
                l.Add(Nv(s.Row)); l.Add(Nv(s.Col)); l.Add(Sv(s.Txt)); l.Add(Sv(s.Cls));
                seg.Add(l);
            }
            var fld = new ListValue();
            foreach (var f in Flds)
            {
                var d = new Lexicon();
                d[Sv("id")] = Sv(f.Id); d[Sv("kind")] = Sv(f.Kind); d[Sv("row")] = Nv(f.Row); d[Sv("col")] = Nv(f.Col);
                d[Sv("txt")] = Sv(f.Txt); d[Sv("on")] = f.On ? BooleanValue.True : BooleanValue.False;
                if (f.IsChoice)
                {
                    d[Sv("n")] = Nv(f.N);
                    var dm = new ListValue(); foreach (var i in f.Dim) dm.Add(Nv(i));
                    d[Sv("dim")] = dm;
                    var it = new ListValue();
                    foreach (var kv in f.Items) { var p = new ListValue(); p.Add(Nv(kv.Key)); p.Add(Sv(kv.Value)); it.Add(p); }
                    d[Sv("items")] = it;
                    var wy = new ListValue(); foreach (var w in f.Why) wy.Add(Sv(w));
                    d[Sv("why")] = wy;
                }
                else if (f.Drop)
                {
                    d[Sv("n")] = Nv(f.N);
                    var dm = new ListValue(); foreach (var i in f.Dim) dm.Add(Nv(i));
                    d[Sv("dim")] = dm;
                    var wl = new ListValue(); foreach (var w in f.Words) wl.Add(Sv(w));
                    d[Sv("words")] = wl; d[Sv("drop")] = BooleanValue.True;
                }
                fld.Add(d);
            }
            var pg = new Lexicon();
            pg[Sv("seg")] = seg; pg[Sv("fld")] = fld;
            return pg;
        }

        // ---- the canonical text (for the offline tests)
        public string Dump()
        {
            var b = new StringBuilder();
            foreach (var s in Segs) b.Append("S ").Append(s.Row).Append(' ').Append(s.Col).Append(' ').Append(s.Cls).Append(" |").Append(s.Txt).Append("|\n");
            foreach (var f in Flds)
            {
                b.Append("F ").Append(f.Id).Append(' ').Append(f.Kind).Append(' ').Append(f.Row).Append(' ').Append(f.Col).Append(' ')
                 .Append(f.On ? 1 : 0).Append(" |").Append(f.Txt).Append('|');
                if (f.IsChoice || f.Drop)
                {
                    b.Append(" n=").Append(f.N).Append(" dim=").Append(string.Join(",", f.Dim.ConvertAll(i => i.ToString()).ToArray()));
                    if (f.IsChoice) b.Append(" items=").Append(string.Join(";", f.Items.ConvertAll(kv => kv.Key + ":" + kv.Value).ToArray()))
                                     .Append(" why=").Append(string.Join(";", f.Why.ToArray()));
                    else b.Append(" words=").Append(string.Join(";", f.Words.ToArray()));
                }
                b.Append('\n');
            }
            return b.ToString();
        }
    }
}
