import { View, div } from "gpui-kit";
import { h_flex, v_flex, Input, InputState } from "gpui-base";
import { closeOverlay, exec, pickFolder, props, run, theme } from "herdr";

// Resolve paths on the target, not on the desktop. The path is an argv value,
// never shell source; even a checkout literally named "$(date)" stays literal.
const folderCommand = `set -e
case "$1" in
  '~') path=$HOME ;;
  '~/'*) path=$HOME/\${1#??} ;;
  /*) path=$1 ;;
  *) path=\${3:-$HOME}/$1 ;;
esac
case "$2" in
  create) mkdir -p -- "$path" ;;
  repo) git init -- "$path" >&2 ;;
esac
CDPATH= cd -- "$path"
pwd -P`;

export default class OpenFolder extends View {
  init(_props, cx) {
    const p = props();
    this.machine = p?.machine ?? null;
    this.base = p?.folder || "";
    this.overlay = p?.overlay;
    this.input = InputState.new({ placeholder: "Folder path" });
    this.input.on("submit", (_e, cx) => this.open("open", cx));
    this.input.on("change", (_e, cx) => { this.error = ""; cx.notify(); });
    this.handle = cx.focus_handle();
    this.input.focus();
  }

  close() {
    this.closed = true;
  }

  open(action, cx) {
    const path = this.input.value();
    if (!path || this.busy) return;
    this.busy = true;
    this.error = "";
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const r = await exec("sh", ["-c", folderCommand, "open-folder", path, action, this.base], { on: this.machine });
        if (this.closed) return;
        if (r.code !== 0) throw new Error(r.stderr.trim() || "Could not open folder");
        run("space.new", { machine: this.machine ?? "", folder: r.stdout.replace(/\n$/, "") });
        closeOverlay(this.overlay);
      } catch (e) {
        this.error = String(e);
      } finally {
        this.busy = false;
        if (!this.closed) cx.notify();
      }
    });
  }

  render() {
    const t = theme();
    const button = (id, label, click, primary = false) => div().id(id).px(10).py(6).rounded(6)
      .cursor_pointer().bg(primary ? t.solid : t.raised).text_color(primary ? t.solid_foreground : t.foreground)
      .hover((s) => s.opacity(0.85)).on_click(click).child(label);
    const canOpen = Boolean(this.input.value()) && !this.busy;
    return v_flex().id("open-folder").track_focus(this.handle).w_full().p(16).gap(10)
      .bg(t.popover).text_size(12.5).text_color(t.foreground)
      .child(div().text_size(15).font_semibold().child("Open repo or folder"))
      .child(div().text_color(t.muted).child(`${this.machine ?? "This computer"} · ${this.base || "~"}`))
      .child(h_flex().gap(6).items_center()
        .child(Input.new(this.input).flex_1().h(34).px(8).rounded(6).border(1).border_color(t.input).bg(t.background))
        .when(!this.machine, (el) => el.child(button("browse", "Browse…", (_e, cx) => cx.spawn(async () => {
          const picked = await pickFolder({ prompt: "Choose folder" });
          if (picked) this.input.set_value(picked);
        })))))
      .when(Boolean(this.error), (el) => el.child(div().text_color(t.blocked).child(this.error)))
      .child(h_flex().gap(6).justify_end().when(!canOpen, (el) => el.opacity(0.5))
        .child(button("create", "Create folder", (_e, cx) => this.open("create", cx)))
        .child(button("repo", "New Git repo", (_e, cx) => this.open("repo", cx)))
        .child(button("open", this.busy ? "Opening…" : "Open", (_e, cx) => this.open("open", cx), true)));
  }
}
