{ lexicon, ... }:
{
  den.aspects.native-debugging = lexicon {
    package = pkgs: pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter;
  };
}
