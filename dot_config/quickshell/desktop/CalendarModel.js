// Pure date and format math for the Calendar popup and Google Calendar event model.
// Everything here is locale- and Qt-free for clean evaluation.

var MS_PER_DAY = 86400000;
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];

function pad2(value) {
  var n = Number(value);
  return (n < 10 ? "0" : "") + n;
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day);
}

function keyForDate(date) {
  if (!date) return "";
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate());
}

function dateFromKey(key, fallback) {
  if (!key || typeof key !== "string") return fallback || new Date();
  var parts = key.split("-");
  if (parts.length !== 3) return fallback || new Date();
  var y = parseInt(parts[0], 10);
  var m = parseInt(parts[1], 10) - 1;
  var d = parseInt(parts[2], 10);
  if (isNaN(y) || isNaN(m) || isNaN(d)) return fallback || new Date();
  return new Date(y, m, d);
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null;
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null;

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase();
  if (text === "") return null;

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i;

  var parsed = parseInt(text, 10);
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null;
}

function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value);
  if (configured !== null) return configured;
  var fallbackStart = coerceWeekStart(fallback);
  return fallbackStart === null ? 1 : fallbackStart;
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1);
  var out = [];
  for (var i = 0; i < 7; i++) out.push((start + i) % 7);
  return out;
}

// ISO-8601 week number: the week owning the Thursday of that date's Monday-based week.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day));
  var weekday = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - weekday);
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7);
}

function monthGrid(year, month, weekStart, todayKey, eventIndex) {
  var start = normalizedWeekStart(weekStart, 1);
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7;
  var cursor = new Date(year, month, 1 - leading);
  var today = String(todayKey || "");
  var weeks = [];

  for (var w = 0; w < 6; w++) {
    var days = [];
    var thursday = null;
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear();
      var cellMonth = cursor.getMonth();
      var cellDay = cursor.getDate();
      var weekday = cursor.getDay();
      var key = dateKey(cellYear, cellMonth, cellDay);
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay };
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        hasEvent: eventIndex ? !!eventIndex[key] : false,
        dots: eventIndex ? eventColors(eventIndex, key, 3) : []
      });
      cursor.setDate(cursor.getDate() + 1);
    }
    var anchor = thursday || days[0];
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    });
  }
  return weeks;
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1);
  return { year: target.getFullYear(), month: target.getMonth() };
}

function indexEventsByDate(events) {
  var index = {};
  if (!events || !events.length) return index;
  for (var i = 0; i < events.length; i++) {
    var event = events[i];
    var key = event && event.dateKey;
    if (!key) continue;
    if (!index[key]) index[key] = [];
    index[key].push(event);
  }
  return index;
}

function eventsForDateKey(index, dateKey) {
  if (!index || !dateKey) return [];
  return index[dateKey] || [];
}

function eventColors(index, dateKey, maxDots) {
  var events = eventsForDateKey(index, dateKey);
  if (!events || events.length === 0) return [];
  var seen = {};
  var out = [];
  var cap = maxDots && maxDots > 0 ? maxDots : 3;
  for (var i = 0; i < events.length; i++) {
    var color = events[i].color;
    if (color && !seen[color]) {
      seen[color] = true;
      out.push(color);
      if (out.length >= cap) break;
    }
  }
  return out;
}

function calendarsInDocument(doc) {
  var events = (doc && doc.events) || [];
  var seen = {};
  var out = [];
  for (var i = 0; i < events.length; i++) {
    var event = events[i];
    var id = event && event.calendarId;
    if (!id || seen[id]) continue;
    seen[id] = true;
    out.push({
      id: id,
      name: event.calendarName || id,
      color: event.color || "#9e9e9e"
    });
  }
  return out.sort(function(a, b) {
    return a.name.localeCompare(b.name);
  });
}

function filterEvents(events, hiddenCalendars, showWorkingLocation, showDeclined) {
  if (!events || !events.length) return [];
  var hidden = hiddenCalendars || {};
  var out = [];
  for (var i = 0; i < events.length; i++) {
    var event = events[i];
    if (!event) continue;
    if (event.calendarId && hidden[event.calendarId]) continue;
    if (!showWorkingLocation && event.eventType === "workingLocation") continue;
    if (!showDeclined && event.responseStatus === "declined") continue;
    out.push(event);
  }
  return out;
}

function nextEvent(events, nowMs) {
  if (!events || !events.length) return null;
  var now = typeof nowMs === "number" ? nowMs : Date.now();
  var candidates = [];
  for (var i = 0; i < events.length; i++) {
    var event = events[i];
    if (!event || event.allDay) continue;
    var startMs = Date.parse(event.start);
    var endMs = Date.parse(event.end || event.start);
    if (isNaN(startMs)) continue;
    // An event currently in flight or in the future
    if (endMs > now) {
      candidates.push({ event: event, startMs: startMs });
    }
  }
  if (candidates.length === 0) return null;
  candidates.sort(function(a, b) { return a.startMs - b.startMs; });
  return candidates[0].event;
}

function millisUntil(event, nowMs) {
  if (!event || !event.start) return 0;
  var startMs = Date.parse(event.start);
  if (isNaN(startMs)) return 0;
  var now = typeof nowMs === "number" ? nowMs : Date.now();
  return startMs - now;
}

function formatCountdown(msUntil) {
  if (typeof msUntil !== "number") return "";
  if (msUntil <= 0) return "now";
  var totalMins = Math.round(msUntil / 60000);
  if (totalMins < 1) return "in <1m";
  if (totalMins < 60) return "in " + totalMins + "m";
  var hours = Math.floor(totalMins / 60);
  var mins = totalMins % 60;
  if (mins === 0) return "in " + hours + "h";
  return "in " + hours + "h " + mins + "m";
}

function formatTimeRange(startIso, endIso, allDay) {
  if (allDay) return "All day";
  if (!startIso) return "";
  var start = new Date(startIso);
  var end = endIso ? new Date(endIso) : null;
  function fmtTime(d) {
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
  }
  if (!end) return fmtTime(start);
  return fmtTime(start) + " - " + fmtTime(end);
}

function safeUrl(url) {
  if (!url || typeof url !== "string") return "";
  var text = url.trim();
  if (!text.startsWith("https://")) return "";
  if (/[\s"'<>]/.test(text)) return "";
  return text;
}

function isMeetingJoinable(event, nowMs) {
  if (!event || !event.meetingUrl) return false;
  var url = safeUrl(event.meetingUrl);
  if (!url) return false;
  var now = typeof nowMs === "number" ? nowMs : Date.now();
  var startMs = Date.parse(event.start);
  var endMs = Date.parse(event.end || event.start);
  if (isNaN(startMs)) return true;
  // Available 15 mins before start up to 15 mins after end
  var leadMs = 15 * 60000;
  return now >= (startMs - leadMs) && now <= (endMs + leadMs);
}

function syncState(doc, nowMs, syncIntervalSeconds) {
  if (!doc) return "empty";
  if (!doc.syncedAt) return "stale";
  var synced = Date.parse(doc.syncedAt);
  if (isNaN(synced)) return "stale";
  var now = typeof nowMs === "number" ? nowMs : Date.now();
  var intervalMs = (syncIntervalSeconds || 300) * 1000;
  if (now - synced > intervalMs * 4) return "stale";
  return "fresh";
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    dateFromKey: dateFromKey,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    indexEventsByDate: indexEventsByDate,
    eventsForDateKey: eventsForDateKey,
    eventColors: eventColors,
    calendarsInDocument: calendarsInDocument,
    filterEvents: filterEvents,
    nextEvent: nextEvent,
    millisUntil: millisUntil,
    formatCountdown: formatCountdown,
    formatTimeRange: formatTimeRange,
    safeUrl: safeUrl,
    isMeetingJoinable: isMeetingJoinable,
    syncState: syncState
  };
}
