function nextPrayer(report, now) {
    if (!report) return null;
    for (var i = 0; i < report.events.length; i++) {
        var event = report.events[i];
        if (event.prayer && event.epoch > now) return event;
    }
    return null;
}

function progress(report, now) {
    var next = nextPrayer(report, now);
    if (!next) return 0;
    var previous = null;
    for (var i = 0; i < report.events.length; i++) {
        var event = report.events[i];
        if (event.prayer && event.epoch <= now) previous = event;
    }
    if (!previous) return 0;
    return Math.max(0, Math.min(1, (now - previous.epoch) / (next.epoch - previous.epoch)));
}

function countdown(seconds, compact) {
    var total = Math.max(0, Math.ceil(seconds));
    var h = Math.floor(total / 3600);
    var m = Math.floor((total % 3600) / 60);
    var s = total % 60;
    if (compact) return h ? h + "h " + m + "m" : Math.max(1, Math.ceil(total / 60)) + "m";
    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
}

function timeLabel(row, clock24) {
    return row ? (clock24 ? row.time24 : row.time12 + " " + row.period) : "—";
}

function retryDelay(failures) {
    return Math.min(900, 60 * Math.pow(2, Math.max(0, failures - 1)));
}

var barPresets = [
    {value: "name-time", label: "Prayer + time"},
    {value: "time", label: "Time only"},
    {value: "name", label: "Prayer name only"},
    {value: "countdown", label: "Countdown"},
    {value: "name-countdown", label: "Prayer + countdown"},
    {value: "arabic", label: "Arabic prayer + time"},
    {value: "time-name", label: "Time + prayer"},
    {value: "icon", label: "Icon only"},
    {value: "custom", label: "Custom format…"}
];

function barTemplate(settings) {
    var templates = {"name-time": "{name} {time}", "time": "{time}", "name": "{name}",
        "countdown": "{remaining}", "name-countdown": "{name} in {remaining}",
        "arabic": "{arabic} {time}", "time-name": "{time} · {name}", "icon": ""};
    var preset = settings.barPreset || "name-time";
    if (preset === "custom") return String(settings.barFormat || "{name} {h}::{mm}:{ampm}").slice(0, 200);
    return templates[preset] === undefined ? templates["name-time"] : templates[preset];
}

function formatBar(row, report, now, settings) {
    var template = barTemplate(settings);
    if (!template) return "";
    if (!row) return "Awqat";
    var parts = row.time24.split(":");
    var hour = Number(parts[0]);
    var h12 = hour % 12 || 12;
    var values = {name: row.name, arabic: row.arabic, short: row.name.slice(0, 3),
        time: timeLabel(row, settings.clock24 === true), time24: row.time24,
        time12: row.time12 + " " + row.period, h: h12, hh: (h12 < 10 ? "0" : "") + h12,
        H: hour, HH: parts[0], mm: parts[1], ampm: row.period.toLowerCase(), AMPM: row.period,
        remaining: countdown(row.epoch - now, true), remainingClock: countdown(row.epoch - now, false),
        city: report && report.location ? report.location.name : "", icon: "☾"};
    return template.replace(/\{([a-zA-Z][a-zA-Z0-9]*)\}/g, function(match, key) {
        return values[key] === undefined ? match : String(values[key]);
    });
}

function duePrayer(report, now, alerted) {
    if (!report) return null;
    for (var i = report.events.length - 1; i >= 0; i--) {
        var event = report.events[i];
        var key = event.name + ":" + event.epoch;
        if (event.prayer && event.epoch <= now && now - event.epoch <= 90 && alerted.indexOf(key) < 0)
            return event;
    }
    return null;
}

function barOptions(row, report, now, settings) {
    return barPresets.map(function(preset) {
        var values = {barPreset: preset.value, barFormat: settings.barFormat, clock24: settings.clock24};
        var example = preset.value === "icon" ? "☾" : formatBar(row, report, now, values);
        return {value: preset.value, title: preset.label, example: example, label: preset.label + "  ·  " + example};
    });
}

function formatError(template) {
    var allowed = ["name", "arabic", "short", "time", "time24", "time12", "h", "hh", "H", "HH", "mm", "ampm", "AMPM", "remaining", "remainingClock", "city", "icon"];
    var unknown = String(template).match(/\{[^}]*\}/g) || [];
    for (var i = 0; i < unknown.length; i++) {
        if (allowed.indexOf(unknown[i].slice(1, -1)) < 0) return "Unknown token " + unknown[i] + ". Check the token list below.";
    }
    if (String(template).replace(/\{[^}]*\}/g, "").match(/[{}]/)) return "Close each token with a matching { and }.";
    if (!String(template).trim()) return "Enter a format, or choose Icon only.";
    return "";
}
