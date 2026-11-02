{
  # programs that can't read the default path name their own, like persistence paths.
  den.quirks.avatar.description = "Extra avatar destinations declared by program aspects";

  # quirks reach class modules, while lexicon calls furnish callbacks with its own context, so the
  # requested paths are only readable here. home.file also collapses paths programs share, where
  # furnish would reject the duplicate.
  den.batteries.user-avatar = image: {
    homeManager =
      { avatar, lib, ... }:
      let
        destinations = [ (import ./_destination.nix) ] ++ lib.concatMap (entry: entry.destinations) avatar;
      in
      {
        home.file = lib.genAttrs destinations (_: {
          source = image;
        });
      };
  };
}
