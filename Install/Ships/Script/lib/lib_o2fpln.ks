// lib_o2fpln.ks -- ops2q's FLIGHT-PLAN TREE.
//  The tree: node 0 is the state NOW (the live orbit); every other node is a BURN planned from the state after its parent's burn. A node
//  with two or more children is a branch point. Two kinds of burn: OURS (src "O": BRN PLN's SAVE / LOAD, the plan files) and PRINCIPIA'S
//  (src "P", type PRNCP: the mirror of its flight plans, READ ONLY: o2flMirror replaces them, nothing is ever sent back).
//  A node: LEXICON(id, par, kids (live child ids, in order), src, ty (CIRC HA HP PLANE DV OMS-1 OMS-2 DEORB PRNCP), ut (the impulse, UT),
//    ep (the UT its el is defined at: the impulse for ours, the ignition for Principia's), dv (LVLH LIST at the impulse), el (the
//    conic AFTER the burn, lib_o2orb's o2Els; node 0 has none), key (the node's source identity: a plan file, a Principia plan:burn), tb, live,
//    nb (the burn was solved by the N-BODY solve (ADDONS:KALS:NBSOLVE), so its state after the burn is the n-body coast's)).
//  NAMES: the burn number (its depth) then one letter for every node on its path whose PARENT has two or
//  more children, the letter = its place among them (A, B ..): 1A 1B, 2AA 2AB, and 2A under an unbranched 1A; the names are computed, so
//  they re-letter by themselves when a branch is added or removed.
//  RULES: SAVE adds a CHILD of the FPLN STATE node (a node that has a child already becomes a branch point); DELETE removes the burn and
//  everything under it (never node 0); a burn FLOWN (o2flFly) drops its sibling branches, leaves the tree and its children move up.
//  o2flN is a LIST indexed by id (an id is never reused; a removed node keeps its slot with live FALSE).
//  Needs lib_o2orb.ks loaded first (o2Els, o2AtTA, o2TAafter, o2Lvlh, o2ToLvlh).
GLOBAL o2flN IS LIST().
GLOBAL o2flTip IS 0.                          // the ACTIVE PATH ends here (root .. tip, then each first child down to a leaf)
GLOBAL o2flState IS 0.                        // BRN PLN's FPLN STATE: the burns after it are planned from its state after the burn
GLOBAL o2flSel IS 0.                          // the FPLN page's selected burn
GLOBAL o2flVer IS 0.                          // +1 at every change of the tree
GLOBAL O2FL_MAX_PLANS IS 10.                  // Principia's own cap (max_flight_plans)

FUNCTION o2flInit {
    SET o2flN TO LIST().
    o2flN:ADD(LEXICON("id", 0, "par", -1, "kids", LIST(), "src", "O", "ty", "", "ut", 0, "ep", 0, "dv", LIST(0, 0, 0), "el", LEXICON(),
        "key", "", "tb", 0, "live", TRUE, "nb", FALSE)).
    SET o2flTip TO 0. SET o2flState TO 0. SET o2flSel TO 0.
    SET o2flVer TO o2flVer + 1.
}

FUNCTION o2flLive { PARAMETER id. RETURN id >= 0 AND id < o2flN:LENGTH AND o2flN[id]["live"]. }
FUNCTION o2flCount { LOCAL n IS 0. FOR nd IN o2flN { IF nd["live"] AND nd["id"] > 0 { SET n TO n + 1. } } RETURN n. }

// a child of par: src "O" / "P", the type word, the impulse UT, the el's epoch, the LVLH dv, the conic after, the key, the burn time
FUNCTION o2flAdd {
    PARAMETER par, src, ty, ut, ep, dv, el, key IS "", tb IS 0, nb IS FALSE.
    LOCAL id IS o2flN:LENGTH.
    o2flN:ADD(LEXICON("id", id, "par", par, "kids", LIST(), "src", src, "ty", ty, "ut", ut, "ep", ep, "dv", dv, "el", el,
        "key", key, "tb", tb, "live", TRUE, "nb", nb)).
    o2flN[par]["kids"]:ADD(id).
    SET o2flVer TO o2flVer + 1.
    RETURN id.
}

FUNCTION o2flUpgrade {                       // a node solved again by the n-body solve: its burn, conic after and key replaced, the mark set
    PARAMETER id, ut, dv, el, key.
    SET o2flN[id]["ut"] TO ut. SET o2flN[id]["ep"] TO ut. SET o2flN[id]["dv"] TO dv. SET o2flN[id]["el"] TO el. SET o2flN[id]["key"] TO key.
    SET o2flN[id]["nb"] TO TRUE.
    SET o2flVer TO o2flVer + 1.
}

FUNCTION o2flDepth {
    PARAMETER id.
    LOCAL d IS 0. LOCAL c IS id.
    UNTIL c <= 0 { SET d TO d + 1. SET c TO o2flN[c]["par"]. }
    RETURN d.
}

FUNCTION o2flUp {                             // the ids root .. id
    PARAMETER id.
    LOCAL rs IS LIST(). LOCAL c IS id.
    UNTIL c < 0 { rs:INSERT(0, c). SET c TO o2flN[c]["par"]. }
    RETURN rs.
}

FUNCTION o2flLetter { PARAMETER k. RETURN CHOOSE CHAR(65 + k) IF k < 26 ELSE "+". }

FUNCTION o2flName {
    PARAMETER id.
    IF id <= 0 { RETURN "0". }
    LOCAL upl IS o2flUp(id).
    LOCAL s IS "".
    FROM { LOCAL i IS 1. } UNTIL i >= upl:LENGTH STEP { SET i TO i + 1. } DO {
        LOCAL kids IS o2flN[upl[i - 1]]["kids"].
        IF kids:LENGTH >= 2 { SET s TO s + o2flLetter(kids:INDEXOF(upl[i])). }
    }
    RETURN ("" + (upl:LENGTH - 1)) + s.
}

FUNCTION o2flFind {                           // the id of a name, -1 when none
    PARAMETER nm.
    FOR nd IN o2flN { IF nd["live"] AND o2flName(nd["id"]) = nm { RETURN nd["id"]. } }
    RETURN -1.
}

FUNCTION o2flDfs {                            // the live ids in pre-order (depth-first), 0 first
    LOCAL out IS LIST().
    LOCAL st IS LIST(0).
    UNTIL st:LENGTH = 0 {
        LOCAL c IS st[st:LENGTH - 1].
        st:REMOVE(st:LENGTH - 1).
        out:ADD(c).
        LOCAL kids IS o2flN[c]["kids"].
        FROM { LOCAL i IS kids:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO { st:ADD(kids[i]). }
    }
    RETURN out.
}

FUNCTION o2flLay {                            // the grid: one column per leaf (in pre-order); LEXICON(c0, c1 (the leaf columns under each id), dp (depth), n (leaves), md (deepest), ord)
    LOCAL n IS o2flN:LENGTH.
    LOCAL c0 IS LIST(). LOCAL c1 IS LIST(). LOCAL dp IS LIST().
    FROM { LOCAL i IS 0. } UNTIL i >= n STEP { SET i TO i + 1. } DO { c0:ADD(-1). c1:ADD(-1). dp:ADD(-1). }
    LOCAL nl IS 0. LOCAL md IS 0.
    LOCAL ord IS o2flDfs().
    FOR id IN ord {
        IF id = 0 { SET dp[0] TO 0. } ELSE { SET dp[id] TO dp[o2flN[id]["par"]] + 1. }
        IF dp[id] > md { SET md TO dp[id]. }
        IF o2flN[id]["kids"]:LENGTH = 0 { SET c0[id] TO nl. SET c1[id] TO nl. SET nl TO nl + 1. }
    }
    FROM { LOCAL i IS ord:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO {
        LOCAL id IS ord[i].
        LOCAL kids IS o2flN[id]["kids"].
        IF kids:LENGTH > 0 { SET c0[id] TO c0[kids[0]]. SET c1[id] TO c1[kids[kids:LENGTH - 1]]. }
    }
    RETURN LEXICON("c0", c0, "c1", c1, "dp", dp, "n", MAX(1, nl), "md", md, "ord", ord).
}

FUNCTION o2flFix {                            // the path / state / selection point at a live node (a removed one: its parent)
    PARAMETER id, par.
    IF NOT o2flLive(o2flTip) { SET o2flTip TO par. }
    IF NOT o2flLive(o2flState) { SET o2flState TO par. }
    IF NOT o2flLive(o2flSel) { SET o2flSel TO par. }
}

FUNCTION o2flDel {                            // the burn and everything under it: how many went (the root never)
    PARAMETER id.
    IF id <= 0 OR NOT o2flLive(id) { RETURN 0. }
    LOCAL par IS o2flN[id]["par"].
    LOCAL cnt IS 0.
    LOCAL st IS LIST(id).
    UNTIL st:LENGTH = 0 {
        LOCAL c IS st[st:LENGTH - 1].
        st:REMOVE(st:LENGTH - 1).
        FOR k IN o2flN[c]["kids"] { st:ADD(k). }
        SET o2flN[c]["live"] TO FALSE.
        SET cnt TO cnt + 1.
    }
    LOCAL pk IS o2flN[par]["kids"].
    pk:REMOVE(pk:INDEXOF(id)).
    o2flFix(id, par).
    SET o2flVer TO o2flVer + 1.
    RETURN cnt.
}

FUNCTION o2flFly {                            // a burn FLOWN: its sibling branches are dropped (that state no longer exists), it leaves the tree, its children move up
    PARAMETER id.
    IF id <= 0 OR NOT o2flLive(id) { RETURN. }
    LOCAL par IS o2flN[id]["par"].
    FOR s IN o2flN[par]["kids"]:COPY { IF s <> id { o2flDel(s). } }
    LOCAL pk IS o2flN[par]["kids"].
    LOCAL ix IS pk:INDEXOF(id).
    pk:REMOVE(ix).
    LOCAL kk IS o2flN[id]["kids"].
    FROM { LOCAL i IS kk:LENGTH - 1. } UNTIL i < 0 STEP { SET i TO i - 1. } DO {
        pk:INSERT(ix, kk[i]).
        SET o2flN[kk[i]]["par"] TO par.
    }
    SET o2flN[id]["live"] TO FALSE.
    o2flFix(id, par).
    SET o2flVer TO o2flVer + 1.
}

FUNCTION o2flPath {                           // the ACTIVE PATH: ids root .. tip, then every first child down to a leaf
    LOCAL p IS o2flUp(o2flTip).
    LOCAL c IS o2flTip.
    UNTIL o2flN[c]["kids"]:LENGTH = 0 { SET c TO o2flN[c]["kids"][0]. p:ADD(c). }
    RETURN p.
}
FUNCTION o2flOnPath { PARAMETER id. RETURN o2flPath():CONTAINS(id). }
FUNCTION o2flSetPath { PARAMETER id. IF o2flLive(id) { SET o2flTip TO id. SET o2flVer TO o2flVer + 1. } }

FUNCTION o2flStep {                           // FPLN STATE's + / -: the next (d = 1) / previous burn depth-first, 0 .. the last, no wrap
    PARAMETER id, d.
    LOCAL ord IS o2flDfs().
    LOCAL i IS ord:INDEXOF(id) + d.
    IF i < 0 OR i >= ord:LENGTH { RETURN id. }
    RETURN ord[i].
}

FUNCTION o2flSide {                           // the cursor's left / right (d = -1 / 1): the node of the same depth before / after in the tree, id when none
    PARAMETER id, d.
    LOCAL dp IS o2flDepth(id).
    LOCAL row IS LIST().
    FOR c IN o2flDfs() { IF o2flDepth(c) = dp { row:ADD(c). } }
    LOCAL i IS row:INDEXOF(id) + d.
    IF i < 0 OR i >= row:LENGTH { RETURN id. }
    RETURN row[i].
}

FUNCTION o2flUpOf { PARAMETER id. RETURN CHOOSE o2flN[id]["par"] IF id > 0 ELSE 0. }                       // the cursor's up = the parent
FUNCTION o2flDownOf { PARAMETER id. RETURN CHOOSE o2flN[id]["kids"][0] IF o2flN[id]["kids"]:LENGTH > 0 ELSE id. }   // down = the first child

FUNCTION o2flHas { PARAMETER key. FOR nd IN o2flN { IF nd["live"] AND nd["key"] = key AND key <> "" { RETURN nd["id"]. } } RETURN -1. }   // the burn with that key, -1 when none

FUNCTION o2flStateAt {                        // LIST(r, v) on the conic el (defined at epoch ep) at UT ut
    PARAMETER el, ep, ut.
    IF el["n"] <= 0 { RETURN o2AtTA(el, el["ta"]). }
    RETURN o2AtTA(el, o2TAafter(el, el["ta"], ut - ep)).
}

// a burn's start and end (UT) and where the orbiter is once it ends. Ours: the impulse UT (ut) is the burn's centre, so it starts tb / 2 before
// and ends tb / 2 after it, and the conic's epoch is the impulse. Principia's: the conic's epoch is the ignition (ep), the burn ends tb after it.
FUNCTION o2flBegin { PARAMETER id. RETURN CHOOSE o2flN[id]["ep"] IF o2flN[id]["src"] = "P" ELSE o2flN[id]["ut"] - o2flN[id]["tb"] / 2. }
FUNCTION o2flEnd { PARAMETER id. RETURN CHOOSE o2flN[id]["ep"] + o2flN[id]["tb"] IF o2flN[id]["src"] = "P" ELSE o2flN[id]["ut"] + o2flN[id]["tb"] / 2. }
FUNCTION o2flBugDt {                          // s after the node's conic epoch at which its burn ends (the orbiter bug's place on that conic); 0 for node 0
    PARAMETER id.
    IF id <= 0 OR NOT o2flLive(id) { RETURN 0. }
    RETURN MAX(0, o2flEnd(id) - o2flN[id]["ep"]).
}

FUNCTION o2flOrb {                            // a node's orbit as text "HA x HP" in km, whole ("" for the root: the caller shows the live one)
    PARAMETER id, rad.
    LOCAL el IS o2flN[id]["el"].
    IF NOT el:HASKEY("ra") { RETURN "". }
    IF el["e"] >= 1 { RETURN "ESCAPE". }
    RETURN ROUND((el["ra"] - rad) / 1000) + "x" + ROUND((el["rp"] - rad) / 1000).
}

// ---- Principia's mirror (READ ONLY): plans = LIST of plans, each LIST of burns LEXICON(ut, ep, dv, el, tb, key); one branch under node 0 per plan.
// A burn already there with the same key, the same parent and the same impulse (1 s, 0.05 m/s) is kept as it is (its id, and OUR burns planned
// after it); the rest of the old mirror goes (our burns under it with it: LEXICON(lost: ours dropped)). Returns LEXICON(new, kept, gone (mirrored burns removed), lost (ours removed with them)).
FUNCTION o2flSame {
    PARAMETER nd, b.
    IF ABS(nd["ut"] - b["ut"]) >= 1 { RETURN FALSE. }
    FROM { LOCAL i IS 0. } UNTIL i >= 3 STEP { SET i TO i + 1. } DO { IF ABS(nd["dv"][i] - b["dv"][i]) >= 0.05 { RETURN FALSE. } }
    RETURN TRUE.
}

FUNCTION o2flMirror {
    PARAMETER plans.
    LOCAL top IS o2flN:LENGTH.                // the nodes there before: only these can be old mirror to drop
    LOCAL old IS LEXICON().
    FOR nd IN o2flN { IF nd["live"] AND nd["src"] = "P" { SET old[nd["key"]] TO nd["id"]. } }
    LOCAL keep IS LIST().
    LOCAL nNew IS 0.
    LOCAL pn IS MIN(plans:LENGTH, O2FL_MAX_PLANS).
    FROM { LOCAL p IS 0. } UNTIL p >= pn STEP { SET p TO p + 1. } DO {
        LOCAL par IS 0.
        LOCAL chain IS TRUE.
        FOR b IN plans[p] {
            LOCAL id IS -1.
            IF chain AND old:HASKEY(b["key"]) {
                LOCAL oi IS old[b["key"]].
                IF o2flN[oi]["live"] AND o2flN[oi]["par"] = par AND o2flSame(o2flN[oi], b) { SET id TO oi. }
            }
            IF id < 0 {
                SET chain TO FALSE.
                SET id TO o2flAdd(par, "P", "PRNCP", b["ut"], b["ep"], b["dv"], b["el"], b["key"], b["tb"]).
                SET nNew TO nNew + 1.
            } ELSE { keep:ADD(id). }
            SET par TO id.
        }
    }
    LOCAL gone IS 0. LOCAL lost IS 0.
    FROM { LOCAL i IS 1. } UNTIL i >= top STEP { SET i TO i + 1. } DO {
        IF o2flN[i]["live"] AND o2flN[i]["src"] = "P" AND NOT keep:CONTAINS(i) {
            FOR c IN o2flSub(i) { IF o2flN[c]["src"] = "O" { SET lost TO lost + 1. } ELSE { SET gone TO gone + 1. } }
            o2flDel(i).
        }
    }
    o2flOrder().
    SET o2flVer TO o2flVer + 1.
    RETURN LEXICON("new", nNew, "kept", keep:LENGTH, "gone", gone, "lost", lost).
}

FUNCTION o2flSub {                            // the ids under id (and id itself)
    PARAMETER id.
    LOCAL out IS LIST(). LOCAL st IS LIST(id).
    UNTIL st:LENGTH = 0 {
        LOCAL c IS st[st:LENGTH - 1]. st:REMOVE(st:LENGTH - 1).
        out:ADD(c).
        FOR k IN o2flN[c]["kids"] { st:ADD(k). }
    }
    RETURN out.
}

FUNCTION o2flPlanOf { PARAMETER k. RETURN o2flN[k]["key"]:SPLIT(":")[0]:TONUMBER(0). }   // a mirrored burn's Principia plan index

FUNCTION o2flOrder {                          // every node's kids: the mirrored ones first (in their plan order), then ours (in their order)
    FOR nd IN o2flN {
        IF nd["live"] AND nd["kids"]:LENGTH > 1 {
            LOCAL a IS LIST(). LOCAL b IS LIST().
            FOR k IN nd["kids"] {
                IF o2flN[k]["src"] = "P" {
                    LOCAL i IS a:LENGTH.
                    UNTIL i = 0 OR o2flPlanOf(a[i - 1]) <= o2flPlanOf(k) { SET i TO i - 1. }
                    a:INSERT(i, k).
                } ELSE { b:ADD(k). }
            }
            FOR k IN b { a:ADD(k). }
            SET nd["kids"] TO a.
        }
    }
}

// a Principia burn as o2flMirror wants it: plan p, manoeuvre mi, the ignition UT ig, the impulse (half-dV) UT tc, the burn time tb, the ignition state
// r, v (body-relative, world axes) and the burn's dV vector dvw (world axes): the conic after = the ignition state + the impulse (an approximation of the
// burn's own length), the LVLH dv in the ignition state's frame
FUNCTION o2flPrRec {
    PARAMETER p, mi, ig, tc, tb, rv, vv, dvw, mu, npole, eqx.
    RETURN LEXICON("ut", tc, "ep", ig, "dv", o2ToLvlh(dvw, o2Lvlh(rv, vv)), "el", o2Els(rv, vv + dvw, mu, npole, eqx), "tb", tb,
        "key", p + ":" + mi).
}

// ---- OUR burns kept over a re-RUN: 1:/o2q_fpln.txt (the vessel's own volume), one line a burn whose parent is node 0 or another of ours
// (a burn under a Principia burn is not kept: its parent is read again). The conic after is rebuilt from the state at its epoch.
GLOBAL O2FL_FILE IS "1:/o2q_fpln.txt".
FUNCTION o2flSave {
    IF EXISTS(O2FL_FILE) { DELETEPATH(O2FL_FILE). }
    FOR nd IN o2flN {
        IF nd["live"] AND nd["id"] > 0 AND nd["src"] = "O" AND o2flN[nd["par"]]["src"] = "O" AND nd["el"]:HASKEY("ta") {
            LOCAL st IS o2AtTA(nd["el"], nd["el"]["ta"]).
            LOCAL rv IS st[0]. LOCAL vv IS st[1].
            LOG "" + nd["id"] + "," + nd["par"] + "," + nd["ty"] + "," + ROUND(nd["ut"], 2) + "," + ROUND(nd["ep"], 2) + "," + ROUND(nd["dv"][0], 3) + ","
                + ROUND(nd["dv"][1], 3) + "," + ROUND(nd["dv"][2], 3) + "," + ROUND(rv:X, 2) + "," + ROUND(rv:Y, 2) + "," + ROUND(rv:Z, 2) + ","
                + ROUND(vv:X, 4) + "," + ROUND(vv:Y, 4) + "," + ROUND(vv:Z, 4) + "," + nd["key"] + "," + ROUND(nd["tb"], 1) + "," + (CHOOSE 1 IF nd["nb"] ELSE 0) TO O2FL_FILE.
        }
    }
}

FUNCTION o2flLoad {                           // after o2flInit: our burns back; how many
    PARAMETER mu, npole, eqx.
    IF NOT EXISTS(O2FL_FILE) { RETURN 0. }
    LOCAL map IS LEXICON(). LOCAL n IS 0.
    FOR ln0 IN OPEN(O2FL_FILE):READALL:STRING:SPLIT(CHAR(10)) {
        LOCAL f IS ln0:TRIM:SPLIT(",").
        IF f:LENGTH >= 16 {
            LOCAL par IS 0.
            IF f[1] <> "0" { SET par TO CHOOSE map[f[1]] IF map:HASKEY(f[1]) ELSE -1. }
            IF par >= 0 {
                LOCAL rv IS V(f[8]:TONUMBER(0), f[9]:TONUMBER(0), f[10]:TONUMBER(0)).
                LOCAL vv IS V(f[11]:TONUMBER(0), f[12]:TONUMBER(0), f[13]:TONUMBER(0)).
                LOCAL id IS o2flAdd(par, "O", f[2], f[3]:TONUMBER(0), f[4]:TONUMBER(0), LIST(f[5]:TONUMBER(0), f[6]:TONUMBER(0), f[7]:TONUMBER(0)),
                    o2Els(rv, vv, mu, npole, eqx), f[14], f[15]:TONUMBER(0), CHOOSE (f[16] = "1") IF f:LENGTH >= 17 ELSE FALSE).
                SET map[f[0]] TO id.
                SET n TO n + 1.
            }
        }
    }
    RETURN n.
}
