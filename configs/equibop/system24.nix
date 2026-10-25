{
  fetchFromGitHub,
  runCommand,
  fetchurl,
  python3,
  palette,
  lib,
}:
let
  system24 = fetchFromGitHub {
    owner = "refact0r";
    repo = "system24";
    rev = "35a069674115e9676316e4c0ad6aad7089436be2";
    hash = "sha256-C/seCeh2+eevdtWKMMUS2vlFsmsvFXrQvHvhEOEeuik=";
  };
  midnight = fetchFromGitHub {
    owner = "refact0r";
    repo = "midnight-discord";
    rev = "8598b2d540c51b5ab06364818b405bd5c66e2509";
    hash = "sha256-r+g7ehjTWfxBlFhXov2fCQT1ljVrmK/LVhLCQC82C+A=";
  };
  fontRevision = "bfb7c046dea572dca9fdd435481ba2f36b0a1ebc";
  fontSource =
    name: hash:
    fetchurl {
      url = "https://raw.githubusercontent.com/google/fonts/${fontRevision}/ofl/dmmono/${name}";
      inherit hash;
    };
  fontLicense = fontSource "OFL.txt" "sha256-K62l6kXDxjt/HqH4jOlnLJ5PDEKyw7c3iUkIT+VaMGY=";
  fonts = [
    {
      name = "DMMono-MediumItalic.ttf";
      weight = 500;
      style = "italic";
      hash = "sha256-o7IhG7nPXE/BoLSHVT5nOnN8InDFm4a/HgtIx35YeqI=";
    }
    {
      name = "DMMono-LightItalic.ttf";
      weight = 300;
      style = "italic";
      hash = "sha256-kCFhklVdVs1AhXJQu9bQ6BMN29AVmS1YQiXX85CElUQ=";
    }
    {
      name = "DMMono-Regular.ttf";
      weight = 400;
      style = "normal";
      hash = "sha256-VbTJjxI9rrs+0nlHukeyrwBVT8YoTWOaVAvO9eYlitI=";
    }
    {
      name = "DMMono-Medium.ttf";
      weight = 500;
      style = "normal";
      hash = "sha256-/TJ9r0YduHtEqH3vR10lG/A7mX98B9loBZLXXbv6rQs=";
    }
    {
      name = "DMMono-Italic.ttf";
      weight = 400;
      style = "italic";
      hash = "sha256-MrW62cvOZOrG0FyKu+thkxf35Ms1Thwz23Ya2/quGxY=";
    }
    {
      name = "DMMono-Light.ttf";
      weight = 300;
      style = "normal";
      hash = "sha256-x7NkXcjSgjcxe00Be8R7n/CadmB1gSLay2lKWoJVLCQ=";
    }
  ];
  fontArguments = lib.concatMapStringsSep " " (
    font: "--font ${toString font.weight} ${font.style} ${fontSource font.name font.hash}"
  ) fonts;
in
runCommand "equibop-system24.css" { nativeBuildInputs = [ python3 ]; } ''
  set -euo pipefail
  python ${./compose.py} \
    --system24 ${system24} \
    --midnight ${midnight} \
    --font-license ${fontLicense} \
    ${fontArguments} \
    --overrides ${./overrides.css} \
    --palette ${palette} \
    --output "$out"
''
