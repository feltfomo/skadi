# the capability names a theme adapter declares about itself. the compiler and
# the matugen runtime select adapters by these rather than probing for fields,
# so an adapter that grows a behavior says so once, here, in its own file
{
  nativeBlocks = "native-blocks";
  blockFiles = "block-files";
  aggregateFiles = "aggregate-files";
  matugenRuntime = "matugen-runtime";
}
