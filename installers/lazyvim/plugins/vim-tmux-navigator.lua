-- vim-tmux-navigator: seamless C-h/j/k/l navigation between Neovim splits
-- and tmux panes. The plugin's keymaps check whether vim's cursor actually
-- moved; if it didn't (you're at the edge of vim's splits), it shells out
-- to `tmux select-pane` so focus hops into the adjacent tmux pane instead.
--
-- Requires matching tmux bindings — see tmux/tmux.conf at the repo root.
-- https://github.com/christoomey/vim-tmux-navigator

return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<C-h>",  "<cmd>TmuxNavigateLeft<cr>",     desc = "Window left  (tmux-aware)" },
    { "<C-j>",  "<cmd>TmuxNavigateDown<cr>",     desc = "Window down  (tmux-aware)" },
    { "<C-k>",  "<cmd>TmuxNavigateUp<cr>",       desc = "Window up    (tmux-aware)" },
    { "<C-l>",  "<cmd>TmuxNavigateRight<cr>",    desc = "Window right (tmux-aware)" },
    { "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Window previous (tmux-aware)" },
  },
}
