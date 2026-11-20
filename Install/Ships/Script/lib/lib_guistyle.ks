// lib_guistyle.ks -- ONE LOOK FOR THE kOS GUI BOXES (not the displays): a title bar with an optional subtitle, sections under
// headings, body text and grey notes, table rows with fixed column widths, choice buttons that show which one is selected,
// and a primary / secondary action pair. Whole-label colours go through STYLE:TEXTCOLOR (the *_RGB globals); a colour inside
// a line goes through rich text (uiColor with the hex globals). The two forms of a colour are the same colour.
// THE SHUTTLE PANEL LOOK: matte grey panels, grey mono labels, amber = selected, green = the primary action, orange = a
// warning; square corners (the 9-slice PNGs in gui_panel/); ALL text centred both ways (kOS's ALIGN "CENTER" =
// MiddleCenter). UI_PANEL FALSE = the plain look (the default skin, amber headings, [ bracketed ] choices).
// The windows that frame a display (OPS 1 TRAJ / OMS-MPS, ENTRY TRAJ, VERT SIT / HORIZ SIT, the deorbit / family
// progress page) take the same look, as an orbiter cockpit panel, through uiDispSkin / uiDispTitle / uiDispLabel /
// uiDispWarn: the window, buttons, popups and text fields in the panel sprites, but NOT skin:LABEL nor SKIN:FONT (every
// live value and sprite on a page is a label: the displays themselves are unchanged). A toggle that is ON = the switch
// lit (uiOnStates: an amber edge, amber text); a guarded action (ABORT, BAILOUT) an orange edge.
// UI_DISP FALSE (or UI_PANEL FALSE) = the display windows in kOS's default skin.
// Nothing here runs at load except the GLOBALs (and uiRt, the displays' real-time clock). Used by deorbit_plan.ks,
// ops1q.ks (lib_ascent_gui), lib_aoa.ks, lib_dap.ks, and lib_ascdisp, lib_taemdisp, traj_display, prog_display.
@LAZYGLOBAL OFF.

GLOBAL UI_PANEL IS TRUE.                     // TRUE = the Shuttle panel look; FALSE = the plain look
GLOBAL UI_PANEL_DIR IS "gui_panel/".         // its backgrounds, archive-relative (Ships/Script/gui_panel/)
GLOBAL UI_PANEL_FONT IS "Consolas".          // a monospaced Windows font (kOS keeps only those); an unknown name = Arial
GLOBAL UI_DISP IS TRUE.                      // TRUE = the display windows' frames in the panel look (with UI_PANEL)
GLOBAL UI_DISP_PT IS 11.                     // px, the display frames' button and label text
// the 5 and 10 Hz flashes and updates in real time, not game time, so physics warp does not change them:
// the displays' clock, real seconds (KUNIVERSE:REALTIME; TIME:SECONDS on a kOS without it). The flashes and the
// redraws between the guidance cycles run on it, so they keep their rate under physics warp (at 4x a tick is 0.08 s
// of game time: a 0.1 s game-time grid redrew at every tick and flashed several times faster than 5 Hz); the
// guidance cycles, the physics and the extrapolations stay on TIME:SECONDS
GLOBAL uiHasRt IS KUNIVERSE:HASSUFFIX("REALTIME").
FUNCTION uiRt {
    IF uiHasRt { RETURN KUNIVERSE:REALTIME. }
    RETURN TIME:SECONDS.
}
GLOBAL UI_ACCENT IS "#f2c14e".               // amber: the selected choice (in the plain look also the title and the headings)
GLOBAL UI_ACCENT_RGB IS RGB(0.949, 0.757, 0.306).
GLOBAL UI_MUTED IS "#a8b0b8".                // grey: notes, column headings, the secondary action
GLOBAL UI_MUTED_RGB IS RGB(0.659, 0.690, 0.722).
GLOBAL UI_GO IS "#8fd18f".                   // green: the primary action
GLOBAL UI_GO_RGB IS RGB(0.561, 0.820, 0.561).
GLOBAL UI_WARN IS "#ff9966".                 // orange: a value past a limit, a failure in a line
GLOBAL UI_WARN_RGB IS RGB(1, 0.6, 0.4).      // the same orange, a guarded action's text
GLOBAL UI_TEXT_RGB IS RGB(0.788, 0.804, 0.820).    // #c9cdd1 labels and buttons
GLOBAL UI_HEAD_RGB IS RGB(0.604, 0.635, 0.667).    // #9aa2aa section headings and notes
GLOBAL UI_TITLE_RGB IS RGB(0.894, 0.902, 0.910).   // #e4e6e8 the title
GLOBAL UI_FIELD_RGB IS RGB(0.925, 0.933, 0.941).   // #eceef0 typed text
GLOBAL UI_ON_RGB IS RGB(0.165, 0.125, 0.031).      // #2a2008 text on the amber
GLOBAL UI_TITLE_PT IS 16.                    // font sizes: the title ...
GLOBAL UI_HEAD_PT IS 13.                     // ... a section heading ...
GLOBAL UI_BODY_PT IS 12.                     // ... body text and table cells ...
GLOBAL UI_NOTE_PT IS 11.                     // ... a note
GLOBAL UI_GAP IS 6.                          // px between the sections
GLOBAL UI_CTL_H IS 24.                       // px, a button's and a text field's height

// "<color=#..>txt</color>": a colour inside a rich-text line
FUNCTION uiColor {
    PARAMETER txt, hex.
    RETURN "<color=" + hex + ">" + txt + "</color>".
}

// a style rectangle (BORDER, PADDING, MARGIN, OVERFLOW) in px
FUNCTION uiRect {
    PARAMETER rc, pl, pr, pt, pb.
    SET rc:LEFT TO pl.
    SET rc:RIGHT TO pr.
    SET rc:TOP TO pt.
    SET rc:BOTTOM TO pb.
}

// a style's backgrounds (gui_panel/<name>) and text colour in its normal, hover, pressed and focused states (Unity keeps
// a text colour per state)
FUNCTION uiStates {
    PARAMETER st, bg, bgHov, bgAct, col.
    SET st:BG TO UI_PANEL_DIR + bg.
    SET st:TEXTCOLOR TO col.
    IF st:HASSUFFIX("HOVER") { SET st:HOVER:BG TO UI_PANEL_DIR + bgHov. SET st:HOVER:TEXTCOLOR TO col. }
    IF st:HASSUFFIX("ACTIVE") { SET st:ACTIVE:BG TO UI_PANEL_DIR + bgAct. SET st:ACTIVE:TEXTCOLOR TO col. }
    IF st:HASSUFFIX("FOCUSED") { SET st:FOCUSED:BG TO UI_PANEL_DIR + bg. SET st:FOCUSED:TEXTCOLOR TO col. }
}

// a TOGGLE button's ON states (Unity draws a pressed toggle with them): the switch lit, an amber edge and amber text
FUNCTION uiOnStates {
    PARAMETER st.
    IF st:HASSUFFIX("ON") { SET st:ON:BG TO UI_PANEL_DIR + "gp_tog_on". SET st:ON:TEXTCOLOR TO UI_ACCENT_RGB. }
    IF st:HASSUFFIX("HOVER_ON") { SET st:HOVER_ON:BG TO UI_PANEL_DIR + "gp_tog_on_hov". SET st:HOVER_ON:TEXTCOLOR TO UI_ACCENT_RGB. }
    IF st:HASSUFFIX("ACTIVE_ON") { SET st:ACTIVE_ON:BG TO UI_PANEL_DIR + "gp_btn_act". SET st:ACTIVE_ON:TEXTCOLOR TO UI_ACCENT_RGB. }
    IF st:HASSUFFIX("FOCUSED_ON") { SET st:FOCUSED_ON:BG TO UI_PANEL_DIR + "gp_tog_on". SET st:FOCUSED_ON:TEXTCOLOR TO UI_ACCENT_RGB. }
}

// a control style in the panel look: its states' backgrounds and text colour, BORDER 2 (the 9-slice; no layout
// effect), the panel font at pt px (the style's own FONT: the skin's labels keep theirs)
FUNCTION uiCtlStyle {
    PARAMETER st, bg, bgHov, bgAct, col, pt.
    uiStates(st, bg, bgHov, bgAct, col).
    uiRect(st:BORDER, 2, 2, 2, 2).
    SET st:FONT TO UI_PANEL_FONT.
    SET st:FONTSIZE TO pt.
}

// the popup menus of skin sk (kOS draws its list icon on the face itself): the face a button, the list dark, an item
// clear (lit under the mouse), on one line. kOS 1.6's sk:HAS("popupMenu") is FALSE, so a by-name guard styles nothing;
// the skin's own suffixes POPUPMENU / POPUPMENUITEM reach the styles (the list's window style has no suffix: kOS's own,
// dark). The face and the list UI_POP_DPT larger than the buttons.
GLOBAL UI_POP_DPT IS 2.
FUNCTION uiPopSkin {
    PARAMETER sk, pt.
    uiCtlStyle(sk:POPUPMENU, "gp_btn", "gp_btn_hov", "gp_btn_act", UI_TEXT_RGB, pt + UI_POP_DPT).
    LOCAL it IS sk:POPUPMENUITEM.
    uiCtlStyle(it, "gp_clear", "gp_btn_hov", "gp_btn_act", UI_TEXT_RGB, pt + UI_POP_DPT).
    SET it:WORDWRAP TO FALSE.
}

// the panel look on a new GUI's skin, before its first widget (a skin change reaches only the widgets made after it)
FUNCTION uiPanelSkin {
    PARAMETER g.
    LOCAL sk IS g:SKIN.
    SET sk:FONT TO UI_PANEL_FONT.
    SET g:STYLE:BG TO UI_PANEL_DIR + "gp_panel".          // the window: matte grey, a 1 px edge
    uiRect(g:STYLE:BORDER, 2, 2, 2, 2).
    uiRect(g:STYLE:PADDING, 6, 6, 6, 6).
    LOCAL lb IS sk:LABEL.                                  // labels: grey, centred both ways
    SET lb:TEXTCOLOR TO UI_TEXT_RGB.
    SET lb:FONTSIZE TO UI_BODY_PT.
    SET lb:ALIGN TO "CENTER".
    LOCAL bt IS sk:BUTTON.                                 // buttons: flat, square, a thin edge
    uiStates(bt, "gp_btn", "gp_btn_hov", "gp_btn_act", UI_TEXT_RGB).
    uiRect(bt:BORDER, 2, 2, 2, 2).
    uiRect(bt:PADDING, 9, 9, 2, 2).
    SET bt:HEIGHT TO UI_CTL_H.
    SET bt:FONTSIZE TO UI_BODY_PT.
    SET bt:ALIGN TO "CENTER".
    uiOnStates(bt).                                        // a pressed toggle lit
    uiPopSkin(sk, UI_BODY_PT).                             // the popups too
    LOCAL tf IS sk:TEXTFIELD.                              // text fields: dark, an amber edge while typed in
    uiStates(tf, "gp_fld", "gp_fld", "gp_fld", UI_FIELD_RGB).
    IF tf:HASSUFFIX("FOCUSED") { SET tf:FOCUSED:BG TO UI_PANEL_DIR + "gp_fld_foc". }
    uiRect(tf:BORDER, 2, 2, 2, 2).
    uiRect(tf:PADDING, 5, 5, 2, 2).
    SET tf:HEIGHT TO UI_CTL_H.
    SET tf:FONTSIZE TO UI_BODY_PT.
    SET tf:ALIGN TO "CENTER".
    LOCAL bx IS sk:BOX.                                    // a section's frame: none
    SET bx:BG TO UI_PANEL_DIR + "gp_clear".
    uiRect(bx:BORDER, 0, 0, 0, 0).
    uiRect(bx:PADDING, 2, 2, 2, 2).
}

// A new box: GUI(w) at (x, y) with its title bar and, when given, a one-line grey subtitle. Returns the GUI (the caller SHOWs it).
FUNCTION uiBox {
    PARAMETER title, w, x, y, sub IS "".
    LOCAL g IS GUI(w).
    SET g:X TO x.
    SET g:Y TO y.
    IF UI_PANEL { uiPanelSkin(g). }
    LOCAL t IS g:ADDLABEL("<b>" + title + "</b>").
    SET t:STYLE:RICHTEXT TO TRUE.
    SET t:STYLE:ALIGN TO "CENTER".
    IF UI_PANEL {                                          // the title bar: dark, out to the window's edge (OVERFLOW)
        SET t:STYLE:FONTSIZE TO UI_HEAD_PT + 1.
        SET t:STYLE:TEXTCOLOR TO UI_TITLE_RGB.
        SET t:STYLE:BG TO UI_PANEL_DIR + "gp_title".
        uiRect(t:STYLE:BORDER, 0, 0, 0, 1).
        uiRect(t:STYLE:OVERFLOW, 5, 5, 5, 0).
        uiRect(t:STYLE:MARGIN, 0, 0, 0, 6).
        SET t:STYLE:HEIGHT TO 26.
        SET t:STYLE:HSTRETCH TO TRUE.
    } ELSE {
        SET t:STYLE:FONTSIZE TO UI_TITLE_PT.
        SET t:STYLE:TEXTCOLOR TO UI_ACCENT_RGB.
    }
    IF sub <> "" {
        LOCAL s IS uiNote(g, sub).
        SET s:STYLE:ALIGN TO "CENTER".
    }
    RETURN g.
}

// A section: a gap, the heading, then a frame. Returns the frame (add the section's widgets to it).
FUNCTION uiSection {
    PARAMETER parent, ttl.
    parent:ADDSPACING(UI_GAP).
    LOCAL h IS parent:ADDLABEL("<b>" + ttl + "</b>").
    SET h:STYLE:RICHTEXT TO TRUE.
    IF UI_PANEL {                                          // grey, a thin rule under it
        SET h:STYLE:FONTSIZE TO UI_NOTE_PT.
        SET h:STYLE:TEXTCOLOR TO UI_HEAD_RGB.
        SET h:STYLE:BG TO UI_PANEL_DIR + "gp_rule".
        uiRect(h:STYLE:BORDER, 0, 0, 0, 1).
        SET h:STYLE:HEIGHT TO 20.
        SET h:STYLE:HSTRETCH TO TRUE.
    } ELSE {
        SET h:STYLE:FONTSIZE TO UI_HEAD_PT.
        SET h:STYLE:TEXTCOLOR TO UI_ACCENT_RGB.
    }
    RETURN parent:ADDVBOX().
}

// Body text: rich text, wrapped. Returns the label.
FUNCTION uiText {
    PARAMETER parent, txt IS "".
    LOCAL l IS parent:ADDLABEL(txt).
    SET l:STYLE:RICHTEXT TO TRUE.
    SET l:STYLE:WORDWRAP TO TRUE.
    SET l:STYLE:FONTSIZE TO UI_BODY_PT.
    RETURN l.
}

// A note: smaller grey body text. Returns the label.
FUNCTION uiNote {
    PARAMETER parent, txt IS "".
    LOCAL l IS uiText(parent, txt).
    SET l:STYLE:FONTSIZE TO UI_NOTE_PT.
    SET l:STYLE:TEXTCOLOR TO CHOOSE UI_HEAD_RGB IF UI_PANEL ELSE UI_MUTED_RGB.
    RETURN l.
}

// A table row: one label per column, each its fixed width in px, so the rows' columns line up. Returns LEXICON("row" = the
// layout (SHOW / HIDE it), "cells" = the labels).
FUNCTION uiRow {
    PARAMETER parent, widths.
    LOCAL rw IS parent:ADDHLAYOUT().
    LOCAL cells IS LIST().
    FOR w IN widths {
        LOCAL c IS rw:ADDLABEL("").
        SET c:STYLE:RICHTEXT TO TRUE.
        SET c:STYLE:FONTSIZE TO UI_BODY_PT.
        SET c:STYLE:HSTRETCH TO FALSE.
        SET c:STYLE:WIDTH TO w.
        cells:ADD(c).
    }
    RETURN LEXICON("row", rw, "cells", cells).
}

// A choice button (one of a set, polled with :TAKEPRESS); uiChoiceShow marks the selected one.
FUNCTION uiChoice {
    PARAMETER parent, txt.
    LOCAL b IS parent:ADDBUTTON(txt).
    SET b:STYLE:RICHTEXT TO TRUE.
    RETURN b.
}

// Show a choice button as selected or not (its plain text). The panel look: selected = an amber button with dark text; before
// bold amber [ bracketed ] text.
FUNCTION uiChoiceShow {
    PARAMETER b, txt, isOn.
    IF UI_PANEL {
        IF isOn { uiStates(b:STYLE, "gp_btn_on", "gp_btn_on_hov", "gp_btn_on_hov", UI_ON_RGB). }
        ELSE { uiStates(b:STYLE, "gp_btn", "gp_btn_hov", "gp_btn_act", UI_TEXT_RGB). }
        SET b:TEXT TO txt.
    } ELSE {
        SET b:TEXT TO CHOOSE "<b>" + uiColor("[ " + txt + " ]", UI_ACCENT) + "</b>" IF isOn ELSE txt.
    }
}

// The primary action (bold green; the panel look: a green edge) and a secondary one (grey). Return the buttons.
FUNCTION uiPrimary {
    PARAMETER parent, txt.
    LOCAL b IS 0.
    IF UI_PANEL {
        SET b TO parent:ADDBUTTON("<b>" + txt + "</b>").
        uiStates(b:STYLE, "gp_go", "gp_go_hov", "gp_btn_act", UI_GO_RGB).
    } ELSE {
        SET b TO parent:ADDBUTTON("<b>" + uiColor(txt, UI_GO) + "</b>").
    }
    SET b:STYLE:RICHTEXT TO TRUE.
    RETURN b.
}
FUNCTION uiSecondary {
    PARAMETER parent, txt.
    LOCAL b IS parent:ADDBUTTON(CHOOSE txt IF UI_PANEL ELSE uiColor(txt, UI_MUTED)).
    SET b:STYLE:RICHTEXT TO TRUE.
    RETURN b.
}

// ---------------------------------------------------------------- the frames round the displays
// TRUE when the display windows take the panel look
FUNCTION uiDispOn {
    RETURN UI_PANEL AND UI_DISP.
}

// A display window's skin, right after its GUI() (before its first widget): the window, its buttons (and their ON states),
// text fields and popups in the panel look. Not touched: skin:LABEL and SKIN:FONT (the page's live values and sprites are
// labels), the window's PADDING (the page box keeps its place), any size.
FUNCTION uiDispSkin {
    PARAMETER g.
    IF NOT uiDispOn() { RETURN. }
    LOCAL sk IS g:SKIN.
    SET g:STYLE:BG TO UI_PANEL_DIR + "gp_panel".
    uiRect(g:STYLE:BORDER, 2, 2, 2, 2).
    LOCAL bt IS sk:BUTTON.
    uiCtlStyle(bt, "gp_btn", "gp_btn_hov", "gp_btn_act", UI_TEXT_RGB, UI_DISP_PT).
    uiOnStates(bt).
    LOCAL tf IS sk:TEXTFIELD.
    uiCtlStyle(tf, "gp_fld", "gp_fld", "gp_fld", UI_FIELD_RGB, UI_DISP_PT).
    IF tf:HASSUFFIX("FOCUSED") { SET tf:FOCUSED:BG TO UI_PANEL_DIR + "gp_fld_foc". }
    uiPopSkin(sk, UI_DISP_PT).
}

// A display window's title: its row a dark bar with a rule under it, the title light grey, centred, 22 px high
FUNCTION uiDispTitle {
    PARAMETER rw, lb.
    IF NOT uiDispOn() { RETURN. }
    SET rw:STYLE:BG TO UI_PANEL_DIR + "gp_title".
    uiRect(rw:STYLE:BORDER, 0, 0, 0, 1).
    SET lb:STYLE:RICHTEXT TO TRUE.
    SET lb:STYLE:FONT TO UI_PANEL_FONT.
    SET lb:STYLE:FONTSIZE TO UI_HEAD_PT.
    SET lb:STYLE:TEXTCOLOR TO UI_TITLE_RGB.
    SET lb:STYLE:ALIGN TO "CENTER".
    SET lb:STYLE:HSTRETCH TO TRUE.
    SET lb:STYLE:HEIGHT TO 22.
}

// A label in a display window's frame (not on the page): the panel font, grey
FUNCTION uiDispLabel {
    PARAMETER lb.
    IF NOT uiDispOn() { RETURN. }
    SET lb:STYLE:FONT TO UI_PANEL_FONT.
    SET lb:STYLE:FONTSIZE TO UI_DISP_PT.
    SET lb:STYLE:TEXTCOLOR TO UI_HEAD_RGB.
}

// A guarded action (ABORT, FAIL NOW, BAILOUT): an orange edge, orange text (its own style; uiDispOn only)
FUNCTION uiDispWarn {
    PARAMETER b.
    IF NOT uiDispOn() { RETURN. }
    uiStates(b:STYLE, "gp_warn", "gp_warn_hov", "gp_btn_act", UI_WARN_RGB).
}
