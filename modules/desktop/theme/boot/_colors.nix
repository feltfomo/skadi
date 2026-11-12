# the palette's #rrggbb roles in the forms the boot stages read.
{ lib }:
let
  channels = hex: map (i: lib.fromHexString (builtins.substring i 2 (lib.removePrefix "#" hex))) [
    0
    2
    4
  ];
in
{
  # "rrggbb", as console.colors takes it.
  bare = hex: lib.toLower (lib.removePrefix "#" hex);
  # "r, g, b" in 0-1, as plymouth's script functions take it.
  unit = hex: lib.concatMapStringsSep ", " (c: toString (c / 255.0)) (channels hex);
}
