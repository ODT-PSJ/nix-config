{ pkgs, src }:

let
  meteoconsLottie = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@meteocons/lottie/-/lottie-0.1.0.tgz";
    hash = "sha256-Q+onMqvejkKcT8VqJ7ss79hT+MNKkEtX+GpLWivxoT0=";
  };
  meteoconsSvg = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@meteocons/svg/-/svg-0.1.0.tgz";
    hash = "sha256-kbSNH4SX2ej07R1bzDLTBqqlBQ3pnDhGfCpY963VpQE=";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "clavis-config";
  version = "c9ecd66";
  inherit src;

  patches = [
    ./patches/clavis-weather-summary-height.patch
    ./patches/clavis-asus-power-profile.patch
    ./patches/clavis-odt-compat.patch
    ./patches/clavis-odt-brightness.patch
    ./patches/clavis-backend-integration.patch
    ./patches/clavis-weather-actions.patch
    ./patches/clavis-package-backend-detection.patch
    ./patches/clavis-hidden-wifi.patch
    ./patches/clavis-mpris-stability.patch
    ./patches/clavis-compact-bar.patch
    ./patches/clavis-bluetooth-pairing.patch
    ./patches/clavis-fcitx-tray-icon.patch
  ];

  nativeBuildInputs = [ pkgs.gnutar ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r . "$out/"
    chmod -R u+w "$out"

    weatherDir="$out/assets/icons/weather/meteocons"
    mkdir -p "$weatherDir/lottie" "$weatherDir/svg"
    tar -xzf ${meteoconsLottie} -C "$weatherDir/lottie" --strip-components=1
    tar -xzf ${meteoconsSvg} -C "$weatherDir/svg" --strip-components=1

    runHook postInstall
  '';
}
