{
  appimageTools,
  fetchurl,
  lib,
}:
let
  pname = "wooting-bg-service";
  release = builtins.fromJSON (builtins.readFile ./release.json);
  inherit (release) version;
  src = fetchurl {
    name = "${pname}-${version}.AppImage";
    url = "https://api.wooting.io/public/bg-service/download-installer?target=linux&version=${version}";
    inherit (release) hash;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands =
    let
      contents = appimageTools.extract { inherit pname version src; };
    in
    ''
      install -Dm444 "${contents}/Wooting Background Service.desktop" \
        $out/share/applications/wooting-bg-service.desktop
      install -Dm444 ${contents}/wooting-bg-service.png -t $out/share/icons
    '';

  meta = {
    description = "Background service that lets Wootility talk to the keyboard outside the app";
    homepage = "https://wooting.io/wootility";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "wooting-bg-service";
  };
}
