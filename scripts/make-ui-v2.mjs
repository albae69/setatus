#!/usr/bin/env node
// Setatus UI v2: redesign of menu bar, popover and context menu.
// Usage: node scripts/make-ui-v2.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";

const CLI = "/Users/bae/figcraft-cli/figcraft-cli";
const OUT = "Design/setatus-ui-v2.figcraft";

const FONT = "Helvetica Neue";
const MONO = "Menlo";
const INK = "#1D1D1F";
const SUB = "#6E6E73";
const FAINT = "#AEAEB2";
const CARD = "#F5F5F7";
const LINE = "#E9E9EE";
const ACCENT = "#007AFF";
const GREEN = "#30B15A";
const AMBER = "#F0A020";
const MENU_BG = "#2C2C2E";
const MENU_TEXT = "#F2F2F7";
const MENU_DIM = "#98989F";
const MENU_SEP = "#3D3D3F";
const BAR_BG = "#26262A";

const cmds = [];
let seq = 0;
const ref = (p) => `${p}${++seq}`;

const layer = (type, params) => {
  const id = ref(type[0]);
  cmds.push({ command: "node.create", as: id, params: { type, ...params } });
  return { $ref: id };
};

const frame = (name, parent, props = {}, size = {}, extra = {}) => {
  const merged = { fill: "none", layout: "vertical", sizingH: "fill", sizingV: "hug", ...props };
  if (merged.layout) {
    merged.gap ??= 0;
    merged.padding ??= 0;
  } else {
    delete merged.sizingH;
    delete merged.sizingV;
  }
  return layer("frame", { name, parent, ...extra, ...size, props: merged });
};

const rect = (parent, width, height, props = {}, extra = {}) =>
  layer("rectangle", { parent, width, height, props: { fill: "none", ...props }, ...extra });

const text = (parent, t, opts = {}) => {
  const { size = 12, color = INK, font = FONT, weight = "Regular", lh, width, align, upper, ls, name } = opts;
  return layer("text", {
    parent,
    text: t,
    name: name || t.slice(0, 40),
    width,
    props: {
      fontFamily: font,
      fontStyle: weight,
      fontSize: size,
      lineHeight: lh ?? Math.round(size * 1.4),
      letterSpacing: ls,
      fill: color,
      textAlign: align,
      textCase: upper ? "upper" : undefined,
      textAutoResize: width ? "height" : "widthAndHeight",
    },
  });
};

const hstack = (name, parent, opts = {}) => frame(name, parent, { layout: "horizontal", crossAlign: "center", ...opts });
const vstack = (name, parent, opts = {}) => frame(name, parent, { layout: "vertical", ...opts });

const label = (parent, t) => text(parent, t, { size: 10, color: SUB, upper: true, ls: 0.6, lh: 13 });
const caption = (parent, t) => text(parent, t, { size: 10, color: SUB, lh: 13 });

const W_PANEL = 340;
const W_INNER = 308;

const meterBar = (parent, ratio, color, width = W_INNER, height = 4) => {
  const track = frame("meter", parent, { layout: null, width, height, cornerRadius: height / 2, fill: LINE, clip: true });
  rect(track, Math.max(2, width * ratio), height, { fill: color, cornerRadius: height / 2 });
  return track;
};

// ---------------------------------------------------------------- menu bar
const BAR_W = 1440;
const BAR_H = 24;
const bar = layer("frame", {
  name: "Menu bar",
  x: 40,
  y: 64,
  width: BAR_W,
  height: BAR_H,
  props: { fill: BAR_BG, layout: null, clip: true },
});

text(bar, "\uF8FF", { size: 14, color: "#FFFFFF", lh: 16, name: "Apple" });
for (const [i, item] of ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].entries()) {
  text(bar, item, {
    size: 13,
    color: "#FFFFFF",
    weight: item === "Finder" ? "Bold" : "Regular",
    lh: 16,
    x: [34, 88, 120, 164, 202, 238, 292][i],
    y: 4,
    name: `App ${item}`,
  });
}

text(bar, "OC 42% CPU 12% GPU 13% RAM 62% 2.4k \u21931.2M \u2191240K", {
  size: 9.5,
  font: MONO,
  weight: "Medium",
  color: "#FFFFFF",
  lh: 12,
  width: 400,
  align: "right",
  x: 876,
  y: 6,
  name: "Setatus title",
});

const battery = layer("frame", { name: "Battery", parent: bar, x: 1284, y: 6, width: 24, height: 12, props: { fill: "none", layout: null } });
rect(battery, 22, 11, { fill: "none", stroke: "#FFFFFF99", strokeWeight: 1, cornerRadius: 3 });
rect(battery, 14, 7, { fill: "#FFFFFF", cornerRadius: 1.5 }, { x: 3, y: 2 });
rect(battery, 2, 5, { fill: "#FFFFFF99", cornerRadius: 1 }, { x: 22.5, y: 3 });

for (const d of ["M0 4 Q8 -3 16 4", "M3 7 Q8 3 13 7"]) {
  layer("vector", { parent: bar, path: d, width: 16, height: 10, x: 1314, y: 9, name: "wifi", props: { fill: "none", stroke: "#FFFFFF", strokeWeight: 1.5 } });
}
rect(bar, 3, 3, { fill: "#FFFFFF", cornerRadius: 1.5 }, { x: 1321, y: 19 });

const cc = layer("frame", { name: "Control center", parent: bar, x: 1338, y: 5, width: 14, height: 14, props: { fill: "none", layout: null } });
rect(cc, 5, 5, { fill: "none", stroke: "#FFFFFF", strokeWeight: 1, cornerRadius: 2.5 }, { x: 0, y: 1 });
rect(cc, 7, 2, { fill: "#FFFFFF", cornerRadius: 1 }, { x: 7, y: 2.5 });
rect(cc, 5, 5, { fill: "none", stroke: "#FFFFFF", strokeWeight: 1, cornerRadius: 2.5 }, { x: 9, y: 8 });
rect(cc, 7, 2, { fill: "#FFFFFF", cornerRadius: 1 }, { x: 0, y: 9.5 });

text(bar, "Mon 14:32", { size: 12, color: "#FFFFFF", width: 68, align: "right", x: 1360, y: 4, name: "Clock" });

// ---------------------------------------------------------------- context menu
const menuRow = (parent, nameLabel, extra, opts = {}) => {
  const { check, ...frameOpts } = opts;
  const row = hstack("item", parent, { height: 24, padding: [0, 12], mainAlign: "spaceBetween", ...frameOpts });
  const left = hstack("left", row, { gap: 8, sizingH: "hug", mainAlign: "min" });
  if (check !== undefined) text(left, check, { size: 12, color: MENU_TEXT, lh: 14, width: 12 });
  text(left, nameLabel, { size: 13, color: MENU_TEXT, lh: 15 });
  if (extra) text(row, extra, { size: 13, color: MENU_DIM, lh: 15 });
};

const menuSep = (parent) => {
  const wrap = vstack("separator", parent, { height: 9, mainAlign: "center", crossAlign: "center" });
  rect(wrap, 216, 1, { fill: MENU_SEP });
};

const menuPanel = (name, x, y, width, height) =>
  layer("frame", {
    name,
    x,
    y,
    width,
    height,
    props: {
      fill: MENU_BG,
      layout: "vertical",
      padding: [5, 0],
      cornerRadius: 10,
      clip: true,
      effects: [{ type: "dropShadow", color: "#00000055", offset: [0, 8], radius: 24, spread: -4 }],
    },
  });

const menu = menuPanel("Context menu", 1080, 128, 216, 154);
menuRow(menu, "Refresh", "\u2318R");
menuRow(menu, "Menu Bar", "\u25B8");
menuRow(menu, "Launch at Login", "", { check: "\u2713" });
menuSep(menu);
menuRow(menu, "About Setatus");
menuRow(menu, "Quit Setatus", "\u2318Q");

const metricsMenu = menuPanel("Menu Bar submenu", 1304, 180, 224, 186);
for (const [nameLabel, extra] of [
  ["OpenCode limit", ""],
  ["CPU", "\u25B8"],
  ["GPU", "\u25B8"],
  ["RAM", ""],
  ["Fan speed", ""],
  ["Internet speed", ""],
  ["Power input", ""],
]) menuRow(metricsMenu, nameLabel, extra, { check: nameLabel === "Power input" ? "" : "\u2713" });
menuSep(metricsMenu);
menuRow(metricsMenu, "Reset to Defaults");

// ---------------------------------------------------------------- popover
const panel = layer("frame", {
  name: "Popover",
  x: 40,
  y: 128,
  width: W_PANEL,
  props: {
    fill: "#FFFFFF",
    layout: "vertical",
    gap: 16,
    padding: 16,
    sizingH: "fixed",
    sizingV: "hug",
    clip: true,
    cornerRadius: 12,
    stroke: "#00000012",
    strokeWeight: 1,
    strokeAlign: "outside",
    effects: [{ type: "dropShadow", color: "#00000029", offset: [0, 10], radius: 30, spread: -6 }],
  },
});

const headerRow = hstack("Header", panel, { mainAlign: "spaceBetween" });
cmds.push({ command: "image.place", as: ref("img"), params: { parent: headerRow, path: "Assets/wordmark.png", width: 45, height: 15, name: "wordmark" } });
const headerMeta = hstack("meta", headerRow, { gap: 8, sizingH: "hug", mainAlign: "max" });
text(headerMeta, "Updated 14:32", { size: 10, color: FAINT, font: MONO });
text(headerMeta, "\u21BB", { size: 12, color: SUB });

const usage = vstack("Usage card", panel, { gap: 10, padding: 12, fill: CARD, cornerRadius: 10 });
const usageTop = hstack("top", usage, { mainAlign: "spaceBetween", crossAlign: "min" });
const usageHero = vstack("hero", usageTop, { gap: 2, sizingH: "hug", mainAlign: "min" });
label(usageHero, "OpenCode \u00B7 5 hours");
const heroLine = hstack("hero line", usageHero, { gap: 8, sizingH: "hug", crossAlign: "baseline", mainAlign: "min" });
text(heroLine, "42%", { size: 30, weight: "Medium", font: MONO, lh: 34 });
text(heroLine, "of 5h window", { size: 10, color: SUB });
text(usageTop, "resets in 3h 12m", { size: 10, color: SUB });
meterBar(usage, 0.42, GREEN, W_INNER - 24, 5);

const usageSplit = hstack("windows", usage, { gap: 16 });
for (const [nameLabel, percent, eta] of [["Week", 18, "resets in 6d 4h"], ["Month", 6, "resets in 21d"]]) {
  const col = vstack("window", usageSplit, { gap: 4, sizingH: "fill" });
  const line = hstack("line", col, { mainAlign: "spaceBetween" });
  text(line, nameLabel, { size: 11, color: SUB });
  text(line, `${percent}%`, { size: 11, font: MONO, color: INK });
  meterBar(col, percent / 100, percent > 60 ? AMBER : GREEN, 134, 3);
  text(col, eta, { size: 9, color: FAINT });
}

const system = vstack("System", panel, { gap: 8 });
const tiles = hstack("tiles", system, { gap: 7 });
for (const [nameLabel, value, detail, ratio, color] of [
  ["CPU", "12%", "54 \u00B0C", 0.12, GREEN],
  ["GPU", "13%", "47 \u00B0C", 0.13, GREEN],
  ["RAM", "62%", "9.9 / 16 GB", 0.62, AMBER],
]) {
  const tile = vstack("tile", tiles, { gap: 6, padding: 10, fill: CARD, cornerRadius: 8, width: 98, height: 76, sizingH: "fixed", sizingV: "fixed" });
  label(tile, nameLabel);
  const line = hstack("value line", tile, { mainAlign: "spaceBetween", crossAlign: "baseline" });
  text(line, value, { size: 17, weight: "Medium", font: MONO, lh: 20 });
  text(line, detail, { size: 9, color: FAINT });
  meterBar(tile, ratio, color, 78, 3);
}

const sysLine1 = hstack("power", system, { mainAlign: "spaceBetween" });
text(sysLine1, "Power", { size: 11, color: SUB });
text(sysLine1, "28 W in \u00B7 96 W adapter \u00B7 80%", { size: 11, font: MONO });
const sysLine2 = hstack("uptime", system, { mainAlign: "spaceBetween" });
text(sysLine2, "Uptime", { size: 11, color: SUB });
text(sysLine2, "4d 6h \u00B7 SSD 41\u00B0C \u00B7 Battery 32\u00B0C", { size: 11, font: MONO, color: SUB });

const fan = vstack("Fan", panel, { gap: 8, padding: 12, fill: CARD, cornerRadius: 10 });
const fanTop = hstack("fan top", fan, { mainAlign: "spaceBetween", crossAlign: "min" });
const fanHero = vstack("hero", fanTop, { gap: 2, sizingH: "hug", mainAlign: "min" });
label(fanHero, "Fan");
const fanLine = hstack("fan value", fanHero, { gap: 6, sizingH: "hug", crossAlign: "baseline", mainAlign: "min" });
text(fanLine, "2400", { size: 20, weight: "Medium", font: MONO, lh: 24 });
text(fanLine, "rpm", { size: 10, color: SUB, lh: 13 });
const pill = hstack("pill", fanTop, { gap: 4, padding: [3, 8], fill: "#FFFFFF", cornerRadius: 9, sizingH: "hug" });
rect(pill, 6, 6, { fill: GREEN, cornerRadius: 3 });
text(pill, "Auto", { size: 10, color: INK });

const slider = layer("frame", { name: "slider", parent: fan, width: W_INNER - 24, height: 14, props: { fill: "none", layout: null } });
rect(slider, W_INNER - 24, 4, { fill: LINE, cornerRadius: 2 }, { x: 0, y: 5 });
rect(slider, (W_INNER - 24) * 0.24, 4, { fill: ACCENT, cornerRadius: 2 }, { x: 0, y: 5 });
rect(slider, 14, 14, { fill: "#FFFFFF", cornerRadius: 7, stroke: "#00000026", strokeWeight: 1 }, { x: (W_INNER - 24) * 0.24 - 7, y: 0 });

const fanFoot = hstack("fan foot", fan, { mainAlign: "spaceBetween" });
text(fanFoot, "min 1200", { size: 9, color: FAINT });
text(fanFoot, "target 2400", { size: 9, color: FAINT });
text(fanFoot, "max 6200", { size: 9, color: FAINT });

const net = vstack("Internet", panel, { gap: 10, padding: 12, fill: CARD, cornerRadius: 10 });
const netCols = hstack("columns", net, { gap: 12 });
for (const [arrow, nameLabel, value] of [
  ["\u2193", "Download", "1.2 MB/s"],
  ["\u2191", "Upload", "240 KB/s"],
]) {
  const col = vstack("col", netCols, { gap: 2, sizingH: "fill", mainAlign: "min" });
  label(col, `${arrow} ${nameLabel}`);
  text(col, value, { size: 16, weight: "Medium", font: MONO, lh: 20 });
}
const netFoot = hstack("net foot", net, { mainAlign: "spaceBetween" });
text(netFoot, "412.6 GB in \u00B7 38.2 GB out", { size: 9, color: FAINT, font: MONO });
text(netFoot, "192.168.1.24", { size: 9, color: FAINT, font: MONO });

const activity = vstack("Activity", panel, { gap: 8, padding: 12, fill: CARD, cornerRadius: 10 });
const actHead = hstack("head", activity, { mainAlign: "spaceBetween" });
label(actHead, "Activity");
const segmented = hstack("segmented", actHead, { gap: 2, padding: 2, fill: "#EDEDF2", cornerRadius: 7, sizingH: "hug" });
const segOn = hstack("seg on", segmented, { padding: [2, 8], fill: "#FFFFFF", cornerRadius: 5, sizingH: "hug" });
text(segOn, "Ports 3", { size: 9, color: INK, weight: "Medium" });
const segOff = hstack("seg off", segmented, { padding: [2, 8], sizingH: "hug" });
text(segOff, "Processes 4", { size: 9, color: SUB });

const rows = vstack("rows", activity, { gap: 0 });
for (const [nameLabel, meta, danger] of [
  ["next-server", ":3000 \u00B7 4821 \u00B7 12.4%", false],
  ["postgres", ":5432 \u00B7 3902 \u00B7 0.4%", false],
  ["vite", ":8080 \u00B7 7712 \u00B7 0.8%", true],
]) {
  const row = hstack("row", rows, { height: 30, mainAlign: "spaceBetween" });
  const left = hstack("left", row, { gap: 8, sizingH: "hug", mainAlign: "min" });
  text(left, nameLabel, { size: 11, weight: "Medium" });
  text(left, meta, { size: 9, font: MONO, color: FAINT });
  text(row, "\u2715", { size: 9, color: danger ? FAINT : "#C7C7CC" });
}

const footer = hstack("Footer", panel, { mainAlign: "spaceBetween" });
text(footer, "Set API key", { size: 11, color: ACCENT });
text(footer, "\u2699 Preferences", { size: 11, color: SUB });

// ---------------------------------------------------------------- states + notes
const confirm = layer("frame", {
  name: "Activity \u00B7 confirm state",
  x: 400,
  y: 128,
  width: 308,
  props: { fill: CARD, layout: "vertical", gap: 8, padding: 12, cornerRadius: 10, sizingH: "fixed", sizingV: "hug" },
});
const confirmHead = hstack("head", confirm, { mainAlign: "spaceBetween" });
label(confirmHead, "Kill process");
const confirmRow = hstack("row", confirm, { height: 28, mainAlign: "spaceBetween" });
const confirmLeft = vstack("left", confirmRow, { gap: 1, sizingH: "hug", mainAlign: "min" });
text(confirmLeft, "vite \u00B7 :8080", { size: 11, weight: "Medium" });
text(confirmLeft, "pid 7712 \u00B7 0.8% \u00B7 124 MB", { size: 9, font: MONO, color: FAINT });
const confirmActions = hstack("actions", confirmRow, { gap: 8, sizingH: "hug" });
text(confirmActions, "Cancel", { size: 10, color: SUB });
text(confirmActions, "SIGTERM", { size: 10, color: "#E0352B", weight: "Medium" });

const notes = layer("frame", {
  name: "Notes",
  x: 736,
  y: 128,
  width: 320,
  props: { fill: "none", layout: "vertical", gap: 10, padding: 0, sizingH: "fixed", sizingV: "hug" },
});
text(notes, "Redesign notes", { size: 15, weight: "Medium" });
for (const line of [
  "Hierarchy: one hero number (5h window) instead of three equal limit rows. Week and month drop to secondary columns.",
  "Quieter surfaces: dividers replaced by cards on one 16 gap; semantic colour only when a value is high (RAM 62% amber).",
  "System metrics become a 3-tile grid so CPU, GPU and RAM read at a glance; power, uptime and sensors collapse to two lines.",
  "Ports and processes merge into one Activity card with a segmented switch and counts, so the popover stays one screen tall.",
  "Destructive kill stays behind a row action and an inline SIGTERM confirm; no accidental two-step menus.",
  "Menu bar keeps its strings but pads values consistently (2.4k fan, aligned percentages), so it stops jittering every tick.",
]) {
  const row = hstack("note", notes, { gap: 6, crossAlign: "min" });
  rect(row, 4, 4, { fill: ACCENT, cornerRadius: 2 }, { y: 5 });
  text(row, line, { size: 11, color: SUB, lh: 16, width: 306 });
}

const typeSpec = vstack("Type + colour", notes, { gap: 6 });
label(typeSpec, "Type + colour");
text(typeSpec, "Helvetica Neue 11 / 12 / 17 / 30 \u00B7 Menlo for numbers", { size: 10, color: SUB });
const swatches = hstack("swatches", typeSpec, { gap: 6 });
for (const c of [INK, SUB, FAINT, GREEN, AMBER, ACCENT, CARD]) {
  rect(swatches, 22, 22, { fill: c, cornerRadius: 5, stroke: "#00000012", strokeWeight: 1 });
}

const pageLabel = (t, x, y) => cmds.push({
  command: "node.create",
  params: {
    type: "text",
    text: t,
    x,
    y,
    name: t,
    props: { fontFamily: FONT, fontStyle: "Medium", fontSize: 11, fill: FAINT, textAutoResize: "widthAndHeight" },
  },
});
pageLabel("Menu bar", 40, 40);
pageLabel("Popover \u2014 redesigned", 40, 104);
pageLabel("Activity \u2014 confirm state", 400, 104);
pageLabel("Context menu", 1080, 104);
pageLabel("Menu Bar submenu", 1304, 156);

const script = [
  { command: "file.new" },
  { command: "page.rename", params: { name: "Setatus UI v2" } },
  { command: "page.setBackground", params: { color: "#F2F2F7" } },
  ...cmds,
];

mkdirSync("Design", { recursive: true });
writeFileSync("/tmp/setatus-ui-v2.json", JSON.stringify(script, null, 1));
const log = execFileSync(CLI, ["run", "/tmp/setatus-ui-v2.json", "--out", OUT], { encoding: "utf8" });
const fails = log.split("\n").filter((l) => l.includes('"ok":false'));
console.log(`UI v2 -> ${OUT}`);
for (const f of fails) console.log("FAIL " + f);
if (fails.length) process.exit(1);
