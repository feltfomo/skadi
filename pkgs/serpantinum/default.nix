{
  upstream,
  python3,
  lib,
  licenseFile,
}:
upstream.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ python3 ];
  postPatch = (old.postPatch or "") + ''
    python3 ${./patch-runtime.py} .
  '';
  postInstall = (old.postInstall or "") + ''
    install -Dm644 ${licenseFile} "$out/share/licenses/serpantinum/LICENSE.md"
  '';
  # The upstream package metadata disagrees with its README and license file.
  meta = old.meta // {
    license = lib.licenses.agpl3Plus;
  };
})
