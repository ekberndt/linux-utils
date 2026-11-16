// Popup menu for opening a new terminal tab or agent session in a chosen repo,
// folder, or computer — without Herdr's built-in worktree dialog.

import { View, div, svg, image } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import {
  theme,
  spaces,
  panes,
  knownAgents,
  pickFolder,
  home,
  checking,
  run,
  closeOverlay,
  props,
  window,
  keys,
  shared,
  setShared,
} from "herdr";

const KNOWN = "new-menu.agents";

function shortcut(action) {
  const k = keys().find((b) => b.section === "global" && b.action === action);
  if (!k?.keys.trim()) return "";
  const mac = window()?.platform === "macos";
  const names = mac
    ? { ctrl: "⌃", alt: "⌥", shift: "⇧", cmd: "⌘", fn: "fn" }
    : { ctrl: "Ctrl", alt: "Alt", shift: "Shift", cmd: "Super", fn: "Fn" };
  const alias = { secondary: mac ? "cmd" : "ctrl", super: "cmd", win: "cmd" };
  return k.keys
    .trim()
    .split(/\s+/)
    .map((stroke) => {
      const parts = stroke.split("-");
      let key = parts.pop();
      if (key === "") {
        key = "-";
        parts.pop();
      }
      const held = new Set(parts.map((m) => alias[m.toLowerCase()] ?? m.toLowerCase()));
      if (/^[A-Z]$/.test(key)) held.add("shift");
      const label = key.length === 1 ? key.toUpperCase() : key[0].toUpperCase() + key.slice(1).toLowerCase();
      return [...Object.keys(names).filter((m) => held.has(m)).map((m) => names[m]), label].join(mac ? "" : "+");
    })
    .join(" ");
}

function resolveTarget(p) {
  if (p && "machine" in p) {
    const machine = p.machine ?? null;
    const space =
      p.space ??
      spaces().find((s) => s.active && (s.machine ?? null) === machine)?.id ??
      spaces().find((s) => (s.machine ?? null) === machine)?.id ??
      null;
    const folder = p.folder || (machine === null ? home() : null);
    return { machine, space, folder, title: p.title ?? null };
  }
  const active = spaces().find((s) => s.active);
  const machine = active?.machine ?? null;
  const focusedCwd = panes().find((pn) => pn.focused && pn.cwd && (!active || active.tabs?.some((tb) => tb.id === pn.tab)))?.cwd;
  return {
    machine,
    space: active?.id ?? null,
    folder: focusedCwd || active?.folder || (machine === null ? home() : null),
    title: null,
  };
}

export function launchSession(target, agent = null) {
  const { machine, space, folder } = target;
  if (space) {
    const args = { space };
    if (folder) args.folder = folder;
    if (agent) {
      args.name = agent.name;
      args.argv = agent.run;
    }
    run("tab.new", args);
    return;
  }
  const args = { machine: machine ?? "" };
  if (folder) args.folder = folder;
  if (agent) {
    args.tab = agent.name;
    args.argv = agent.run;
  }
  run("space.new", args);
}

export default class SessionMenu extends View {
  init(_props, cx) {
    const { machine } = resolveTarget(props());
    const where = machine ?? "";
    this.agents = shared(KNOWN)?.[where] ?? [];
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    if (!checking()) {
      cx.spawn(async (cx) => {
        try {
          this.agents = await knownAgents({ on: machine });
          setShared(KNOWN, { ...(shared(KNOWN) ?? {}), [where]: this.agents });
        } catch {
          this.failed = true;
        }
        cx.notify();
      });
    }
  }

  entries(t, target) {
    const installed = this.agents.filter((a) => a.installed);
    const choices = this.failed ? installed : [...installed, ...this.agents.filter((a) => !a.installed).slice(0, 2)];
    const items = [
      {
        id: "terminal",
        icon: svg("icons/shell.svg").size(13).flex_none().text_color(t.foreground),
        label: "New terminal tab",
        hint: shortcut("tab.new"),
        enabled: true,
        run: () => launchSession(target, null),
      },
      ...choices.map((a, i) => ({
        id: `agent-${a.key}`,
        icon: a.tint
          ? svg(a.icon).size(13).flex_none().text_color(a.installed ? t.foreground : t.dim)
          : image(a.icon).size(13).flex_none(),
        label: a.name,
        hint: a.installed ? (i < 9 ? String(i + 1) : "") : "not installed",
        enabled: a.installed,
        section: i === 0 ? "Start session" : null,
        run: () => launchSession(target, a),
      })),
    ];
    if (target.machine === null) {
      items.push({
        id: "pick-folder",
        icon: svg("mods/workspace-chrome/folder-plus.svg").size(13).flex_none().text_color(t.muted),
        label: "New tab in folder…",
        hint: "",
        enabled: true,
        divider: true,
        run: (cx) => {
          cx.spawn(async () => {
            const picked = await pickFolder({ prompt: "Open terminal" });
            if (picked) launchSession({ ...target, folder: picked }, null);
          });
        },
      });
    }
    return { items, installed };
  }

  choose(item, cx) {
    if (!item?.enabled) return;
    closeOverlay(props()?.overlay);
    item.run(cx);
  }

  render() {
    const t = theme();
    const target = resolveTarget(props());
    const { items, installed } = this.entries(t, target);
    const enabledIndexes = items.map((it, idx) => (it.enabled ? idx : -1)).filter((idx) => idx >= 0);
    if (!items[this.at]?.enabled && enabledIndexes.length) this.at = enabledIndexes[0];

    const statusNote = this.failed
      ? "Could not check installed agents"
      : this.agents.length === 0
        ? "Checking installed agents…"
        : null;
    const height = Math.min(
      420,
      12 +
        (target.title ? 24 : 0) +
        (items.some((it) => it.section) ? 24 : 0) +
        (items.some((it) => it.divider) ? 9 : 0) +
        (statusNote ? 26 : 0) +
        items.length * 28,
    );

    return v_flex()
      .id("session-menu")
      .track_focus(this.handle)
      .min_h(0)
      .w_full()
      .h(height)
      .bg(t.popover)
      .p(5)
      .text_size(12.5)
      .on_key_down((e, cx) => {
        if (e.key === "escape") {
          closeOverlay(props()?.overlay);
          return;
        }
        if (e.key === "down" || e.key === "up") {
          if (!enabledIndexes.length) return;
          const pos = Math.max(0, enabledIndexes.indexOf(this.at));
          const step = e.key === "down" ? 1 : -1;
          this.at = enabledIndexes[(pos + step + enabledIndexes.length) % enabledIndexes.length];
          cx.notify();
          return;
        }
        if (e.key === "enter") {
          this.choose(items[this.at], cx);
          return;
        }
        if (!e.modifiers?.control && !e.modifiers?.platform && !e.modifiers?.alt && /^[1-9]$/.test(e.key)) {
          const agent = installed[Number(e.key) - 1];
          if (agent) {
            closeOverlay(props()?.overlay);
            launchSession(target, agent);
          }
        }
      })
      .when(Boolean(target.title), (el) =>
        el.child(div().px(8).pt(3).pb(5).truncate().text_size(11).font_medium().text_color(t.dim).child(target.title)),
      )
      .child(
        v_flex()
          .flex_1()
          .min_h(0)
          .overflow_y_scrollbar()
          .children(
            items.flatMap((it, idx) => {
              const out = [];
              if (it.section) {
                out.push(div().px(8).pt(6).pb(3).text_size(10.5).text_color(t.dim).child(it.section));
              }
              if (it.divider) {
                out.push(div().h(1).mx(4).my(4).bg(t.border));
              }
              out.push(
                h_flex()
                  .id(it.id)
                  .h(28)
                  .px(8)
                  .gap(8)
                  .rounded(6)
                  .items_center()
                  .flex_none()
                  .text_color(it.enabled ? t.foreground : t.dim)
                  .when(it.enabled && idx === this.at, (el) => el.bg(t.selected))
                  .when(it.enabled, (el) => el.cursor_pointer().hover((s) => s.bg(t.hover)))
                  .on_click((_e, cx) => this.choose(it, cx))
                  .child(it.icon)
                  .child(div().flex_1().min_w(0).truncate().child(it.label))
                  .when(Boolean(it.hint), (el) => el.child(div().text_size(10.5).text_color(t.dim).child(it.hint))),
              );
              return out;
            }),
          )
          .when(Boolean(statusNote), (el) => el.child(div().px(8).py(5).text_size(11).text_color(t.dim).child(statusNote))),
      );
  }
}
