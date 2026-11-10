{
  # swap compressed in RAM, used ahead of the swapfile. builds and VM tests saturate the disk, and a
  # page of the shell or compositor swapped out to that disk then stalls every keystroke behind
  # them; a page in zram comes back without touching the disk. the swapfile stays as overflow.
  den.aspects.zram.nixos.zramSwap.enable = true;
}
