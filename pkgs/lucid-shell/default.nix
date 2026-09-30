{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  writeShellScriptBin,
  symlinkJoin,
  quickshell,
  qt6,
  python3,
  bash,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  gawk,
  procps,
  jq,
  curl,
  git,
  glib,
  librsvg,
  libnotify,
  libcanberra,
  sound-theme-freedesktop,
  noto-fonts-color-emoji,
  awww,
  matugen,
  pywal16,
  brightnessctl,
  playerctl,
  wireplumber,
  pulseaudio,
  bluez,
  networkmanager,
  kdePackages,
  hypridle,
  grim,
  wf-recorder,
  ffmpeg,
  imagemagick,
  wl-clipboard,
  wtype,
  cliphist,
  tesseract,
  hyprpicker,
  cava,
  songrec,
  fastfetch,
  swappy,
  xdg-utils,
}:
let
  version = "1.10.5";
  src = fetchFromGitHub {
    owner = "Sn3akyy1";
    repo = "lucid";
    rev = "09820bb50e65723e69dee33b9f6ec8caf5f588db";
    hash = "sha256-vxphoXdDvXWW2G8WD2FKsuvYicwhGsz1IMKoygfbLgM=";
  };
  python = python3.withPackages (p: [
    p.pillow
    p.numpy
    p.fonttools
    p.pygobject3
    p.pyyaml
  ]);
  shell = quickshell.withModules [
    qt6.qt5compat
    qt6.qtmultimedia
  ];
  data = stdenvNoCC.mkDerivation {
    pname = "lucid-shell-data";
    inherit version src;
    nativeBuildInputs = [
      python
      bash
    ];
    dontBuild = true;
    postPatch = ''
      python ${./patch-paths.py} . ${lib.escapeShellArg (toString sound-theme-freedesktop)} ${lib.escapeShellArg (toString noto-fonts-color-emoji)}
      substituteInPlace support/lucid/launch-shell.sh \
        --replace-fail '/usr/share/vulkan/icd.d' '/run/opengl-driver/share/vulkan/icd.d' \
        --replace-fail '/usr/lib /usr/lib64 /usr/lib/x86_64-linux-gnu' '/run/opengl-driver/lib /run/opengl-driver-32/lib'
      patchShebangs .
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/shell" "$out/helpers" "$out/defaults" "$out/templates"
      cp *.qml VERSION "$out/shell/"
      cp -r assets lucid*/ "$out/shell/"
      cp -r support/lucid/. "$out/helpers/"
      cp support/wallpaper/set-wallpaper.sh "$out/helpers/"
      cp -r defaults/. "$out/defaults/"
      cp support/cava/quickshell.conf "$out/defaults/cava.conf"
      cp -r support/matugen/templates/. "$out/templates/"
      install -Dm644 LICENSE "$out/share/licenses/lucid-shell/LICENSE"
      runHook postInstall
    '';
  };
  runtimePath = lib.makeBinPath [
    shell
    python
    bash
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    procps
    jq
    curl
    git
    glib
    librsvg
    libnotify
    libcanberra
    awww
    matugen
    pywal16
    brightnessctl
    playerctl
    wireplumber
    pulseaudio
    bluez
    networkmanager
    kdePackages.kdeconnect-kde
    hypridle
    grim
    wf-recorder
    ffmpeg
    imagemagick
    wl-clipboard
    wtype
    cliphist
    tesseract
    hyprpicker
    cava
    songrec
    fastfetch
    swappy
    xdg-utils
  ];
  launcher = writeShellScriptBin "lucid-shell" ''
    export PATH=${runtimePath}:"$PATH"
    if [[ "''${1:-}" == --explain ]]; then
      exec ${data}/helpers/launch-shell.sh --explain
    fi
    if [[ ! -f "$HOME/.config/quickshell/lucid/shell.qml" ]]; then
      echo "lucid-shell: deploy the Skadi lucid aspect with furnish before launching" >&2
      exit 1
    fi
    exec ${data}/helpers/launch-shell.sh -p "$HOME/.config/quickshell/lucid" "$@"
  '';
  ipc = writeShellScriptBin "lucid-shell-ipc" ''
    export PATH=${runtimePath}:"$PATH"
    exec ${shell}/bin/quickshell ipc -p "$HOME/.config/quickshell/lucid" call -- "$@"
  '';
  wallpaper = writeShellScriptBin "lucid-wallpaper" ''
    export PATH=${runtimePath}:"$PATH"
    exec ${data}/helpers/set-wallpaper.sh "$@"
  '';
in
symlinkJoin {
  name = "lucid-shell-${version}";
  paths = [
    launcher
    ipc
    wallpaper
  ];
  passthru = { inherit data src; };
  meta = {
    description = "Lucid desktop shell for Hyprland";
    homepage = "https://github.com/Sn3akyy1/lucid";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "lucid-shell";
  };
}
