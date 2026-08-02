{
  program,
  rootPath,
  ...
}:
{
  den.aspects.noctalia = program {
    directories = [
      {
        src = "${rootPath}/configs/noctalia";
        dest = ".config/noctalia";
      }
    ];
  };
}
