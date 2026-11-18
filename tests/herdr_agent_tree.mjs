// Renders the Herdr mods (agent-tree and compact workspace chrome) under node
// against stand-ins for Herdr's modules. Run by test_herdr_agent_tree.sh.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "agent-tree-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));

// The mods import bare "gpui-kit", "gpui-base" and "herdr"; node finds these
// stand-ins in node_modules beside copies of them.
const stubs = {
  // Elements record the calls made on them; child() refuses what GPUI would.
  "gpui-kit": `
    export function element(tag, arg) {
      const node = { tag, arg, calls: {}, mouseDown: {}, kids: [] };
      const self = new Proxy(node, {
        get(_target, prop) {
          if (typeof prop === "symbol" || prop === "then") return undefined;
          if (prop === "prop") return undefined;
          if (prop === "node") return node;
          if (prop === "child") return (c) => {
            if (c == null || typeof c === "boolean") throw new Error("child(" + c + ")");
            node.kids.push(c);
            return self;
          };
          if (prop === "children") return (cs) => { cs.forEach((c) => self.child(c)); return self; };
          if (prop === "when") return (cond, f) => (cond ? f(self) : self);
          if (prop === "hover") return (f) => { f(element("style")); return self; };
          if (prop === "on_mouse_down") return (btn, f) => { node.mouseDown[btn] = f; return self; };
          return (...args) => { node.calls[prop] = args; return self; };
        },
      });
      return self;
    }
    export const div = () => element("div");
    export const svg = (p) => element("svg", p);
    export const image = (p) => element("image", p);
    export class View {}
  `,
  "gpui-base": `
    import { element } from "gpui-kit";
    export const v_flex = () => element("v_flex");
    export const h_flex = () => element("h_flex");
    export const InputState = { new: () => ({
      text: "", value() { return this.text; }, set_value(text) { this.text = text; }, on() {}, focus() {},
    }) };
    export const Input = { new: () => element("input") };
    export class ScrollHandle {
      static new() { return new ScrollHandle(); }
      scroll_to_item() {}
    }
  `,
  herdr: `
    const s = () => globalThis.herdr;
    export const agents = () => s().agents;
    export const terminals = () => s().terminals;
    export const panes = () => s().panes;
    export const spaces = () => s().spaces;
    export const machines = () => s().machines;
    export const props = () => s().props;
    export const home = () => "/Users/eric";
    export const focused = () => s().focused;
    export const layout = () => s().layout;
    export const window = () => s().window ?? { platform: "linux" };
    export const settings = () => ({ zoom: 1 });
    export const updates = () => ({ app: { version: "0.1.15", ready: "0.1.16", updates: true } });
    export const keys = () => [{ section: "global", keys: "cmd-k", action: "app.palette" }];
    // Every color is its own name, so tests can tell them apart.
    export const theme = () => new Proxy({}, { get: (_t, k) => "#" + String(k) });
    export const shared = (k) => s().shared[k];
    export const setShared = (k, v) => { s().shared[k] = v; };
    export const setAgentOrder = (list) => { s().order = list; };
    export const run = (name, args) => { s().ran.push([name, args]); return null; };
    export const openOverlay = (spec) => { s().overlays.push(spec); return "ov1"; };
    export const closeOverlay = (id) => { s().closed.push(id); return null; };
    export const knownAgents = async () => s().knownAgents;
    export const pickFolder = async () => "/Users/eric/src/picked";
    export const checking = () => false;
    export const exec = async (cmd, args, opts) => s().exec(cmd, args, opts);
    export const hc = async (args) => s().hc(args);
  `,
};
for (const [name, source] of Object.entries(stubs)) {
  const dir = path.join(tmp, "node_modules", name);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "package.json"), JSON.stringify({ name, type: "module", main: "index.js" }));
  fs.writeFileSync(path.join(dir, "index.js"), source);
}

for (const modName of ["agent-tree", "session-menu", "open-folder", "tab-bar", "pane-header", "sidebar-footer", "status-bar"]) {
  const src = path.join(root, "herdr/mods", modName);
  const dst = path.join(tmp, "mods", modName);
  fs.mkdirSync(dst, { recursive: true });
  fs.writeFileSync(path.join(dst, "package.json"), JSON.stringify({ type: "module" }));
  for (const file of fs.readdirSync(src)) {
    if (file.endsWith(".js")) fs.copyFileSync(path.join(src, file), path.join(dst, file));
  }
}

const loadMod = (modName, file = "main.js") => import(pathToFileURL(path.join(tmp, "mods", modName, file)));
const { default: AgentTree } = await loadMod("agent-tree");
const { folderLabel, repoFolder, repoName } = await loadMod("agent-tree", "tree.js");
const { default: OpenFolder } = await loadMod("open-folder");
const { default: SessionMenu } = await loadMod("session-menu");
const { default: TabBar } = await loadMod("tab-bar");
const { default: PaneHeader } = await loadMod("pane-header");
const { default: SidebarFooter } = await loadMod("sidebar-footer");
const { default: StatusBar } = await loadMod("status-bar");

// --- The world: this computer ("macbook") and volskaya, reached over SSH. ---

const program = (key, name) => ({ key, name, icon: `icons/${key}.svg`, tint: false, agent: true, shell: false });
const claude = program("claude", "Claude Code");
const codex = program("codex", "Codex");

const spaces = [
  { id: "sp1", name: "herdr-mods", machine: null, branch: "main", active: true, tabs: [{ id: "tb1", index: 1, name: "1", named: false, active: true, status: "idle" }] },
  {
    id: "volskaya/sp2", name: "scalar", machine: "volskaya", tabs: [
      { id: "volskaya/tb1", index: 1, name: "scratch", named: true },
      { id: "volskaya/tb2", index: 2, name: "2", named: false },
      { id: "volskaya/tb3", index: 3, name: "3", named: false },
    ],
  },
  {
    id: "volskaya/sp3", name: "mach", machine: "volskaya", tabs: [
      { id: "volskaya/tb4", index: 1, name: "1", named: false },
      { id: "volskaya/tb5", index: 2, name: "2", named: false },
    ],
  },
];
const tabOf = new Map(spaces.flatMap((s) => s.tabs.map((t) => [t.id, [s, t]])));

// In agents() order: space, tab, pane.
const sessions = [
  { address: "t3", tab: "tb1", cwd: "/Users/eric/src/herdr-mods", title: "✳ Tidy mods", status: "idle", program: claude },
  { address: "volskaya/t8", tab: "volskaya/tb1", cwd: "/home/ekberndt", title: "claude", status: "done", program: claude },
  { address: "volskaya/t1p", tab: "volskaya/tb2", cwd: "/home/ekberndt/src/linux-utils", title: "Session skill", status: "blocked", program: claude, pinned: true },
  { address: "volskaya/t1r", tab: "volskaya/tb3", cwd: "/home/ekberndt/src/linux-utils-feat-herdr-installer", title: "Herdr installer and agents tree", status: "working", program: claude },
  { address: "volskaya/t7", tab: "volskaya/tb4", cwd: "/home/ekberndt/src/mach", title: "⠼ Explain project tracking | mach", status: "working", program: codex },
  { address: "volskaya/t9", tab: "volskaya/tb5", cwd: "/home/ekberndt/src/mach", title: "codex", status: "idle", program: codex },
];
const pane = (s) => s.address.replace(/t(\w+)$/, "p$1");
const agents = sessions.map((s) => {
  const [space, tab] = tabOf.get(s.tab);
  return {
    address: s.address, pane: pane(s), space: space.id, space_name: space.name, tab: tab.id, tab_index: tab.index, tab_name: tab.name,
    status: s.status, app: s.program.key, program: s.program, title: s.title, seq: 0, pinned: Boolean(s.pinned), focused: false,
  };
});
// A sub-agent t1r started, without a pane of its own.
const review = { address: "volskaya/t1s", name: "review", parent: "volskaya/t1r", state: "live", status: "done", cwd: "/home/ekberndt/src/linux-utils", program: claude };

const commonDirs = {
  [JSON.stringify(["volskaya", "/home/ekberndt/src/linux-utils"])]: "/home/ekberndt/src/linux-utils/.git",
  [JSON.stringify(["volskaya", "/home/ekberndt/src/linux-utils-feat-herdr-installer"])]: "/home/ekberndt/src/linux-utils/.git",
  [JSON.stringify(["volskaya", "/home/ekberndt/src/mach"])]: "/home/ekberndt/src/mach/.git",
  [JSON.stringify([null, "/Users/eric/src/herdr-mods"])]: "/Users/eric/src/herdr-mods/.git",
};
const execs = [];
const layoutJson = JSON.parse(fs.readFileSync(path.join(root, "herdr/layouts/agent-tree.json"), "utf8"));
globalThis.herdr = {
  machines: [{ name: null, layout: "ready" }, { name: "volskaya", layout: "ready" }],
  agents,
  terminals: [...sessions.map((s) => ({ address: s.address, state: "live", status: s.status, cwd: s.cwd, program: s.program, parent: null })), review],
  panes: sessions.map((s) => ({ pane: pane(s), terminal: s.address, tab: s.tab, cwd: s.cwd, title: s.title, status: s.status, program: s.program })),
  spaces,
  props: { pane: "p3" },
  focused: { agent: null },
  layout: layoutJson,
  shared: {},
  ran: [],
  overlays: [],
  closed: [],
  knownAgents: [
    { ...claude, run: ["claude"], installed: true },
    { ...codex, run: ["codex", "--no-daemon"], installed: true },
  ],
  order: null,
  hc: async (args) => {
    assert.deepEqual(args, ["server", "status", "--json"]);
    return { code: 0, stdout: JSON.stringify({ core: { name: "macbook" } }), stderr: "" };
  },
  exec: async (cmd, args, { cwd, on }) => {
    execs.push([cmd, ...args, cwd, on]);
    const dir = commonDirs[JSON.stringify([on, cwd])];
    return dir ? { code: 0, stdout: `${dir}\n`, stderr: "" } : { code: 128, stdout: "", stderr: "fatal: not a git repository" };
  },
};
const storage = {};
globalThis.localStorage = {
  getItem: (k) => storage[k] ?? null,
  setItem: (k, v) => { storage[k] = v; },
  removeItem: (k) => { delete storage[k]; },
};

const tasks = [];
const timers = [];
const cx = {
  spawn: (f) => { tasks.push(f(cx)); },
  timer: { every: (_ms, f) => timers.push(f) },
  focus_handle: () => ({ focus: () => {} }),
  notify: () => {},
  stop_propagation: () => {},
};
const settle = async () => { while (tasks.length) await tasks.shift(); };

// --- Reading the rendered list back. ---

function byId(el, id) {
  if (typeof el === "string") return null;
  if (el.node.calls.id?.[0] === id) return el;
  for (const kid of el.node.kids) {
    const found = byId(kid, id);
    if (found) return found;
  }
  return null;
}

function words(el) {
  const out = [];
  const walk = (x) => {
    if (typeof x === "string") out.push(x);
    else x.node.kids.forEach(walk);
  };
  walk(el);
  return out;
}

// A guide cell is a fixed-size column of two halves: the top draws "│" or the
// corner, the bottom carries the line on.
function guideChar(n) {
  const [top, bottom] = n.kids.map((k) => k.node.calls);
  if (!top.border_l) return " ";
  if (!top.border_b) return "│";
  return bottom.border_l ? "├" : "└";
}
const isGuide = (n) => n.tag === "v_flex" && n.calls.w?.[0] === 16 && n.kids.length === 2;

// A row as text: its guide lines, then icons (by file name), words and status marks.
function describe(row) {
  let guides = "";
  const tokens = [];
  const walk = (x) => {
    if (typeof x === "string") return tokens.push(x);
    const n = x.node;
    if (isGuide(n)) return (guides += guideChar(n));
    if (n.tag === "svg" || n.tag === "image") return tokens.push(path.basename(n.arg, ".svg"));
    if (n.tag === "div" && n.calls.border) tokens.push("ring");
    if (n.tag === "div" && n.calls.bg?.[0] === "#done") tokens.push("dot");
    n.kids.forEach(walk);
  };
  walk(row);
  return `${guides}${guides ? " " : ""}${tokens.join(" ")}`;
}

const list = (view) => byId(view.render(cx), "ag-list").node.kids;
const tree = (view) => list(view).map(describe);

// --- Pure helpers. ---

assert.equal(repoName("/home/u/src/linux-utils/.git"), "linux-utils", "a checkout's .git names its repo");
assert.equal(repoName("/srv/git/infra.git"), "infra", "a bare repo drops .git");
assert.equal(repoFolder("/home/u/src/linux-utils/.git", "/tmp/wt"), "/home/u/src/linux-utils");
assert.equal(repoFolder("/srv/git/infra.git", "/srv/work"), "/srv/work");
assert.equal(folderLabel("/home/u"), "~");
assert.equal(folderLabel("/Users/u/notes"), "~/notes");
assert.equal(folderLabel("/srv/data"), "/srv/data");

// --- The tree. ---

const view = new AgentTree();
view.init({}, cx);
await settle();

assert.ok(tree(view).includes("├ folder ~/src/linux-utils-feat-herdr-installer chevron-down"),
  "until git answers, a session sits under its folder");

// Two ticks before any answer: each place is asked about once, on its own machine.
timers[0](cx);
timers[0](cx);
await settle();
assert.deepEqual(execs.map((e) => e.slice(-2)).sort(), [
  ["/Users/eric/src/herdr-mods", null],
  ["/home/ekberndt", "volskaya"],
  ["/home/ekberndt/src/linux-utils", "volskaya"],
  ["/home/ekberndt/src/linux-utils-feat-herdr-installer", "volskaya"],
  ["/home/ekberndt/src/mach", "volskaya"],
]);
assert.deepEqual(execs[0].slice(0, 4), ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]);

assert.deepEqual(tree(view), [
  "monitor macbook chevron-down",
  "└ folder herdr-mods chevron-down",
  " └ claude Tidy mods <1m ring",
  "server volskaya chevron-down",
  "├ folder linux-utils chevron-down",
  "│├ claude Session skill pin <1m Needs you",
  "│└ claude Herdr installer and agents tree chevron-down <1m spinner",
  "│ └ claude review ring",
  "├ folder mach chevron-down",
  "│├ codex Explain project tracking | mach <1m spinner",
  "│└ codex mach / 2 <1m ring",
  "└ folder ~ chevron-down",
  " └ claude scratch <1m dot",
], "computer > repo > session, worktrees under their repo, pinned first, sub-agents under their parent");

for (const row of tree(view).filter((r) => /claude|codex/.test(r))) {
  assert.ok(!/macbook|volskaya/.test(row), `a session row leaves its computer to the tree: ${row}`);
}
assert.deepEqual(globalThis.herdr.order, ["t3", "volskaya/t1p", "volskaya/t1r", "volskaya/t7", "volskaya/t9", "volskaya/t8"],
  "agent.next follows the tree");

// Header controls at the top of the sidebar replace brand + Spaces.
const fullView = view.render(cx);
byId(fullView, "search").node.calls.on_click[0]({}, cx);
byId(fullView, "agent-new").node.calls.on_click[0]({}, cx);
assert.deepEqual(globalThis.herdr.ran.slice(-1), [["mod.open", { name: "picker" }]]);
assert.equal(globalThis.herdr.overlays.at(-1).mod, "session-menu");
globalThis.herdr.ran.length = 0;

// Right-clicking a repo or computer opens session-menu (not Herdr's worktree menu)
// targeted at that repo's primary checkout or that computer's home.
const rowOf = (text) => list(view).find((r) => describe(r).includes(text));
rowOf("folder linux-utils").node.mouseDown.right({}, cx);
const repoPopup = globalThis.herdr.overlays.at(-1);
assert.deepEqual(repoPopup, {
  mod: "session-menu",
  kind: "popup",
  width: 240,
  height: 420,
  props: {
    machine: "volskaya",
    space: "volskaya/sp2",
    folder: "/home/ekberndt/src/linux-utils",
    title: "volskaya · linux-utils",
  },
});

globalThis.herdr.props = { ...repoPopup.props, overlay: "ov-repo" };
const repoMenu = new SessionMenu();
repoMenu.init(globalThis.herdr.props, cx);
await settle();
const repoMenuTree = repoMenu.render();
assert.ok(!words(repoMenuTree).some((w) => /worktree/i.test(w)), "session-menu exposes no Herdr worktree actions");
byId(repoMenuTree, "agent-claude").node.calls.on_click[0]({}, cx);
assert.deepEqual(globalThis.herdr.closed.at(-1), "ov-repo");
assert.deepEqual(globalThis.herdr.ran.at(-1), [
  "tab.new",
  { space: "volskaya/sp2", folder: "/home/ekberndt/src/linux-utils", name: "Claude Code", argv: ["claude"] },
]);

rowOf("server volskaya").node.mouseDown.right({}, cx);
const machinePopup = globalThis.herdr.overlays.at(-1);
assert.deepEqual(machinePopup.props, {
  machine: "volskaya",
  space: "volskaya/sp2",
  folder: "/home/ekberndt",
  title: "volskaya",
});
globalThis.herdr.props = { ...machinePopup.props, overlay: "ov-machine" };
const machineMenu = new SessionMenu();
machineMenu.init(globalThis.herdr.props, cx);
await settle();
byId(machineMenu.render(), "terminal").node.calls.on_click[0]({}, cx);
assert.deepEqual(globalThis.herdr.ran.at(-1), [
  "tab.new",
  { space: "volskaya/sp2", folder: "/home/ekberndt" },
]);
globalThis.herdr.props = { pane: "p3" };
globalThis.herdr.ran.length = 0;

// Clicks: a session focuses its pane; a sub-agent without one opens in peek; a repo folds.
rowOf("Session skill").node.calls.on_click[0]({}, cx);
rowOf("review").node.calls.on_click[0]({}, cx);
assert.deepEqual(globalThis.herdr.ran, [
  ["pane.focus", { pane: "volskaya/p1p" }],
  ["terminal.peek", { terminal: "volskaya/t1s" }],
]);
rowOf("folder mach").node.calls.on_click[0]({}, cx);
assert.deepEqual(tree(view).slice(8), [
  "├ folder mach spinner 2 chevron-right",
  "└ folder ~ chevron-down",
  " └ claude scratch <1m dot",
], "a folded repo keeps its count and most urgent status");

// On the narrow rail: one numbered status per session, in tree order, and » to widen it.
globalThis.herdr.layout = { id: "root", children: [{ id: "sidebar", size: { px: 44 } }] };
assert.deepEqual(tree(view), ["1 ring", "2 !", "3 spinner", "4 spinner", "5 ring", "6 dot"]);
const rail = view.render(cx);
byId(rail, "collapse").node.calls.on_click[0]({}, cx);
assert.deepEqual(globalThis.herdr.ran.at(-1), ["layout.resize", { id: "sidebar", px: 256 }]);

// A just-connected computer can start its first session, with no agent or space.
globalThis.herdr.layout = layoutJson;
const world = globalThis.herdr;
world.machines.push({ name: "fresh", layout: "ready" });
rowOf("server fresh").node.calls.on_click[0]({}, cx);
world.props = { ...world.overlays.at(-1).props, overlay: "ov-empty" };
const emptyMenu = new SessionMenu();
emptyMenu.init(world.props, cx);
await settle();
byId(emptyMenu.render(), "terminal").node.calls.on_click[0]({}, cx);
assert.deepEqual(world.ran.at(-1), ["space.new", { machine: "fresh" }]);
byId(emptyMenu.render(), "add-machine").node.calls.on_click[0]({}, cx);
assert.deepEqual(world.ran.at(-1), ["mod.open", { name: "machine-add" }]);
byId(emptyMenu.render(), "open-folder").node.calls.on_click[0]({}, cx);
assert.deepEqual(world.overlays.at(-1).props, { machine: "fresh", folder: null });
world.props = { ...world.overlays.at(-1).props, overlay: "ov-folder" };
const folderDialog = new OpenFolder();
folderDialog.init({}, cx);
assert.ok(!byId(folderDialog.render(), "browse"), "the desktop folder picker is never used for a remote");
const originalExec = world.exec;
const remoteHome = fs.realpathSync(tmp);
world.exec = async (cmd, args, options) => {
  assert.deepEqual(options, { on: "fresh" });
  const r = spawnSync(cmd, args, { encoding: "utf8", env: { ...process.env, HOME: remoteHome } });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
};
const folderAction = async (id, input) => {
  folderDialog.input.set_value(input);
  byId(folderDialog.render(), id).node.calls.on_click[0]({}, cx);
  await settle();
};
const beforeOpen = world.ran.length;
await folderAction("open", "~/missing");
assert.ok(folderDialog.error);
assert.equal(world.ran.length, beforeOpen, "invalid paths must not start a terminal somewhere else");
assert.notEqual(world.closed.at(-1), "ov-folder");
const dirname = "two words '$" + "(date)";
await folderAction("create", "~/" + dirname);
assert.deepEqual(world.ran.at(-1), ["space.new", { machine: "fresh", folder: path.join(remoteHome, dirname) }]);
assert.equal(world.closed.at(-1), "ov-folder");
await folderAction("repo", "src/project");
assert.ok(fs.statSync(path.join(remoteHome, "src/project/.git")).isDirectory());
await folderAction("open", path.join(remoteHome, "src/project"));
assert.deepEqual(world.ran.at(-1), ["space.new", { machine: "fresh", folder: path.join(remoteHome, "src/project") }]);
// Dismissing a remote dialog while the host is answering must not switch spaces.
let finishExec;
world.exec = () => new Promise((resolve) => { finishExec = resolve; });
const pendingDialog = new OpenFolder();
pendingDialog.init({}, cx);
pendingDialog.input.set_value("~/project");
const beforeCancel = world.ran.length;
pendingDialog.open("open", cx);
pendingDialog.close();
finishExec({ code: 0, stdout: "/home/u/project\n", stderr: "" });
await settle();
assert.equal(world.ran.length, beforeCancel);
world.exec = originalExec;

// A plain shell is reachable after switching spaces, without becoming an agent.
const shell = { key: "shell", name: "zsh", icon: "icons/shell.svg", tint: true };
world.spaces.push({ id: "fresh/sp1", name: "project", machine: "fresh", folder: "/src/project", tabs: [{ id: "fresh/tb1", name: "1" }] });
world.panes.push({ terminal: "fresh/t1", tab: "fresh/tb1", pane: "fresh/p1", program: shell, cwd: null });
const beforeShell = [...world.order];
rowOf("shell zsh / 1").node.calls.on_click[0]({}, cx);
assert.deepEqual(world.ran.at(-1), ["pane.focus", { pane: "fresh/p1" }]);
assert.deepEqual(world.order, beforeShell);
assert.equal(world.order.includes("fresh/t1"), false);
world.props = { pane: "p3" };
const localDialog = new OpenFolder();
localDialog.init({}, cx);
byId(localDialog.render(), "browse").node.calls.on_click[0]({}, cx);
await settle();
assert.equal(localDialog.input.value(), "/Users/eric/src/picked");

// --- Compact chrome mods: TabBar, PaneHeader, SidebarFooter, StatusBar. ---

globalThis.herdr.layout = layoutJson;
globalThis.herdr.window = { platform: "macos", titlebar: "none", buttons: false, maximized: false, fullscreen: false };

const tabBar = new TabBar();
tabBar.init();
const tabTree = tabBar.render();
assert.ok(byId(tabTree, "tab-tb1") && byId(tabTree, "tab-new") && byId(tabTree, "panel-files") && byId(tabTree, "panel-changes"));

const paneHeader = new PaneHeader();
paneHeader.init();
assert.deepEqual(words(paneHeader.render()), ["Claude Code", "~/src/herdr-mods"]);

const footer = new SidebarFooter().render();
assert.ok(byId(footer, "settings") && byId(footer, "machine"));
byId(footer, "machine").node.calls.on_click[0]({}, cx);
assert.deepEqual(world.ran.at(-1), ["mod.open", { name: "machine-add" }]);

assert.deepEqual(words(new StatusBar().render()), ["This computer", "main", "6 agents", "· 1 needs you", "⌘K  commands"]);

// --- The layout removes Spaces and the brand banner, giving agent-tree the full sidebar. ---

const blocks = [];
const walkLayout = (n) => {
  if (n.content?.mod) blocks.push([n.id, n.content.mod]);
  if (n.content?.pane?.header?.content?.mod) blocks.push([`${n.id}.header`, n.content.pane.header.content.mod]);
  (n.children ?? []).forEach(walkLayout);
};
walkLayout(layoutJson);
assert.deepEqual(blocks, [
  ["agents", "agent-tree"],
  ["sidebar-footer", "sidebar-footer"],
  ["tabs", "tab-bar"],
  ["main.header", "pane-header"],
  ["files", "files"],
  ["changes", "changes"],
  ["status", "status-bar"],
]);
// "none": Herdr would otherwise dock a copy into whatever layout is showing when it first sees a mod.
for (const entry of fs.readdirSync(path.join(root, "herdr/mods"))) {
  const manifest = path.join(root, "herdr/mods", entry, "mod.json");
  if (fs.existsSync(manifest)) assert.equal(JSON.parse(fs.readFileSync(manifest, "utf8")).place, "none", entry);
}

console.log("ok   agent-tree layout and mods");
