{
  lib,
  rustPlatform,
  fetchFromGitHub,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "herdr-nvim";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "ChmaraX";
    repo = "herdr-nvim";
    rev = "5e849b5377fd409d2fd4be159c9c9fa36c251f7a";
    hash = "sha256-BdZygw+OdfNlcEmb6v6ic9HV8ImxU3bDCq+28qu8Er0=";
  };
  cargoHash = "sha256-pImtQ1YiM47VvA8u9ER/lXtDVsZhQy38fkCbzmT/gc4=";

  nativeCheckInputs = [ git ];
  # the picker integration test searches tracked files in its source checkout.
  preCheck = ''
    git init -q
    git add Cargo.toml src
  '';

  postInstall = ''
    cp herdr-plugin.toml "$out/"
    cp -r lua plugin doc "$out/"
  '';

  meta = {
    description = "Neovim sidebar and code annotations for herdr";
    homepage = "https://github.com/ChmaraX/herdr-nvim";
    license = lib.licenses.mit;
    mainProgram = "herdr-nvim";
  };
}
