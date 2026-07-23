{ rootPath, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      rebuild-vm-golden = pkgs.buildGoModule {
        pname = "rebuild-vm-golden";
        version = "0.1.0";
        src = rootPath + "/go";
        vendorHash = null;
        subPackages = [ "cmd/rebuild-vm-golden" ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        # host-side runtime deps; nix left ambient to match vm-test.nix.
        postInstall = ''
          wrapProgram $out/bin/rebuild-vm-golden \
            --prefix PATH : ${lib.makeBinPath [
              pkgs.qemu_kvm
              pkgs.openssh
              pkgs.git
              pkgs.ssh-to-age
              pkgs.coreutils
              pkgs.gnutar
              pkgs.gzip
            ]} \
            --set OVMF_FD ${pkgs.OVMF.fd}
        '';
        meta = {
          description = "One-command harness that rebuilds and verifies the signed golden VM image from a pinned revision";
          mainProgram = "rebuild-vm-golden";
        };
      };
    in
    {
      packages.rebuild-vm-golden = rebuild-vm-golden;
      apps.rebuild-vm-golden = {
        type = "app";
        program = "${rebuild-vm-golden}/bin/rebuild-vm-golden";
      };
    };
}