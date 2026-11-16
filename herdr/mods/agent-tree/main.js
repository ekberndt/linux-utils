// Full-sidebar agents tree: each computer, its repos/folders, then the agent
// sessions in them and the sub-agents they started. Replaces both the brand
// banner and the Spaces list at the top of the sidebar.

import { View, div, image, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import {
  agents,
  terminals,
  panes,
  spaces,
  focused,
  run,
  openOverlay,
  exec,
  hc,
  checking,
  theme,
  shared,
  setShared,
  setAgentOrder,
  window,
  layout,
} from "herdr";
import { buildTree, placeKey, rows, urgent } from "./tree.js";

const ICONS = "mods/workspace-chrome";
const SIDEBAR_WIDTH = 256;
// Every tree row is this tall, so guide lines run unbroken from row to row.
const ROW = 24;
// Guide cells and icons share this width, so a child's line drops from the middle of its parent's icon.
const CELL = 16;
// A place git could not answer for (a machine away, a folder gone) is asked again after this.
const RETRY_MS = 30000;

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// As in the shipped mods: the sidebar is a rail by its width, and the agents
// list's » is what unfolds it on macOS, where the traffic lights cover the bar's toggle.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  setShared("sidebar.collapsed", !narrow());
  run("layout.resize", {
    id: "sidebar",
    px: narrow() ? (shared("sidebar.width") ?? SIDEBAR_WIDTH) : window()?.platform === "macos" ? 76 : 44,
  });
}

function duration(ms) {
  const m = Math.floor(ms / 60000);
  if (m < 1) return "<1m";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  return h < 24 ? `${h}h` : `${Math.floor(h / 24)}d`;
}

// The agent's icon from the app's program table: a one-color glyph or a picture.
function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

// Herdr's status marks. compact: a ! for blocked on a folded row.
function status(t, s, compact = false) {
  if (s === "working") return svg(`${ICONS}/spinner.svg`).size(11).mx(1).flex_none().text_color(t.working).spin(900);
  if (s === "blocked" && compact) {
    return div()
      .size(13)
      .flex_none()
      .rounded(4)
      .bg(t.blocked + "26")
      .text_size(10)
      .font_bold()
      .text_color(t.blocked)
      .flex()
      .items_center()
      .justify_center()
      .child("!");
  }
  if (s === "blocked") {
    return div()
      .flex_none()
      .px(5)
      .h(16)
      .rounded(4)
      .bg(t.blocked + "26")
      .text_size(10)
      .font_semibold()
      .text_color(t.blocked)
      .flex()
      .items_center()
      .child("Needs you");
  }
  // Idle: a ring; done: a dot.
  if (s === "idle") return div().size(6.5).mx(3).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim);
  return div().size(6.5).mx(3).flex_none().rounded(4).bg(s === "done" ? t.done : t.dim + "00");
}

// One cell per level: "│" runs through, "├" branches off and runs on, "└" ends.
function guide(l, t) {
  const line = (el) => el.border_l(1.5).border_color(t.input);
  return v_flex()
    .w(CELL)
    .h(ROW)
    .flex_none()
    .child(
      div()
        .ml(CELL / 2 - 1)
        .h(ROW / 2)
        .when(Boolean(l), line)
        .when(l === "├" || l === "└", (el) => el.border_b(1.5))
        .when(l === "└", (el) => el.rounded_bl(5)),
    )
    .child(div().ml(CELL / 2 - 1).flex_1().when(l === "│" || l === "├", line));
}

// Empty when a program has no icon, so its label still lines up with its siblings'.
const iconCell = (el) => h_flex().w(CELL).mr(6).flex_none().justify_center().when(Boolean(el), (cell) => cell.child(el));

export default class AgentTree extends View {
  init(_props, cx) {
    this.folded = new Set();
    this.places = new Map(); // placeKey -> git common dir, null outside a repo
    this.asked = new Map(); // placeKey -> when git was last asked about it
    this.unnamed = []; // [machine, folder] places the last render could not name
    this.local = "This computer";
    // Each agent's last state and when it changed (ms), kept across restarts.
    try {
      this.changed = JSON.parse(localStorage.getItem("changed") ?? "{}");
    } catch {
      this.changed = {};
    }
    if (!checking()) {
      // This computer goes by its core's name; other machines by the names their addresses carry.
      cx.spawn(async (cx) => {
        try {
          this.local = JSON.parse((await hc(["server", "status", "--json"])).stdout).core.name || this.local;
        } catch {}
        cx.notify();
      });
      cx.timer.every(500, (cx) => this.ask(cx));
      cx.timer.every(30000, (cx) => cx.notify());
    }
  }

  // One git call per place the tree could not name yet, on the machine it is on.
  ask(cx) {
    const now = Date.now();
    for (const [machine, folder] of this.unnamed) {
      const key = placeKey(machine, folder);
      if (now - (this.asked.get(key) ?? 0) < RETRY_MS) continue;
      this.asked.set(key, now);
      cx.spawn(async (cx) => {
        try {
          const r = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: folder, on: machine });
          this.places.set(key, r.code === 0 ? r.stdout.replace(/\n$/, "") : null);
          cx.notify();
        } catch {} // Unreachable: asked again after RETRY_MS.
      });
    }
  }

  // Stamps agents whose state changed. Done and idle count as one: looking at a
  // finished agent turns done into idle, and looking isn't the agent doing anything.
  track(list, now) {
    let dirty = false;
    for (const a of list) {
      const s = a.status === "done" ? "idle" : a.status;
      if (this.changed[a.address]?.s === s) continue;
      this.changed[a.address] = { s, at: now };
      dirty = true;
    }
    if (!dirty) return;
    const listed = new Set(list.map((a) => a.address));
    for (const [k, c] of Object.entries(this.changed)) {
      if (!listed.has(k) && now - c.at > 30 * 86400000) delete this.changed[k];
    }
    localStorage.setItem("changed", JSON.stringify(this.changed));
  }

  fold(key, cx) {
    this.folded.has(key) ? this.folded.delete(key) : this.folded.add(key);
    cx.notify();
  }

  // The chevron that folds a row; folded, how many agents it hides, colored by the most urgent.
  chevron(t, n) {
    const open = !this.folded.has(n.key);
    const top = urgent(n.below);
    return h_flex()
      .id(`fold-${n.key}`)
      .h(16)
      .px(3)
      .gap(2)
      .flex_none()
      .items_center()
      .rounded(4)
      .text_size(10.5)
      .text_color(open ? t.dim : (t[top] ?? t.dim))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => {
        cx.stop_propagation();
        this.fold(n.key, cx);
      })
      .when(!open, (el) => el.child(String(n.below.length)))
      .child(svg(`${ICONS}/chevron-${open ? "down" : "right"}.svg`).size(10).flex_none());
  }

  openSessionMenu(n) {
    const title = n.kind === "repo" && n.machine ? `${n.machine} · ${n.label}` : n.label;
    openOverlay({
      mod: "session-menu",
      kind: "popup",
      width: 240,
      height: 420,
      props: { machine: n.machine, space: n.space, folder: n.folder, title },
    });
  }

  // Computers and repos: a folder-like row that folds what is under it, and
  // right-clicks to start a new tab or agent session there.
  group(t, n) {
    const computer = n.kind === "computer";
    const folded = this.folded.has(n.key);
    const top = urgent(n.below);
    const glyph = svg(`${ICONS}/${computer ? (n.machine ? "server" : "monitor") : "folder"}.svg`).size(12).flex_none();
    return h_flex()
      .id(n.key)
      .px(6)
      .h(ROW)
      .flex_none()
      .rounded(6)
      .items_center()
      .text_size(computer ? 11 : 12)
      .text_color(t.muted)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .when(computer && !n.machine, (el) => el.tooltip("This computer"))
      .on_click((_e, cx) => this.fold(n.key, cx))
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        this.openSessionMenu(n);
      })
      .children(n.lines.map((l) => guide(l, t)))
      .child(iconCell(glyph))
      .child(div().flex_1().min_w(0).truncate().when(computer, (el) => el.font_medium()).child(n.label))
      .when(folded && top && top !== "idle", (el) => el.child(div().mr(3).child(status(t, top, true))))
      .child(this.chevron(t, n));
  }

  session(t, n, now) {
    const a = n.agent;
    const hovered = this.hovered === a.address;
    const when = this.changed[a.address]?.at;
    const pin = div()
      .id(`pin-${a.address}`)
      .flex_none()
      .p(2)
      .rounded(4)
      .text_color(t.dim)
      .cursor_pointer()
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .tooltip(a.pinned ? "Unpin" : "Pin to the top of its repo")
      .on_click((_e, cx) => {
        cx.stop_propagation();
        run("terminal.pin", { terminal: a.address, pinned: !a.pinned });
        // The row moves away from under the pointer, and no hover-out comes.
        this.hovered = null;
        cx.notify();
      })
      .child(svg(`${ICONS}/${a.pinned ? "pin-off" : "pin"}.svg`).size(12));
    return h_flex()
      .id(`ag-${a.address}`)
      .px(6)
      .h(ROW)
      .flex_none()
      .rounded(6)
      .items_center()
      .gap(5)
      .text_size(12.5)
      .when(a.focused, (el) => el.bg(t.selected))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .tooltip(`${a.space_name} / ${a.tab_name}`)
      .on_hover((on, cx) => {
        if (on) this.hovered = a.address;
        else if (this.hovered === a.address) this.hovered = null;
        cx.notify();
      })
      .on_click(() => run("pane.focus", { pane: a.pane }))
      .on_mouse_down("right", (_e, cx) => {
        cx.stop_propagation();
        openOverlay({ mod: "menu", kind: "popup", width: 200, props: { tab: "tab", target: { id: a.tab, space: a.space } } });
      })
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .items_center()
          .children(n.lines.map((l) => guide(l, t)))
          .child(iconCell(icon(a.program, 14, t.foreground)))
          .child(div().flex_1().min_w(0).truncate().text_color(a.status === "idle" && !a.focused ? t.muted : t.foreground).child(n.label)),
      )
      .when(n.children.length > 0, (el) => el.child(this.chevron(t, n)))
      .when(a.pinned && !hovered, (el) => el.child(svg(`${ICONS}/pin.svg`).size(10.5).flex_none().text_color(t.dim)))
      .when(hovered, (el) => el.child(pin))
      .when(!hovered && Boolean(when), (el) => el.child(div().flex_none().text_size(10.5).text_color(t.dim).child(duration(now - when))))
      .child(status(t, a.status));
  }

  // A sub-agent without a pane opens in peek; one kept as a pane is focused there.
  subagent(t, n, inPanes, shown) {
    const k = n.terminal;
    const on = k.address === shown;
    return h_flex()
      .id(`sub-${k.address}`)
      .px(6)
      .h(ROW)
      .flex_none()
      .rounded(6)
      .items_center()
      .gap(5)
      .text_size(12)
      .when(on, (el) => el.bg(t.raised))
      .cursor_pointer()
      .hover((s) => s.bg(t.hover))
      .on_click(() => run(inPanes.has(k.address) ? "pane.focus" : "terminal.peek", { terminal: k.address }))
      .child(
        h_flex()
          .flex_1()
          .min_w(0)
          .items_center()
          .children(n.lines.map((l) => guide(l, t)))
          .child(iconCell(icon(k.program, 13, t.foreground)))
          .child(div().flex_1().min_w(0).truncate().text_color(on ? t.foreground : t.muted).child(n.label)),
      )
      .when(n.children.length > 0, (el) => el.child(this.chevron(t, n)))
      .child(status(t, n.status));
  }

  header(t, collapsed) {
    const win = window();
    const macTraffic = win?.platform === "macos" && !win?.fullscreen;
    const stop = (_e, cx) => cx.stop_propagation();
    const iconBtn = (id, glyph, tip, action) =>
      div()
        .id(id)
        .size(24)
        .flex_none()
        .flex()
        .items_center()
        .justify_center()
        .rounded(5)
        .text_color(t.dim)
        .tooltip(tip)
        .hover((s) => s.bg(t.hover).text_color(t.foreground))
        .on_mouse_down("left", stop)
        .on_click(action)
        .child(svg(`${ICONS}/${glyph}.svg`).size(13));
    if (collapsed) {
      return h_flex()
        .h(36)
        .flex_none()
        .items_center()
        .justify_center()
        .border_b(1)
        .border_color(t.border)
        .when(!macTraffic, (el) => el.child(iconBtn("sidebar-toggle", "sidebar", "Expand sidebar", toggleSidebar)));
    }
    return h_flex()
      .h(36)
      .pl(macTraffic ? 76 : 12)
      .pr(6)
      .gap(2)
      .flex_none()
      .items_center()
      .border_b(1)
      .border_color(t.border)
      .child(div().flex_1().text_size(11.5).font_medium().text_color(t.dim).child("Agents"))
      .child(iconBtn("search", "search", "Search", () => run("mod.open", { name: "picker" })))
      .child(iconBtn("agent-new", "plus", "New agent or terminal", () => openOverlay({ mod: "session-menu", kind: "popup", width: 240, height: 420 })))
      .child(iconBtn("sidebar-toggle", "sidebar", "Collapse sidebar", toggleSidebar));
  }

  render(cx) {
    const t = theme();
    const collapsed = narrow();
    const listed = agents();
    const now = Date.now();
    this.track(listed, now);
    const { computers, unnamed } = buildTree({
      agents: listed,
      terminals: terminals(),
      panes: panes(),
      spaces: spaces(),
      places: this.places,
      local: this.local,
    });
    this.unnamed = unnamed;
    const sessions = rows(computers, new Set()).filter((n) => n.kind === "session");
    setAgentOrder(sessions.map((n) => n.key));

    const list = v_flex().id("ag-list").flex_1().min_h(0).px(collapsed ? 0 : 6).pt(4).pb(6).overflow_y_scrollbar().mode("always");
    if (collapsed) {
      return v_flex()
        .size_full()
        .min_h(0)
        .bg(t.chrome)
        .text_size(12)
        .child(this.header(t, true))
        .child(
          list.children(
            sessions.map((n, i) =>
              h_flex()
                .id(`ag-${n.key}`)
                .h(24)
                .px(6)
                .flex_none()
                .items_center()
                .gap(4)
                .hover((s) => s.bg(t.hover))
                .tooltip(n.label)
                .on_click(() => run("pane.focus", { pane: n.agent.pane }))
                .child(div().flex_1().min_w(0).whitespace_nowrap().text_right().text_color(t.muted).child(String(i + 1)))
                .child(h_flex().w(14).flex_none().items_center().justify_center().child(status(t, n.status, true))),
            ),
          ),
        )
        .child(
          h_flex()
            .h(26)
            .items_center()
            .justify_center()
            .child(
              div()
                .id("collapse")
                .text_size(12.5)
                .text_color(t.dim)
                .hover((s) => s.text_color(t.foreground))
                .on_click(toggleSidebar)
                .child("»"),
            ),
        );
    }

    const inPanes = new Set(listed.map((a) => a.address));
    const shown = focused()?.agent;
    const draw = (n) =>
      n.kind === "session" ? this.session(t, n, now) : n.kind === "subagent" ? this.subagent(t, n, inPanes, shown) : this.group(t, n);
    return v_flex()
      .size_full()
      .min_h(0)
      .bg(t.chrome)
      .text_size(12.5)
      .child(this.header(t, false))
      .when(listed.length === 0, (el) =>
        el.child(
          div()
            .px(12)
            .pt(8)
            .text_size(11.5)
            .text_color(t.dim)
            .child("No agent status yet. Agents show up here when they report their status. Older versions and agents inside tmux may not."),
        ),
      )
      .child(list.children(rows(computers, this.folded).map(draw)));
  }
}
