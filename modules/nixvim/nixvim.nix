{ inputs, ... }:
{
  flake.nixosModules.nixvim =
    { ... }:
    {
      home-manager.users.feltfomo = {
        imports = [ inputs.nixvim.homeModules.nixvim ];
        programs.nixvim = {
          enable = true;
          colorschemes.catppuccin.enable = true;
          plugins = {
            lualine.enable = true;
            plugins.lsp = {
              enable = true;
              servers = {
                lua_ls.enable = true;
                rust_analyzer = {
                  enable = true;
                  installCargo = false;
                  installRustc = false;
                };
                nil_ls.enable = true;
                opts.clipboard = "unnamedplus";
              };
            };
          };
        };
      };
    };
}
