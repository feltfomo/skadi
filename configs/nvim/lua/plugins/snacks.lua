return {
  "folke/snacks.nvim",
  --made it load so there is no error from plugin loading race condition
  priority = 1000,
  lazy = false,
  --@type snacks.Config
  keys = {
    { "<leader>e", function() Snacks.explorer() end, desc = "File Explorer" },
  },
  opts = {
    dashboard = {
      width = 100,
      preset = {
        header = [[
                                       __        ____      __
                                      /  \       \   \    /  \
                                      \   \       \   \  /   /
                                       \   \       \   \/   /
                                  ______\   \______ \      /
                                 /                 \ \    /     /\
                                /_______    ________\ \   \    /  \
                                       /   /           \   \  /   /
                                      /   /             \  / /   /
                             ________/   /               \/ /   /_____
                            /           /                  /          \
                            \______    /                  /   ________/
                                  /   / /\               /   /
                                 /   / /  \             /   /
                                /   /  \   \  _________/   /______
                                \  /    \   \ \                  /
                                 \/     /    \ \______    ______/
                                       /      \       \   \
                                      /   /\   \       \   \
                                     /   /  \   \       \   \
                                     \__/    \___\       \__/]],
      },
      formats = {
        header = { "%s", align = "left" },
      },
    },
    explorer = {}
  }
}
