final: prev:
let
  patchKvantum =
    package:
    package.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./kvantum/reload.patch ];
      postPatch = (old.postPatch or "") + ''
        cp ${./kvantum/palette-reload.h} style/palette-reload.h
      '';
    });
in
{
  skadi-gtk-reload = final.callPackage ./gtk { };
  libsForQt5 = prev.libsForQt5.overrideScope (
    _: qt: {
      qtstyleplugin-kvantum = patchKvantum qt.qtstyleplugin-kvantum;
    }
  );
  qt6Packages = prev.qt6Packages.overrideScope (
    _: qt: {
      qtstyleplugin-kvantum = patchKvantum qt.qtstyleplugin-kvantum;
    }
  );
}
