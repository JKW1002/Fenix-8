import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! Transformation: a clean digital watch face for the Garmin fenix 8 range.
//!
//! Layout (all positions are relative, so it scales to every fenix 8 screen):
//!   - Left bezel arc:  battery level (green / amber / red)
//!   - Right bezel arc: step goal progress (accent colour)
//!   - Date line, large hours and minutes, then heart rate, steps and battery
//!   - Notification count at the bottom when you have unread notifications
//!   - AMOLED always-on mode: dim, small, position-shifting time (burn-in safe)
class TransformationView extends WatchUi.WatchFace {

    private const ARC_SPAN = 120;          // degrees covered by each bezel arc
    private const LEFT_ARC_START = 240;    // 8 o'clock, fills clockwise up to 10 o'clock
    private const RIGHT_ARC_START = 300;   // 4 o'clock, fills anticlockwise up to 2 o'clock

    private const COLOR_TRACK = 0x2A2A2A;
    private const COLOR_TEXT = 0xFFFFFF;
    private const COLOR_SUBTLE = 0x9A9A9A;
    private const COLOR_HEART = 0xFF3B4E;
    private const COLOR_BATT_OK = 0x40D060;
    private const COLOR_BATT_MID = 0xFFC400;
    private const COLOR_BATT_LOW = 0xFF3B30;

    private var _accents as Array<Number> = [
        0xFFAA00, // Gold
        0x00C8C8, // Teal
        0xFF6A00, // Orange
        0xFF2D55, // Red
        0x3D8BFF, // Blue
        0x40D060  // Green
    ] as Array<Number>;

    private var _isSleeping as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
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
            drawLowPower(dc, settings);
            return;
        }

        var accent = getAccent();
        drawArcs(dc, accent);
        drawDate(dc, accent);
        drawTime(dc, accent, settings);
        drawMetrics(dc);
        drawNotifications(dc, accent, settings);
    }

    function onEnterSleep() as Void {
        _isSleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _isSleeping = false;
        WatchUi.requestUpdate();
    }

    // ---------------------------------------------------------------- drawing

    private function drawArcs(dc as Graphics.Dc, accent as Number) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var cy = dc.getHeight() / 2;
        var pen = (w * 0.028).toNumber();
        if (pen < 4) {
            pen = 4;
        }
        var r = cx - pen;

        dc.setPenWidth(pen);

        // Background tracks
        dc.setColor(COLOR_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, LEFT_ARC_START, LEFT_ARC_START - ARC_SPAN);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, RIGHT_ARC_START, (RIGHT_ARC_START + ARC_SPAN) % 360);

        // Battery (left)
        var battery = System.getSystemStats().battery / 100.0;
        if (battery > 0.01) {
            dc.setColor(batteryColor(battery), Graphics.COLOR_TRANSPARENT);
            var end = LEFT_ARC_START - (ARC_SPAN * clamp(battery)).toNumber();
            if (end != LEFT_ARC_START) {
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, LEFT_ARC_START, end);
            }
        }

        // Steps (right)
        var progress = stepProgress();
        if (progress > 0.01) {
            dc.setColor(progress >= 1.0 ? COLOR_BATT_OK : accent, Graphics.COLOR_TRANSPARENT);
            var sweep = (ARC_SPAN * clamp(progress)).toNumber();
            if (sweep > 0) {
                dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, RIGHT_ARC_START, (RIGHT_ARC_START + sweep) % 360);
            }
        }

        dc.setPenWidth(1);

        // 12 o'clock marker
        var s = (w * 0.018).toNumber();
        var top = pen / 2;
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - s, top], [cx + s, top], [cx, top + (s * 1.6).toNumber()]]);

        // 6 o'clock marker
        dc.setColor(COLOR_SUBTLE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, dc.getHeight() - pen, (s * 0.45).toNumber());
    }

    private function drawDate(dc as Graphics.Dc, accent as Number) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var y = (dc.getHeight() * 0.25).toNumber();
        var font = Graphics.FONT_SMALL;

        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dow = (info.day_of_week as String).toUpper() + " ";
        var rest = (info.day as Number).format("%d") + " " + (info.month as String).toUpper();

        var w1 = dc.getTextWidthInPixels(dow, font);
        var w2 = dc.getTextWidthInPixels(rest, font);
        var x = cx - (w1 + w2) / 2;

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, dow, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + w1, y, font, rest, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawTime(dc as Graphics.Dc, accent as Number, settings as System.DeviceSettings) as Void {
        var w = dc.getWidth();
        var cx = w / 2;
        var y = (dc.getHeight() * 0.47).toNumber();
        var gap = (w * 0.035).toNumber();

        var clock = System.getClockTime();
        var hours = formatHours(clock.hour, settings);
        var mins = clock.min.format("%02d");

        // Use the largest number font that comfortably fits the screen
        var font = Graphics.FONT_NUMBER_THAI_HOT;
        var total = dc.getTextWidthInPixels(hours, font) + dc.getTextWidthInPixels(mins, font) + gap * 2;
        if (total > w * 0.80) {
            font = Graphics.FONT_NUMBER_HOT;
        }

        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - gap, y, font, hours, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + gap, y, font, mins, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);

        // Colon as two accent dots
        var fh = dc.getFontHeight(font);
        var dot = (w * 0.012).toNumber();
        if (dot < 2) {
            dot = 2;
        }
        dc.fillCircle(cx, y - (fh * 0.13).toNumber(), dot);
        dc.fillCircle(cx, y + (fh * 0.13).toNumber(), dot);
    }

    private function drawMetrics(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var colGap = (w * 0.22).toNumber();
        var iconY = (h * 0.665).toNumber();
        var textY = (h * 0.74).toNumber();
        var s = (w * 0.022).toNumber();
        if (s < 4) {
            s = 4;
        }
        var font = Graphics.FONT_TINY;
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Heart rate
        var hr = getHeartRate();
        dc.setColor(COLOR_HEART, Graphics.COLOR_TRANSPARENT);
        drawHeart(dc, cx - colGap, iconY, s);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - colGap, textY, font, hr != null ? hr.format("%d") : "--", justify);

        // Steps
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        dc.setColor(COLOR_SUBTLE, Graphics.COLOR_TRANSPARENT);
        drawSteps(dc, cx, iconY, s);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, textY, font, steps != null ? formatSteps(steps) : "--", justify);

        // Battery
        var battery = System.getSystemStats().battery;
        dc.setColor(batteryColor(battery / 100.0), Graphics.COLOR_TRANSPARENT);
        drawBattery(dc, cx + colGap, iconY, s, battery / 100.0);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx + colGap, textY, font, battery.toNumber().format("%d") + "%", justify);
    }

    private function drawNotifications(dc as Graphics.Dc, accent as Number, settings as System.DeviceSettings) as Void {
        var count = settings.notificationCount;
        if (count == null || count <= 0) {
            return;
        }
        var w = dc.getWidth();
        var cx = w / 2;
        var y = (dc.getHeight() * 0.85).toNumber();
        var s = (w * 0.02).toNumber();
        if (s < 4) {
            s = 4;
        }
        var label = count.format("%d");
        var font = Graphics.FONT_XTINY;
        var tw = dc.getTextWidthInPixels(label, font);
        var iconW = s * 2;
        var x = cx - (iconW + s + tw) / 2;

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        drawEnvelope(dc, x, y, s);
        dc.setColor(COLOR_TEXT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + iconW + s, y, font, label, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! AMOLED always-on: small, dim time that moves every minute to avoid burn-in
    private function drawLowPower(dc as Graphics.Dc, settings as System.DeviceSettings) as Void {
        var w = dc.getWidth();
        var clock = System.getClockTime();
        var step = (w * 0.03).toNumber();
        var dx = ((clock.min % 5) - 2) * step;
        var dy = (((clock.min / 5) % 5) - 2) * step;
        var text = formatHours(clock.hour, settings) + ":" + clock.min.format("%02d");

        dc.setColor(0x808080, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2 + dx, dc.getHeight() / 2 + dy, Graphics.FONT_NUMBER_MEDIUM, text,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ------------------------------------------------------------------ icons

    private function drawHeart(dc as Graphics.Dc, x as Number, y as Number, s as Number) as Void {
        var r = (s * 0.55).toNumber();
        var off = (s * 0.5).toNumber();
        var ty = y - (s * 0.25).toNumber();
        dc.fillCircle(x - off, ty, r);
        dc.fillCircle(x + off, ty, r);
        dc.fillPolygon([
            [x - (s * 1.03).toNumber(), y - (s * 0.05).toNumber()],
            [x + (s * 1.03).toNumber(), y - (s * 0.05).toNumber()],
            [x, y + (s * 1.1).toNumber()]
        ]);
    }

    private function drawSteps(dc as Graphics.Dc, x as Number, y as Number, s as Number) as Void {
        var a = (s * 0.38).toNumber();
        var b = (s * 0.7).toNumber();
        var off = (s * 0.5).toNumber();
        var lift = (s * 0.3).toNumber();
        dc.fillEllipse(x - off, y - lift, a, b);
        dc.fillEllipse(x + off, y + lift - (s * 0.2).toNumber(), a, b);
        dc.fillCircle(x - off, y - lift + b + (s * 0.35).toNumber(), (a * 0.85).toNumber());
        dc.fillCircle(x + off, y + lift - (s * 0.2).toNumber() + b + (s * 0.35).toNumber(), (a * 0.85).toNumber());
    }

    private function drawBattery(dc as Graphics.Dc, x as Number, y as Number, s as Number, level as Float) as Void {
        var bw = (s * 2.0).toNumber();
        var bh = (s * 1.1).toNumber();
        var left = x - bw / 2 - (s * 0.15).toNumber();
        var top = y - bh / 2;
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(left, top, bw, bh, 2);
        dc.fillRectangle(left + bw, y - (s * 0.25).toNumber(), (s * 0.3).toNumber() + 1, (s * 0.5).toNumber());
        var inner = ((bw - 6) * clamp(level)).toNumber();
        if (inner > 0) {
            dc.fillRectangle(left + 3, top + 3, inner, bh - 6);
        }
        dc.setPenWidth(1);
    }

    private function drawEnvelope(dc as Graphics.Dc, x as Number, y as Number, s as Number) as Void {
        var ew = s * 2;
        var eh = (s * 1.4).toNumber();
        var top = y - eh / 2;
        dc.setPenWidth(2);
        dc.drawRectangle(x, top, ew, eh);
        dc.drawLine(x, top, x + s, top + (eh * 0.6).toNumber());
        dc.drawLine(x + ew, top, x + s, top + (eh * 0.6).toNumber());
        dc.setPenWidth(1);
    }

    // ---------------------------------------------------------------- helpers

    private function getAccent() as Number {
        var idx = Application.Properties.getValue("AccentColor");
        if (idx instanceof Number && idx >= 0 && idx < _accents.size()) {
            return _accents[idx];
        }
        return _accents[0];
    }

    private function formatHours(hour as Number, settings as System.DeviceSettings) as String {
        if (settings.is24Hour) {
            return hour.format("%02d");
        }
        var h = hour % 12;
        if (h == 0) {
            h = 12;
        }
        return h.format("%d");
    }

    private function formatSteps(steps as Number) as String {
        if (steps >= 10000) {
            return (steps / 1000.0).format("%.1f") + "k";
        }
        return steps.format("%d");
    }

    private function getHeartRate() as Number or Null {
        var activity = Activity.getActivityInfo();
        if (activity != null && activity.currentHeartRate != null) {
            return activity.currentHeartRate;
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != null
                    && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    private function stepProgress() as Float {
        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        if (steps == null || goal == null || goal <= 0) {
            return 0.0;
        }
        return steps.toFloat() / goal;
    }

    private function batteryColor(level as Float) as Number {
        if (level > 0.5) {
            return COLOR_BATT_OK;
        }
        if (level > 0.2) {
            return COLOR_BATT_MID;
        }
        return COLOR_BATT_LOW;
    }

    private function clamp(v as Float) as Float {
        if (v < 0.0) {
            return 0.0;
        }
        if (v > 1.0) {
            return 1.0;
        }
        return v;
    }
}
