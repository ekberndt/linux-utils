// Renders the agent-tree mod under node against stand-ins for Herdr's modules,
// then reads the rows back as text. Run by test_herdr_agent_tree.sh.

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const modDir = path.join(root, "herdr/mods/agent-tree");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "agent-tree-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));

// The mod imports bare "gpui-kit", "gpui-base" and "herdr"; node finds these
// stand-ins in node_modules beside a copy of it.
const stubs = {
  // Elements record the calls made on them; child() refuses what GPUI would.
  "gpui-kit": `
    export function element(tag, arg) {
      const node = { tag, arg, calls: {}, kids: [] };
      const self = new Proxy(node, {
        get(_target, prop) {
          if (typeof prop === "symbol" || prop === "then") return undefined;
          if (prop === "node") return node;
          if (prop === "child") return (c) => {
            if (c == null || typeof c === "boolean") throw new Error("child(" + c + ")");
            node.kids.push(c);
            return self;
          };
          if (prop === "children") return (cs) => { cs.forEach((c) => self.child(c)); return self; };
          if (prop === "when") return (cond, f) => (cond ? f(self) : self);
          if (prop === "hover") return (f) => { f(element("style")); return self; };
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
  `,
  herdr: `
    const s = () => globalThis.herdr;
    export const agents = () => s().agents;
    export const terminals = () => s().terminals;
    export const panes = () => s().panes;
    export const spaces = () => s().spaces;
    export const focused = () => s().focused;
    export const layout = () => s().layout;
    export const window = () => ({ platform: "linux" });
    // Every color is its own name, so tests can tell them apart.
    export const theme = () => new Proxy({}, { get: (_t, k) => "#" + String(k) });
    export const shared = (k) => s().shared[k];
    export const setShared = (k, v) => { s().shared[k] = v; };
    export const setAgentOrder = (list) => { s().order = list; };
    export const run = (name, args) => { s().ran.push([name, args]); return null; };
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
fs.mkdirSync(path.join(tmp, "mod"));
fs.writeFileSync(path.join(tmp, "mod", "package.json"), JSON.stringify({ type: "module" }));
for (const file of ["main.js", "tree.js"]) fs.copyFileSync(path.join(modDir, file), path.join(tmp, "mod", file));

const { default: AgentTree } = await import(pathToFileURL(path.join(tmp, "mod", "main.js")));
const { folderLabel, repoName } = await import(pathToFileURL(path.join(tmp, "mod", "tree.js")));

// --- The world: this computer ("macbook") and volskaya, reached over SSH. ---

const program = (key, name) => ({ key, name, icon: `icons/${key}.svg`, tint: false, agent: true, shell: false });
const claude = program("claude", "Claude Code");
const codex = program("codex", "Codex");

const spaces = [
  { id: "sp1", name: "herdr-mods", machine: null, tabs: [{ id: "tb1", index: 1, name: "1", named: false }] },
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
globalThis.herdr = {
  agents,
  terminals: [...sessions.map((s) => ({ address: s.address, state: "live", status: s.status, cwd: s.cwd, program: s.program, parent: null })), review],
  panes: sessions.map((s) => ({ pane: pane(s), terminal: s.address, tab: s.tab, cwd: s.cwd })),
  spaces,
  focused: { agent: null },
  layout: { id: "root", children: [{ id: "sidebar", size: { px: 268 } }] },
  shared: {},
  ran: [],
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
  const words = [];
  const walk = (x) => {
    if (typeof x === "string") return words.push(x);
    const n = x.node;
    if (isGuide(n)) return (guides += guideChar(n));
    if (n.tag === "svg" || n.tag === "image") return words.push(path.basename(n.arg, ".svg"));
    if (n.tag === "div" && n.calls.border) words.push("ring");
    if (n.tag === "div" && n.calls.bg?.[0] === "#done") words.push("dot");
    n.kids.forEach(walk);
  };
  walk(row);
  return `${guides}${guides ? " " : ""}${words.join(" ")}`;
}

const list = (view) => byId(view.render(cx), "ag-list").node.kids;
const tree = (view) => list(view).map(describe);

// --- Pure helpers. ---

assert.equal(repoName("/home/u/src/linux-utils/.git"), "linux-utils", "a checkout's .git names its repo");
assert.equal(repoName("/srv/git/infra.git"), "infra", "a bare repo drops .git");
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

// Clicks: a session focuses its pane; a sub-agent without one opens in peek; a repo folds.
const rowOf = (text) => list(view).find((r) => describe(r).includes(text));
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
assert.deepEqual(globalThis.herdr.ran.at(-1), ["layout.resize", { id: "sidebar", px: 268 }]);

// --- The layout shows this mod where Herdr's own list was, and nowhere else. ---

const blocks = [];
const walkLayout = (n) => {
  if (n.content?.mod) blocks.push([n.id, n.content.mod]);
  (n.children ?? []).forEach(walkLayout);
};
walkLayout(JSON.parse(fs.readFileSync(path.join(root, "herdr/layouts/agent-tree.json"), "utf8")));
assert.deepEqual(blocks.filter(([, mod]) => mod.startsWith("agent")), [["agents", "agent-tree"]]);
// "none": Herdr would otherwise dock a copy into whatever layout is showing when it first sees the mod.
assert.equal(JSON.parse(fs.readFileSync(path.join(modDir, "mod.json"), "utf8")).place, "none");

console.log("ok   agent-tree mod");
