// The agents list as a file tree: computer, then repo, then each session with
// the sub-agents it started. Plain data in, nodes out; main.js draws them.

const RANK = { blocked: 4, done: 3, working: 2, idle: 1 };

export const urgent = (statuses) => statuses.reduce((m, s) => ((RANK[s] ?? 0) > (RANK[m] ?? 0) ? s : m), null);

// `vps/t7` lives on vps; a bare address is on this computer (null).
const machineOf = (address) => (address.includes("/") ? address.split("/")[0] : null);

// A folder on a machine: what git is asked about, once.
export const placeKey = (machine, folder) => JSON.stringify([machine, folder]);

// A worktree's git common dir is its main checkout's .git, so every worktree
// of a repo gets the repo's name and launches new sessions from that checkout.
export function repoName(commonDir) {
  const path = commonDir.replace(/\/+$/, "");
  const base = (p) => p.split("/").pop();
  return path.endsWith("/.git") ? base(path.slice(0, -5)) : base(path).replace(/\.git$/, "");
}

export function repoFolder(commonDir, fallback) {
  const path = commonDir.replace(/\/+$/, "");
  return path.endsWith("/.git") ? path.slice(0, -5) : fallback;
}

const homeOf = (folder) => /^(\/home\/[^/]+|\/Users\/[^/]+|\/root)(?=\/|$)/.exec(folder ?? "")?.[1] ?? null;

// A folder outside any repo, with a home folder on any machine as ~.
export const folderLabel = (folder) => folder.replace(/^(\/home\/[^/]+|\/Users\/[^/]+|\/root)(?=\/|$)/, "~");

// Drops what an agent puts before its title, as Herdr's own list does: a status
// glyph or spinner and its separator, and Codex's blinking "[ ! ] " mark.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").replace(/^\[ [!.] \] /, "").trim();

// A session reads as the tab someone named, else the agent's own title when it
// says something, else where it is in the spaces list ("scalar / 3"). Never the
// computer: that is the row's ancestor.
function sessionLabel(agent, tab) {
  const program = agent.program?.name;
  if (!agent.status) return tab?.named ? tab.name : `${program || "Terminal"} / ${agent.tab_name}`;
  if (tab?.named && tab.name !== program) return tab.name;
  const title = clean(agent.title);
  // clean() strips a path's leading ~ or /: test the title with only its status glyph gone.
  const path = /^[~/]|^[A-Za-z]:\\/.test((agent.title ?? "").replace(/^[^\p{L}\p{N}~/]+/u, ""));
  const telling =
    title && title !== agent.address && title !== program && title.toLowerCase() !== agent.program?.key && !path && !title.includes("@");
  return telling ? title : `${agent.space_name} / ${agent.tab_name}`;
}

// A sub-agent reports to its parent, so its done is the parent's news; its error needs you.
const subStatus = (s) => (s === "error" ? "blocked" : s === "done" ? "idle" : s);

// A plain terminal contributes to the count, but has no agent status to color the row.
function node(kind, key, label, status, children, extra = {}) {
  const below = children.flatMap((c) => (c.kind === "session" || c.kind === "subagent" ? [c.status, ...c.below] : c.below));
  return { kind, key, label, status, children, below, ...extra };
}

function subagents(terminals, parent) {
  return terminals
    .filter((k) => k.parent === parent && k.state === "live")
    .map((k) =>
      node("subagent", k.address, k.name || k.template || k.program?.name || k.address, subStatus(k.status), subagents(terminals, k.address), {
        terminal: k,
      }),
    );
}

const keysOf = (nodes) => nodes.flatMap((n) => [n.key, ...keysOf(n.children)]);

// `places`: placeKey -> git common dir, null outside a repo, absent until asked.
// Returns the computer nodes and the [machine, folder] places still to ask git about;
// until then a session sits under its folder.
export function buildTree({ agents, terminals, panes, spaces, machines, places, local }) {
  const kids = new Map(agents.map((a) => [a.address, subagents(terminals, a.address)]));
  // A kept sub-agent has a pane too: under its parent it gets no row of its own unless pinned.
  const nested = new Set(keysOf([...kids.values()].flat()));
  const cwd = new Map(panes.map((p) => [p.pane, p.cwd]));
  const launched = new Map(terminals.map((k) => [k.address, k.cwd]));
  const tabs = new Map(spaces.flatMap((s) => s.tabs.map((tab) => [tab.id, { tab, space: s }])));
  const sessions = [...agents];
  for (const p of panes) {
    const owner = tabs.get(p.tab);
    if (!p.terminal || !owner || kids.has(p.terminal) || nested.has(p.terminal)) continue;
    sessions.push({
      address: p.terminal, pane: p.pane, program: p.program, focused: p.focused, pinned: false, status: null,
      tab: p.tab, tab_name: owner.tab.name, space: owner.space.id, space_name: owner.space.name,
    });
  }
  const activeSpaceId = spaces.find((s) => s.active)?.id ?? null;
  const groupsByMachine = new Map([[null, new Map()]]);
  for (const m of machines) {
    if (m.layout === "ready") groupsByMachine.set(m.name, new Map());
  }
  const homes = new Map(); // machine -> inferred home path
  const unnamed = [];
  sessions.forEach((a, order) => {
    if (nested.has(a.address) && !a.pinned) return;
    const machine = machineOf(a.address);
    const owner = tabs.get(a.tab);
    const folder = cwd.get(a.pane) || launched.get(a.address) || owner?.space.folder || "";
    if (!homes.has(machine) && homeOf(folder)) homes.set(machine, homeOf(folder));
    const place = placeKey(machine, folder);
    if (folder && !places.has(place)) unnamed.push([machine, folder]);
    const common = places.get(place);
    const [key, label, rootFolder] = common
      ? [common, repoName(common), repoFolder(common, folder)]
      : [folder, folderLabel(folder) || "~", folder];
    if (!groupsByMachine.has(machine)) groupsByMachine.set(machine, new Map());
    const groups = groupsByMachine.get(machine);
    if (!groups.has(key)) groups.set(key, { label, folder: rootFolder, sessions: [] });
    groups.get(key).sessions.push(node("session", a.address, sessionLabel(a, owner?.tab), a.status, kids.get(a.address) ?? [], { agent: a, order }));
  });

  const pinnedFirst = (a, b) => b.agent.pinned - a.agent.pinned || a.order - b.order;
  // By code point, not localeCompare, whose order differs between JS engines: ~ (home) sorts last.
  const compare = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
  const byLabel = (a, b) => compare(a.label.toLowerCase(), b.label.toLowerCase()) || compare(a.key, b.key);
  // This computer first, then the others by name, as Herdr orders spaces.
  const byMachine = ([a], [b]) => (a === null ? -1 : b === null ? 1 : compare(a, b));
  const computers = [...groupsByMachine].sort(byMachine).map(([machine, groups]) => {
    const machineSpaces = spaces.filter((s) => (s.machine ?? null) === machine);
    const defaultSpace =
      machineSpaces.find((s) => s.id === activeSpaceId)?.id ??
      machineSpaces[0]?.id ??
      [...groups.values()][0]?.sessions[0]?.agent.space ??
      null;
    const repoNodes = [...groups]
      .map(([key, g]) => {
        const sorted = g.sessions.sort(pinnedFirst);
        const repoSpace =
          sorted.find((s) => s.agent.space === activeSpaceId)?.agent.space ??
          machineSpaces.find((s) => s.folder === g.folder)?.id ??
          sorted[0]?.agent.space ??
          defaultSpace;
        return node("repo", `r:${placeKey(machine, key)}`, g.label, null, sorted, {
          machine,
          folder: g.folder,
          space: repoSpace,
        });
      })
      .sort(byLabel);
    return node("computer", `m:${machine ?? ""}`, machine ?? local, null, repoNodes, {
      machine,
      folder: homes.get(machine) ?? machineSpaces[0]?.folder ?? null,
      space: defaultSpace,
    });
  });
  return { computers, unnamed };
}

// Depth-first rows, skipping what `folded` hides. Each row's guide lines hold
// one cell per level below the computer: "│" while that ancestor has siblings
// still to come, else "", then its own branch, "├" or "└". Computers draw none.
export function rows(computers, folded) {
  const out = [];
  const walk = (nodes, lead) =>
    nodes.forEach((n, i) => {
      const last = i === nodes.length - 1;
      out.push({ ...n, lines: [...lead, last ? "└" : "├"] });
      if (!folded.has(n.key)) walk(n.children, [...lead, last ? "" : "│"]);
    });
  for (const c of computers) {
    out.push({ ...c, lines: [] });
    if (!folded.has(c.key)) walk(c.children, []);
  }
  return out;
}
