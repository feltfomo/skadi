{ config, pkgs, ... }:
let
  ucm = pkgs.callPackage ./ucm.nix { };
in
{
  hardware.firmware = [ pkgs.sof-firmware ];
  boot.kernelParams = [
    "snd_intel_dspcfg.dsp_driver=3"
    # preserve SSP1 and invert the jack signal, which reads present when empty.
    "snd_soc_sof_es8336.quirk=0x41"
  ];
  boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ./module.nix { }) ];

  # ES8326 needs its own mixer initialization and jack routes.
  systemd.user.services = {
    wireplumber.environment.ALSA_CONFIG_UCM2 = "${ucm}";
    pipewire.environment.ALSA_CONFIG_UCM2 = "${ucm}";
  };

  services.pipewire.wireplumber.extraConfig."51-es8326" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "device.name" = "alsa_card.pci-0000_00_1f.3-platform-sof-essx8336"; }
        ];
        # the driver's DAC control changes only the left channel.
        actions.update-props."api.alsa.soft-mixer" = true;
      }
    ];
  };
}
