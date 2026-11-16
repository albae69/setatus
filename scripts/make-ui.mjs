#!/usr/bin/env node
// Setatus UI in FigCraft: menu bar strip, right-click menu cascade, popover panel.
// Usage: node scripts/make-ui.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";

const CLI = "/Users/bae/figcraft-cli/figcraft-cli";
const OUT = "Design/setatus-ui.figcraft";

const FONT = "Helvetica Neue";
const MONO = "Menlo";
const INK = "#1D1D1F";
const SUB = "#6E6E73";
const FAINT = "#8E8E93";
const ACCENT = "#007AFF";
const TRACK = "#E3E3E8";
const GREEN = "#34C759";
const YELLOW = "#FFCC00";
const MENU_BG = "#2C2C2E";
const MENU_TEXT = "#F2F2F7";
const MENU_DIM = "#98989F";
const MENU_SEP = "#3D3D3F";
const BAR_BG = "#26262A";

const cmds = [];
let seq = 0;
const as = (p) => `${p}${++seq}`;

const layer = (type, params) => {
  const id = as(type[0]);
  cmds.push({ command: "node.create", as: id, params: { type, ...params } });
  return { $ref: id };
};

const frame = (name, parent, props, size = {}, extra = {}) => {
  const merged = {
    fill: "none",
    layout: "vertical",
    sizingH: "fill",
    sizingV: "hug",
    ...props,
  };
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
  const { size = 12, color = INK, font = FONT, weight = "Regular", lh, width, align, name } = opts;
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
      fill: color,
      textAlign: align,
      textAutoResize: width ? "height" : "widthAndHeight",
    },
  });
};

const hstack = (name, parent, opts = {}) =>
  frame(name, parent, { layout: "horizontal", crossAlign: "center", ...opts });

const vstack = (name, parent, opts = {}) =>
  frame(name, parent, { layout: "vertical", ...opts });

const caption = (parent, t) => text(parent, t, { size: 11, color: SUB });

const W_INNER = 292; // 320 panel − 14 padding each side

const meter = (parent, ratio, color) => {
  const track = frame("meter", parent, {
    layout: null,
    width: W_INNER,
    height: 5,
    cornerRadius: 2.5,
    fill: TRACK,
    clip: true,
  });
  rect(track, Math.max(2, W_INNER * ratio), 5, { fill: color, cornerRadius: 2.5 });
};

const barRow = (parent, title, value, ratio, color) => {
  const row = vstack("row", parent, { gap: 4 });
  const line = hstack("line", row, { mainAlign: "spaceBetween" });
  text(line, title, { size: 12 });
  text(line, value, { size: 12, font: MONO, weight: "Regular" });
  meter(row, ratio, color);
};

const plainRow = (parent, title, value) => {
  const line = hstack("row", parent, { mainAlign: "spaceBetween" });
  text(line, title, { size: 12 });
  text(line, value, { size: 12, font: MONO });
};

const divider = (parent) => rect(parent, W_INNER, 1, { fill: "#0000001A" });

const sectionHeader = (parent, title, action) => {
  const line = hstack("header", parent, { mainAlign: "spaceBetween" });
  caption(line, title);
  if (action) text(line, action, { size: 11, color: FAINT });
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

text(bar, "OC  1% CPU 12% GPU 13% RAM 62% 2400 \u21931.2M \u2191240K", {
  size: 9,
  font: MONO,
  weight: "Medium",
  color: "#FFFFFF",
  lh: 12,
  width: 420,
  align: "right",
  x: 856,
  y: 6,
  name: "Setatus title",
});

const battery = layer("frame", { name: "Battery", parent: bar, x: 1284, y: 6, width: 24, height: 12, props: { fill: "none", layout: null } });
rect(battery, 22, 11, { fill: "none", stroke: "#FFFFFF99", strokeWeight: 1, cornerRadius: 3 });
rect(battery, 14, 7, { fill: "#FFFFFF", cornerRadius: 1.5 }, { x: 3, y: 2 });
rect(battery, 2, 5, { fill: "#FFFFFF99", cornerRadius: 1 }, { x: 22.5, y: 3 });

for (const [d, o] of [
  ["M0 4 Q8 -3 16 4", { x: 1314, y: 9 }],
  ["M3 7 Q8 3 13 7", { x: 1314, y: 9 }],
]) {
  layer("vector", { parent: bar, path: d, width: 16, height: 10, x: o.x, y: o.y, name: "wifi", props: { fill: "none", stroke: "#FFFFFF", strokeWeight: 1.5 } });
}
rect(bar, 3, 3, { fill: "#FFFFFF", cornerRadius: 1.5 }, { x: 1321, y: 19 });

const cc = layer("frame", { name: "Control center", parent: bar, x: 1338, y: 5, width: 14, height: 14, props: { fill: "none", layout: null } });
rect(cc, 5, 5, { fill: "none", stroke: "#FFFFFF", strokeWeight: 1, cornerRadius: 2.5 }, { x: 0, y: 1 });
rect(cc, 7, 2, { fill: "#FFFFFF", cornerRadius: 1 }, { x: 7, y: 2.5 });
rect(cc, 5, 5, { fill: "none", stroke: "#FFFFFF", strokeWeight: 1, cornerRadius: 2.5 }, { x: 9, y: 8 });
rect(cc, 7, 2, { fill: "#FFFFFF", cornerRadius: 1 }, { x: 0, y: 9.5 });

text(bar, "Mon 14:32", { size: 12, color: "#FFFFFF", width: 68, align: "right", x: 1360, y: 4, name: "Clock" });

// ---------------------------------------------------------------- NSMenu
const menuRow = (parent, label, extra, opts = {}) => {
  const { check, color, ...frameOpts } = opts;
  const row = hstack("item", parent, {
    height: 22,
    padding: [0, 10],
    mainAlign: "spaceBetween",
    ...frameOpts,
  });
  const left = hstack("left", row, { gap: 6, sizingH: "hug", mainAlign: "min" });
  if (check) text(left, check, { size: 12, color: MENU_TEXT, lh: 14, width: 12 });
  text(left, label, { size: 13, color: color || MENU_TEXT, lh: 15 });
  if (extra) text(row, extra, { size: 13, color: MENU_DIM, lh: 15 });
  return row;
};

const menuSep = (parent, width) => {
  const wrap = vstack("separator", parent, { height: 9, mainAlign: "center", crossAlign: "center", sizingH: "fill" });
  rect(wrap, width, 1, { fill: MENU_SEP, sizingH: "fixed" });
};

const menuPanel = (name, parent, x, y, width, height) =>
  layer("frame", {
    name,
    x,
    y,
    width,
    height,
    props: {
      fill: MENU_BG,
      layout: "vertical",
      padding: [4, 0],
      gap: 0,
      cornerRadius: 10,
      clip: true,
      effects: [{ type: "dropShadow", color: "#00000055", offset: [0, 8], radius: 24, spread: -4 }],
    },
  });

const menu = menuPanel("Right-click menu", null, 1040, 128, 210, 180);
menuRow(menu, "Refresh", "\u2318R");
menuRow(menu, "Fan Auto");
menuSep(menu, 210);
menuRow(menu, "Menu Bar", "\u25B8");
menuRow(menu, "Launch at Login", "\u2713");
menuSep(menu, 210);
menuRow(menu, "About Setatus");
menuRow(menu, "Quit Setatus", "\u2318Q");

const metricsMenu = menuPanel("Menu Bar submenu", null, 1254, 128 + 66, 220, 162);
for (const [label, detail] of [
  ["OpenCode limit", ""],
  ["CPU", "\u25B8"],
  ["GPU", "\u25B8"],
  ["RAM", ""],
  ["Fan speed", ""],
  ["Internet speed", ""],
  ["Power input", ""],
]) {
  menuRow(metricsMenu, label, detail, { check: label === "Power input" ? "" : "\u2713" });
}

const cpuMenu = menuPanel("CPU submenu", null, 1478, 128 + 88, 210, 83);
menuRow(cpuMenu, "Show in menu bar", "", { check: "\u2713" });
menuSep(cpuMenu, 210);
menuRow(cpuMenu, "Percent", "\u2713");
menuRow(cpuMenu, "Temperature");

// ---------------------------------------------------------------- popover
const panel = layer("frame", {
  name: "Popover",
  x: 560,
  y: 128,
  width: 320,
  props: {
    fill: "#FFFFFF",
    layout: "vertical",
    gap: 12,
    padding: 14,
    sizingH: "fixed",
    sizingV: "hug",
    clip: true,
    cornerRadius: 10,
    effects: [{ type: "dropShadow", color: "#00000033", offset: [0, 10], radius: 30, spread: -6 }],
  },
});

const headerRow = hstack("header", panel, { mainAlign: "spaceBetween" });
cmds.push({
  command: "image.place",
  as: as("img"),
  params: { parent: headerRow, path: "Assets/wordmark.png", width: 45, height: 15, name: "wordmark" },
});
text(headerRow, "\u21BB", { size: 13, color: SUB, name: "refresh" });

const limits = vstack("OpenCode limits", panel, { gap: 8 });
caption(limits, "OpenCode limits");
for (const [label, percent, eta] of [
  ["5 hours", 42, "in 3h 12m"],
  ["Week", 18, "in 6d 4h"],
  ["Month", 6, "in 21d"],
]) {
  const row = vstack("limit", limits, { gap: 4 });
  const line = hstack("line", row, { mainAlign: "spaceBetween" });
  text(line, label, { size: 12 });
  const right = hstack("value", line, { gap: 3, sizingH: "hug", mainAlign: "max" });
  text(right, `${percent}%`, { size: 12, font: MONO, weight: "Bold" });
  text(right, `\u00B7 ${eta}`, { size: 10, color: SUB });
  meter(row, percent / 100, GREEN);
}
text(limits, "Today  1,284 req \u00B7 12.4M tok \u00B7 $8.42", { size: 10, color: SUB, name: "Today" });

divider(panel);

const system = vstack("System", panel, { gap: 8 });
barRow(system, "CPU", "12% \u00B7 54 \u00B0C", 0.12, GREEN);
barRow(system, "GPU", "13% \u00B7 47 \u00B0C", 0.13, GREEN);
barRow(system, "RAM", "62%", 0.62, YELLOW);
plainRow(system, "Power", "28 W \u00B7 96 W \u00B7 80%");
plainRow(system, "Uptime", "4d 6h");
text(system, "SSD 41\u00B0C \u00B7 Battery 32\u00B0C", { size: 10, color: SUB, name: "extra temps" });

const fan = vstack("Fan", panel, { gap: 6 });
caption(fan, "Fan");
const fanLine = hstack("fan line", fan, { mainAlign: "spaceBetween" });
text(fanLine, "2400 rpm", { size: 12, font: MONO });
text(fanLine, "auto", { size: 10, color: SUB });
const slider = layer("frame", { name: "slider", parent: fan, width: W_INNER, height: 14, props: { fill: "none", layout: null } });
rect(slider, W_INNER, 4, { fill: TRACK, cornerRadius: 2 }, { x: 0, y: 5 });
rect(slider, W_INNER * 0.24, 4, { fill: ACCENT, cornerRadius: 2 }, { x: 0, y: 5 });
rect(slider, 14, 14, { fill: "#FFFFFF", cornerRadius: 7, stroke: "#0000001F", strokeWeight: 1 }, { x: W_INNER * 0.24 - 7, y: 0 });
const fanMeta = hstack("fan meta", fan, { mainAlign: "spaceBetween" });
text(fanMeta, "min 1200 \u00B7 max 6200 \u00B7 target 2400", { size: 10, color: SUB });
text(fanMeta, "Auto", { size: 10, color: ACCENT });

divider(panel);

const net = vstack("Internet", panel, { gap: 4 });
caption(net, "Internet");
for (const [arrow, label, value] of [
  ["\u2193", "Download", "1.2 MB/s"],
  ["\u2191", "Upload", "240 KB/s"],
]) {
  const line = hstack("flow", net, { gap: 6, mainAlign: "spaceBetween" });
  const left = hstack("left", line, { gap: 6, sizingH: "hug", mainAlign: "min" });
  text(left, arrow, { size: 12, color: SUB, width: 10, align: "center" });
  text(left, label, { size: 12 });
  text(line, value, { size: 12, font: MONO });
}
text(net, "Total \u2193 412.6 GB   \u2191 38.2 GB", { size: 10, font: MONO, color: SUB });
text(net, "IP 192.168.1.24", { size: 10, font: MONO, color: SUB });

divider(panel);

const ports = vstack("Dev ports", panel, { gap: 6 });
sectionHeader(ports, "Dev ports", "\u21BB");
const portList = vstack("port list", ports, { gap: 6, height: 110, sizingV: "fixed" });
for (const [port, proc, pid] of [
  [":3000", "next-server", 4821],
  [":5432", "postgres", 3902],
  [":8080", "vite", 7712],
]) {
  const line = hstack("port", portList, { gap: 6, mainAlign: "spaceBetween" });
  const left = hstack("left", line, { gap: 6, sizingH: "hug", mainAlign: "min" });
  text(left, port, { size: 12, font: MONO, width: 44 });
  text(left, proc, { size: 12 });
  text(left, `${pid}`, { size: 10, font: MONO, color: SUB });
  text(line, "\u2715", { size: 10, color: FAINT });
}

divider(panel);

const procs = vstack("Processes", panel, { gap: 6 });
sectionHeader(procs, "Processes", "\u21BB");
const procList = vstack("process list", procs, { gap: 6, height: 220, sizingV: "fixed" });
for (const [name, pid, cpu, mem] of [
  ["Safari", 4821, "12.4%", "862 MB"],
  ["Xcode", 3902, "4.1%", "1.2 GB"],
  ["Terminal", 7712, "0.8%", "124 MB"],
  ["Figma", 6120, "2.2%", "540 MB"],
]) {
  const line = hstack("process", procList, { mainAlign: "spaceBetween" });
  const left = vstack("left", line, { gap: 1, sizingH: "hug", mainAlign: "min" });
  text(left, name, { size: 12 });
  text(left, `${pid} \u00B7 ${cpu} \u00B7 ${mem}`, { size: 10, font: MONO, color: SUB });
  text(line, "\u2715", { size: 10, color: FAINT });
}

divider(panel);

text(panel, "Set API key", { size: 11, color: ACCENT, name: "Set API key" });
text(panel, "Updated 14:32", { size: 10, color: SUB, name: "footer" });

// ---------------------------------------------------------------- labels + page
const label = (t, x, y) => {
  cmds.push({
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
};
label("Menu bar", 40, 40);
label("Right-click menu", 1040, 104);
label("Menu Bar submenu", 1254, 170);
label("CPU submenu", 1478, 192);
label("Popover panel", 560, 104);

const script = [
  { command: "file.new" },
  { command: "page.rename", params: { name: "Setatus UI" } },
  { command: "page.setBackground", params: { color: "#F2F2F7" } },
  ...cmds,
];

mkdirSync("Design", { recursive: true });
writeFileSync("/tmp/setatus-ui.json", JSON.stringify(script, null, 1));
const log = execFileSync(CLI, ["run", "/tmp/setatus-ui.json", "--out", OUT], { encoding: "utf8" });
const fails = log.split("\n").filter((l) => l.includes('"ok":false'));
console.log(`UI -> ${OUT}`);
for (const f of fails) console.log("FAIL " + f);
if (fails.length) process.exit(1);
