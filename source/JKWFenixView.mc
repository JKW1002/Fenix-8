import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! JKWFenix: a dive-style analogue watch face for the fenix 8 AMOLED 47mm.
//!
//! The parts that never change (black wave dial running to the screen edge,
//! minute track, triangle at 12, FENIX, small dial rings and gauge tracks) are
//! a pre-rendered image, resources/drawables/dial.png. Drawing them live was
//! too slow and tripped Garmin's watchdog.
//!
//! Drawn live on top:
//!   - Skeleton sword hands with lume tips
//!   - Seconds hand with orange lollipop, only while awake (after a wrist raise)
//!   - Date at 3, battery at 6 (orange, red below 20%), steps at 9 (orange)
//!   - Always-on: outlined hands, dim hour ticks and triangle, shifted each minute
//!     to protect the AMOLED screen from burn-in
//!
//! All measurements are written for a 454 px screen and scaled by _s.
class JKWFenixView extends WatchUi.WatchFace {

    // Palette
    private const STEEL = 0xC9CCD2;
    private const HAND_STEEL = 0xD9DDE3;
    private const HAND_CUT = 0x0B0C0E;
    private const LUME = 0xF4F8EE;
    private const ORANGE = 0xFF7A00;
    private const RED = 0xFF3B30;
    private const SECONDS = 0xE9ECF0;
    private const AOD_MARKER = 0x4A4A4A;
    private const AOD_HAND = 0xA0A0A0;

    private const SUB_OFFSET = 116.0;   // distance of small dials from centre
    private const GAUGE_RADIUS = 46.0;
    private const GAUGE_PEN = 7.5;
    private const GAUGE_START = 225;    // degrees, 0 = 3 o'clock, anticlockwise
    private const GAUGE_SPAN = 270;

    private var _cx as Float = 227.0;
    private var _cy as Float = 227.0;
    private var _s as Float = 1.0;

    private var _dial = null;
    private var _isSleeping as Boolean = false;

    private var _fValue = Graphics.FONT_TINY;
    private var _fDay = Graphics.FONT_XTINY;
    private var _fDate = Graphics.FONT_SMALL;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _cx = dc.getWidth() / 2.0;
        _cy = dc.getHeight() / 2.0;
        _s = dc.getWidth() / 454.0;
        _dial = WatchUi.loadResource(Rez.Drawables.Dial);
        loadFonts();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var settings = System.getDeviceSettings();
        var burnIn = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
        if (_isSleeping && burnIn) {
            drawAlwaysOn(dc);
            return;
        }

        if (_dial != null) {
            dc.drawBitmap(0, 0, _dial);
        }
        drawDate(dc);
        drawBattery(dc);
        drawSteps(dc);
        drawHands(dc, !_isSleeping);
    }

    function onEnterSleep() as Void {
        _isSleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _isSleeping = false;
        WatchUi.requestUpdate();
    }

    // =============================================================== fonts

    private function loadFonts() as Void {
        var bold = ["RobotoCondensedBold", "RobotoBold", "BionicBold", "Roboto"];
        _fValue = vectorFont(bold, 24, Graphics.FONT_TINY);
        _fDay = vectorFont(bold, 19, Graphics.FONT_XTINY);
        _fDate = vectorFont(bold, 42, Graphics.FONT_SMALL);
    }

    private function vectorFont(faces as Array<String>, size as Number, fallback) {
        if (Graphics has :getVectorFont) {
            var f = Graphics.getVectorFont({:face => faces, :size => (size * _s).toNumber()});
            if (f != null) {
                return f;
            }
        }
        return fallback;
    }

    // ===================================================== small dials

    private function drawDate(dc as Graphics.Dc) as Void {
        var x = _cx + SUB_OFFSET * _s;
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(0xE8E8E8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, _cy - 23.0 * _s, _fDay, (info.day_of_week as String).toUpper(), just);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, _cy + 14.0 * _s, _fDate, (info.day as Number).format("%d"), just);
    }

    private function drawBattery(dc as Graphics.Dc) as Void {
        var x = _cx;
        var y = _cy + SUB_OFFSET * _s;
        var pct = System.getSystemStats().battery;
        gauge(dc, x, y, pct / 100.0, pct < 20.0 ? RED : ORANGE);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + 2.0 * _s, _fValue, pct.toNumber().format("%d") + "%",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawSteps(dc as Graphics.Dc) as Void {
        var x = _cx - SUB_OFFSET * _s;
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        if (steps != null && goal != null && goal > 0) {
            gauge(dc, x, _cy, steps.toFloat() / goal, ORANGE);
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, _cy + 2.0 * _s, _fValue, steps != null ? steps.format("%d") : "--",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! 270 degree gauge with rounded ends, opening at the bottom
    private function gauge(dc as Graphics.Dc, x as Numeric, y as Numeric, frac as Numeric, color as Number) as Void {
        if (frac <= 0.005) {
            return;
        }
        if (frac > 1.0) {
            frac = 1.0;
        }
        var r = GAUGE_RADIUS * _s;
        var pen = (GAUGE_PEN * _s).toNumber();
        if (pen < 2) {
            pen = 2;
        }
        var end = GAUGE_START - (GAUGE_SPAN * frac).toNumber();
        if (end < 0) {
            end += 360;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        if (end != GAUGE_START) {
            dc.drawArc(x, y, r, Graphics.ARC_CLOCKWISE, GAUGE_START, end);
        }
        // Rounded caps
        var cap = pen / 2.0;
        var a0 = Math.toRadians(GAUGE_START);
        var a1 = Math.toRadians(end);
        dc.fillCircle(x + r * Math.cos(a0), y - r * Math.sin(a0), cap);
        dc.fillCircle(x + r * Math.cos(a1), y - r * Math.sin(a1), cap);
        dc.setPenWidth(1);
    }

    // =========================================================== hands

    private function drawHands(dc as Graphics.Dc, showSeconds as Boolean) as Void {
        var clock = System.getClockTime();
        var hourA = ((clock.hour % 12) + clock.min / 60.0) / 12.0 * 2 * Math.PI;
        var minA = (clock.min + (showSeconds ? clock.sec / 60.0 : 0.0)) / 60.0 * 2 * Math.PI;

        drawSword(dc, hourA, 105.0, 11.0, 14.0);
        drawSword(dc, minA, 160.0, 9.0, 14.0);
        if (showSeconds) {
            drawSecondsHand(dc, clock.sec / 60.0 * 2 * Math.PI);
        }

        dc.setColor(STEEL, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, 8.0 * _s);
        dc.setColor(0x555555, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy, 3.0 * _s);
    }

    //! Skeleton sword hand: steel body, lume tip, open window near the centre
    private function drawSword(dc as Graphics.Dc, a as Numeric, len as Numeric, w as Numeric, tail as Numeric) as Void {
        var body = swordOutline(len, w, tail);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(xform(body, a, _cx, _cy + 3.0 * _s));    // drop shadow
        dc.setColor(HAND_STEEL, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(xform(body, a, _cx, _cy));

        dc.setColor(LUME, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(xform([
            [-w * 0.6, -len * 0.5], [-w * 0.45, -len * 0.88], [0.0, -len * 0.96],
            [w * 0.45, -len * 0.88], [w * 0.6, -len * 0.5]
        ], a, _cx, _cy));

        dc.setColor(HAND_CUT, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(xform([
            [-w * 0.45, -len * 0.18], [-w * 0.55, -len * 0.42],
            [w * 0.55, -len * 0.42], [w * 0.45, -len * 0.18]
        ], a, _cx, _cy));
    }

    private function swordOutline(len as Numeric, w as Numeric, tail as Numeric) as Array {
        return [
            [-w * 0.35, tail], [-w, -len * 0.25], [-w * 0.75, -len * 0.9], [0.0, -len],
            [w * 0.75, -len * 0.9], [w, -len * 0.25], [w * 0.35, tail]
        ];
    }

    private function drawSecondsHand(dc as Graphics.Dc, a as Numeric) as Void {
        var pen = (2.5 * _s).toNumber();
        dc.setPenWidth(pen < 2 ? 2 : pen);
        dc.setColor(SECONDS, Graphics.COLOR_TRANSPARENT);
        var line = xform([[0.0, 40.0], [0.0, -170.0]], a, _cx, _cy);
        dc.drawLine(line[0][0], line[0][1], line[1][0], line[1][1]);

        var dot = xform([[0.0, -118.0]], a, _cx, _cy)[0];
        dc.fillCircle(dot[0], dot[1], 9.0 * _s);
        dc.setColor(ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(dot[0], dot[1], 6.0 * _s);

        var tip = xform([[0.0, -170.0], [0.0, -154.0]], a, _cx, _cy);
        var tipPen = (3.0 * _s).toNumber();
        dc.setPenWidth(tipPen < 2 ? 2 : tipPen);
        dc.drawLine(tip[0][0], tip[0][1], tip[1][0], tip[1][1]);
        dc.setPenWidth(1);
    }

    // ==================================================== always-on mode

    private function drawAlwaysOn(dc as Graphics.Dc) as Void {
        var clock = System.getClockTime();
        // Shift the whole face a couple of pixels each minute (3 x 3 pattern)
        var ox = _cx + ((clock.min % 3) - 1) * 2.0 * _s;
        var oy = _cy + (((clock.min / 3) % 3) - 1) * 2.0 * _s;
        var pen = (2.0 * _s).toNumber();
        dc.setPenWidth(pen < 1 ? 1 : pen);

        // Dim hour ticks at the edge, matching the minute track on the dial
        dc.setColor(AOD_MARKER, Graphics.COLOR_TRANSPARENT);
        for (var h = 0; h < 12; h++) {
            var a = h / 12.0 * 2 * Math.PI;
            var sn = Math.sin(a);
            var cs = Math.cos(a);
            dc.drawLine(ox + 206.0 * _s * sn, oy - 206.0 * _s * cs, ox + 220.0 * _s * sn, oy - 220.0 * _s * cs);
        }
        outline(dc, xform([[-15.0, -16.0], [15.0, -16.0], [0.0, 14.0]], 0.0, ox, oy - 152.0 * _s));

        var hourA = ((clock.hour % 12) + clock.min / 60.0) / 12.0 * 2 * Math.PI;
        var minA = clock.min / 60.0 * 2 * Math.PI;
        dc.setColor(AOD_HAND, Graphics.COLOR_TRANSPARENT);
        outline(dc, xform(swordOutline(105.0, 11.0, 14.0), hourA, ox, oy));
        outline(dc, xform(swordOutline(160.0, 9.0, 14.0), minA, ox, oy));
        dc.drawCircle(ox, oy, 6.0 * _s);
        dc.setPenWidth(1);
    }

    private function outline(dc as Graphics.Dc, pts as Array) as Void {
        var n = pts.size();
        for (var i = 0; i < n; i++) {
            var p = pts[i];
            var q = pts[(i + 1) % n];
            dc.drawLine(p[0], p[1], q[0], q[1]);
        }
    }

    // ========================================================== helpers

    //! Rotate shape points (in 454 px units, y up = negative) by a radians
    //! clockwise, scale them, and move them to (ox, oy)
    private function xform(pts as Array, a as Numeric, ox as Numeric, oy as Numeric) as Array {
        var c = Math.cos(a);
        var sn = Math.sin(a);
        var out = new [pts.size()];
        for (var i = 0; i < pts.size(); i++) {
            var x = pts[i][0] * _s;
            var y = pts[i][1] * _s;
            out[i] = [ox + x * c - y * sn, oy + x * sn + y * c];
        }
        return out;
    }
}
