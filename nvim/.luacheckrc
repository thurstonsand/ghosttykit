---@diagnostic disable: lowercase-global

std = "luajit+busted"
codes = true
unused_args = false
max_line_length = false
globals = {
  "vim",
}
exclude_files = {
  ".luarocks/**",
}
