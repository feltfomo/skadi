{
  lexicon,
  rootPath,
  ...
}:
{
  den.aspects.noctalia = lexicon {
    furnish.directories = [
      {
        source = "${rootPath}/configs/noctalia";
        destination = ".config/noctalia";
      }
    ];
  };
}
