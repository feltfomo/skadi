{
  stdenvNoCC,
  fetchFromGitHub,
  neovim,
}:
let
  pin = (builtins.fromJSON (builtins.readFile ../../configs/nvim/lazy-lock.json))."neo-tree.nvim";
in
stdenvNoCC.mkDerivation {
  pname = "neo-tree.nvim";
  version = builtins.substring 0 12 pin.commit;
  src = fetchFromGitHub {
    owner = "nvim-neo-tree";
    repo = "neo-tree.nvim";
    rev = pin.commit;
    hash = "sha256-jZOBMPBfyHWPg4pdo7JWrl+pZ3WSxCSLqPFG7VUiDXs=";
  };
  patches = [ ./preserve-grouped-siblings.patch ];
  nativeBuildInputs = [ neovim ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    nvim --headless -u NONE -i NONE -c 'helptags doc' -c quit
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    mkdir "$out/help"
    mv "$out/doc" "$out/help/doc"
    runHook postInstall
  '';
}
