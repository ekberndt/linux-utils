-- Dotted quads like 100.52.62.2 are parsed as URLs. Colorschemes underline
-- those captures; JetBrains Mono's x-height puts that line through the digits,
-- which reads as strikethrough. The terminal already paints hyperlink
-- underlines — don't stack a second one on the token.
local groups = { "@string.special.url", "@markup.link.url" }

local function drop_url_underline()
  for _, group in ipairs(groups) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if ok and hl then
      hl.underline = false
      hl.underdotted = false
      hl.underdashed = false
      hl.undercurl = false
      vim.api.nvim_set_hl(0, group, hl)
    end
  end
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("linux-utils-url-underline", { clear = true }),
        callback = drop_url_underline,
      })
    end,
  },
}
