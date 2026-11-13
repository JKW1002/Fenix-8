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
//!   - Black wave-pattern dial, dive bezel (20, 30 and 40 turned to read upright)
//!   - Baton hour markers, triangle at 12, FENIX under 12
//!   - Skeleton sword hands with lume tips
//!   - Seconds hand with orange lollipop, shown only while the watch is awake
//!     (after a wrist raise), hidden in low power mode to save battery
//!   - Small dials: date at 3, battery at 6, steps at 9 (orange gauges;
//!     battery turns red below 20%)
//!   - Always-on: outlined hands and dim markers, shifted slightly each minute
//!     to protect the AMOLED screen from burn-in
//!
//! All measurements are written for a 454 px screen and scaled by _s.
class JKWFenixView extends WatchUi.WatchFace {

    // Palette
    private const BEZEL = 0x141518;
    private const BEZEL_EDGE = 0x8A8F98;
    private const PRINT = 0xF2F2F2;
    private const LUME = 0xF4F8EE;
    private const LUME_PIP = 0xD8F5D0;
    private const STEEL = 0xC9CCD2;
    private const HAND_STEEL = 0xD9DDE3;
    private const HAND_CUT = 0x0B0C0E;
    private const DIAL_INNER = 0x2A2D33;
    private const DIAL_OUTER = 0x08090B;
    private const SUB_FILL = 0x050506;
    private const SUB_RING = 0xB8BCC4;
    private const SUB_TICK = 0x6E6E6E;
    private const GAUGE_TRACK = 0x2E2F32;
    private const LABEL = 0xCFCFCF;
    private const ORANGE = 0xFF7A00;
    private const RED = 0xFF3B30;
    private const SECONDS = 0xE9ECF0;
    private const AOD_MARKER = 0x4A4A4A;
    private const AOD_HAND = 0xA0A0A0;

    private const SUB_OFFSET = 100.0;   // distance of small dials from centre
    private const SUB_RADIUS = 40.0;
    private const GAUGE_RADIUS = 28.0;
    private const GAUGE_START = 225;    // degrees, 0 = 3 o'clock, anticlockwise
    private const GAUGE_SPAN = 270;

    private var _cx as Float = 227.0;
    private var _cy as Float = 227.0;
    private var _s as Float = 1.0;

    private var _bg = null;             // BufferedBitmapReference (or BufferedBitmap)
    private var _isSleeping as Boolean = false;
    private var _angledText as Boolean = false;

    private var _fBezel = Graphics.FONT_XTINY;
    private var _fBrand = Graphics.FONT_XTINY;
    private var _fValue = Graphics.FONT_XTINY;
    private var _fLabel = Graphics.FONT_XTINY;
    private var _fDay = Graphics.FONT_XTINY;
    private var _fDate = Graphics.FONT_TINY;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _cx = dc.getWidth() / 2.0;
        _cy = dc.getHeight() / 2.0;
        _s = dc.getWidth() / 454.0;
        loadFonts(dc);
        _bg = null;
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

        var bmp = getBackground(dc);
        if (bmp != null) {
            dc.drawBitmap(0, 0, bmp);
        } else {
            drawStatic(dc);
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

    private function loadFonts(dc as Graphics.Dc) as Void {
        var bold = ["RobotoCondensedBold", "RobotoBold", "BionicBold", "Roboto"];
        var regular = ["RobotoCondensedRegular", "RobotoRegular", "BionicSemiBold", "Roboto"];
        _fBezel = vectorFont(bold, 22, Graphics.FONT_XTINY);
        _fBrand = vectorFont(bold, 22, Graphics.FONT_XTINY);
        _fValue = vectorFont(bold, 17, Graphics.FONT_XTINY);
        _fLabel = vectorFont(regular, 11, Graphics.FONT_XTINY);
        _fDay = vectorFont(bold, 13, Graphics.FONT_XTINY);
        _fDate = vectorFont(bold, 28, Graphics.FONT_TINY);
        _angledText = (dc has :drawAngledText) && !(_fBezel instanceof Number);
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

    // ============================================== static background layer

    //! The dial, bezel, markers and small dial faces never change, so they
    //! are drawn once into an off-screen bitmap and copied each update.
    private function getBackground(dc as Graphics.Dc) {
        var bmp = null;
        if (_bg != null) {
            bmp = (_bg has :get) ? _bg.get() : _bg;
        }
        if (bmp == null) {
            var opts = {:width => dc.getWidth(), :height => dc.getHeight()};
            if (Graphics has :createBufferedBitmap) {
                _bg = Graphics.createBufferedBitmap(opts);
                bmp = _bg.get();
            } else {
                _bg = new Graphics.BufferedBitmap(opts);
                bmp = _bg;
            }
            if (bmp != null) {
                drawStatic(bmp.getDc());
            }
        }
        return bmp;
    }

    private function drawStatic(dc as Graphics.Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawDial(dc);
        drawWaves(dc);
        drawBezel(dc);
        drawMinuteTrack(dc);
        drawMarkers(dc);
        drawBrand(dc);
        drawSubdialFace(dc, _cx + SUB_OFFSET * _s, _cy, null);
        drawSubdialFace(dc, _cx, _cy + SUB_OFFSET * _s, "BATT");
        drawSubdialFace(dc, _cx - SUB_OFFSET * _s, _cy, "STEPS");
        dc.setPenWidth(1);
    }

    //! Soft radial gradient: lighter just above centre, darker at the edge
    private function drawDial(dc as Graphics.Dc) as Void {
        var steps = 24;
        var r = 192.0 * _s;
        for (var i = 0; i < steps; i++) {
            var t = i.toFloat() / (steps - 1);
            dc.setColor(lerpColor(DIAL_OUTER, DIAL_INNER, t), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_cx, _cy - 40.0 * _s * t, r * (1.0 - t * 0.95));
        }
    }

    //! Horizontal wave engraving, slightly lighter than the dial beneath it
    private function drawWaves(dc as Graphics.Dc) as Void {
        var r = 186.0 * _s;
        var step = 6.0 * _s;
        var amp = 5.0 * _s;
        var period = 16.0 * _s;
        var pen = (3.0 * _s).toNumber();
        dc.setPenWidth(pen < 1 ? 1 : pen);

        var y = _cy - r + 6.0 * _s;
        while (y < _cy + r - 4.0 * _s) {
            var dy = y - _cy;
            var half = Math.sqrt(r * r - dy * dy) - 3.0 * _s;
            var x = _cx - half;
            var px = x;
            var py = y + amp * Math.sin(px / period);
            x += step;
            while (x <= _cx + half) {
                var ny = y + amp * Math.sin(x / period);
                dc.setColor(lighten(dialColorAt(x, ny), 0x10), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(px, py, x, ny);
                px = x;
                py = ny;
                x += step;
            }
            y += 11.0 * _s;
        }
    }

    private function drawBezel(dc as Graphics.Dc) as Void {
        // Bezel ring
        dc.setColor(BEZEL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((40.0 * _s).toNumber());
        dc.drawCircle(_cx, _cy, 209.0 * _s);
        dc.setPenWidth((2.0 * _s).toNumber() < 1 ? 1 : (2.0 * _s).toNumber());
        dc.setColor(BEZEL_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, 190.0 * _s);

        // Minute ticks for the first 15 minutes
        dc.setColor(PRINT, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((2.0 * _s).toNumber() < 1 ? 1 : (2.0 * _s).toNumber());
        for (var m = 1; m < 15; m++) {
            if (m % 5 == 0) {
                continue;
            }
            var a = m / 60.0 * 2 * Math.PI;
            dc.drawLine(polarX(a, 198.0), polarY(a, 198.0), polarX(a, 204.0), polarY(a, 204.0));
        }

        // Dots at 15, 25, 35, 45, 55
        for (var d = 15; d < 60; d += 10) {
            var da = d / 60.0 * 2 * Math.PI;
            dc.fillCircle(polarX(da, 208.0), polarY(da, 208.0), 3.0 * _s);
        }

        // Numbers 10 to 50; 20, 30 and 40 turned so they read upright
        for (var n = 10; n < 60; n += 10) {
            var deg = n * 6;
            var na = Math.toRadians(deg);
            var x = polarX(na, 208.0);
            var y = polarY(na, 208.0);
            var text = n.toString();
            var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
            if (_angledText) {
                var rot = (n >= 20 && n <= 40) ? deg + 180 : deg;
                // drawAngledText takes degrees anticlockwise
                dc.drawAngledText(x, y, _fBezel, text, just, (360 - rot) % 360);
            } else {
                dc.drawText(x, y, _fBezel, text, just);
            }
        }

        // Triangle and lume pip at 12
        dc.fillPolygon([
            [_cx - 14.0 * _s, _cy - 224.0 * _s],
            [_cx + 14.0 * _s, _cy - 224.0 * _s],
            [_cx, _cy - 198.0 * _s]
        ]);
        dc.setColor(LUME_PIP, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_cx, _cy - 215.0 * _s, 4.0 * _s);
    }

    private function drawMinuteTrack(dc as Graphics.Dc) as Void {
        dc.setColor(0xE8E8E8, Graphics.COLOR_TRANSPARENT);
        for (var m = 0; m < 60; m++) {
            var a = m / 60.0 * 2 * Math.PI;
            var major = (m % 5 == 0);
            var inner = major ? 172.0 : 177.0;
            var pen = ((major ? 2.0 : 1.0) * _s).toNumber();
            dc.setPenWidth(pen < 1 ? 1 : pen);
            dc.drawLine(polarX(a, 183.0), polarY(a, 183.0), polarX(a, inner), polarY(a, inner));
        }
    }

    private function drawMarkers(dc as Graphics.Dc) as Void {
        for (var h = 1; h < 12; h++) {
            if (h % 3 == 0) {
                continue;   // 3, 6 and 9 are the small dials
            }
            var a = h / 12.0 * 2 * Math.PI;
            var mx = polarX(a, 152.0);
            var my = polarY(a, 152.0);
            dc.setColor(STEEL, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(xform(rect(7.0, 15.0), a, mx, my));
            dc.setColor(LUME, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon(xform(rect(4.5, 12.5), a, mx, my));
        }
        var ty = _cy - 152.0 * _s;
        dc.setColor(STEEL, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(xform(markerTriangle(true), 0.0, _cx, ty));
        dc.setColor(LUME, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(xform(markerTriangle(false), 0.0, _cx, ty));
    }

    private function drawBrand(dc as Graphics.Dc) as Void {
        var text = "FENIX";
        var spacing = 5.0 * _s;
        var chars = text.toCharArray();
        var total = 0.0;
        for (var i = 0; i < chars.size(); i++) {
            total += dc.getTextWidthInPixels(chars[i].toString(), _fBrand);
        }
        total += spacing * (chars.size() - 1);

        var x = _cx - total / 2.0;
        var y = _cy - 95.0 * _s;
        dc.setColor(PRINT, Graphics.COLOR_TRANSPARENT);
        for (var j = 0; j < chars.size(); j++) {
            var ch = chars[j].toString();
            dc.drawText(x, y, _fBrand, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(ch, _fBrand) + spacing;
        }
    }

    private function drawSubdialFace(dc as Graphics.Dc, x as Numeric, y as Numeric, label as String or Null) as Void {
        var r = SUB_RADIUS * _s;
        dc.setColor(SUB_FILL, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, r);

        dc.setColor(SUB_TICK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var i = 0; i < 30; i++) {
            var a = i / 30.0 * 2 * Math.PI;
            var s = Math.sin(a);
            var c = Math.cos(a);
            dc.drawLine(x + (r - 3 * _s) * s, y - (r - 3 * _s) * c, x + (r - 7 * _s) * s, y - (r - 7 * _s) * c);
        }

        var ring = (2.5 * _s).toNumber();
        dc.setPenWidth(ring < 2 ? 2 : ring);
        dc.setColor(SUB_RING, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);

        if (label != null) {
            gauge(dc, x, y, 1.0, GAUGE_TRACK);
            dc.setColor(LABEL, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + 22.0 * _s, _fLabel, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ====================================================== live content

    private function drawDate(dc as Graphics.Dc) as Void {
        var x = _cx + SUB_OFFSET * _s;
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(0xE8E8E8, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, _cy - 14.0 * _s, _fDay, (info.day_of_week as String).toUpper(), just);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, _cy + 9.0 * _s, _fDate, (info.day as Number).format("%d"), just);
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
        var pen = (5.0 * _s).toNumber();
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
        dc.setPenWidth((3.0 * _s).toNumber() < 2 ? 2 : (3.0 * _s).toNumber());
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

        dc.setColor(AOD_MARKER, Graphics.COLOR_TRANSPARENT);
        for (var h = 1; h < 12; h++) {
            var a = h / 12.0 * 2 * Math.PI;
            var mx = ox + 152.0 * _s * Math.sin(a);
            var my = oy - 152.0 * _s * Math.cos(a);
            outline(dc, xform(rect(5.0, 13.0), a, mx, my));
        }
        outline(dc, xform(markerTriangle(true), 0.0, ox, oy - 152.0 * _s));

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

    // ============================================================ helpers

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

    private function rect(hw as Numeric, hh as Numeric) as Array {
        return [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]];
    }

    private function markerTriangle(outer as Boolean) as Array {
        if (outer) {
            return [[-15.0, -16.0], [15.0, -16.0], [0.0, 14.0]];
        }
        return [[-10.0, -12.5], [10.0, -12.5], [0.0, 7.0]];
    }

    private function polarX(a as Numeric, r as Numeric) as Numeric {
        return _cx + r * _s * Math.sin(a);
    }

    private function polarY(a as Numeric, r as Numeric) as Numeric {
        return _cy - r * _s * Math.cos(a);
    }

    //! Approximate dial colour at a point, matching the gradient in drawDial
    private function dialColorAt(x as Numeric, y as Numeric) as Number {
        var dx = x - _cx;
        var dy = y - (_cy - 20.0 * _s);
        var d = Math.sqrt(dx * dx + dy * dy) / (192.0 * _s);
        var t = 1.0 - d;
        if (t < 0.0) {
            t = 0.0;
        }
        return lerpColor(DIAL_OUTER, DIAL_INNER, t);
    }

    private function lerpColor(a as Number, b as Number, t as Numeric) as Number {
        var r = (((a >> 16) & 0xFF) + (((b >> 16) & 0xFF) - ((a >> 16) & 0xFF)) * t).toNumber();
        var g = (((a >> 8) & 0xFF) + (((b >> 8) & 0xFF) - ((a >> 8) & 0xFF)) * t).toNumber();
        var bl = ((a & 0xFF) + ((b & 0xFF) - (a & 0xFF)) * t).toNumber();
        return (r << 16) | (g << 8) | bl;
    }

    private function lighten(c as Number, amt as Number) as Number {
        var r = ((c >> 16) & 0xFF) + amt;
        var g = ((c >> 8) & 0xFF) + amt;
        var b = (c & 0xFF) + amt;
        if (r > 255) { r = 255; }
        if (g > 255) { g = 255; }
        if (b > 255) { b = 255; }
        return (r << 16) | (g << 8) | b;
    }
}
