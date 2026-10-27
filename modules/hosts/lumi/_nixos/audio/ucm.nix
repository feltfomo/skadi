{
  alsa-ucm-conf,
  runCommand,
}:
runCommand "lumi-es8326-ucm" { } ''
  set -euo pipefail
  mkdir -p "$out"
  cp -R --no-preserve=mode ${alsa-ucm-conf}/share/alsa/ucm2/. "$out/"
  install -m 644 ${./sof-essx8336.conf} "$out/Intel/sof-essx8336/sof-essx8336.conf"
  install -m 644 ${./HiFi.conf} "$out/Intel/sof-essx8336/HiFi.conf"
''
