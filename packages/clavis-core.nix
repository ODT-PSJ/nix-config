{ pkgs, src }:

pkgs.stdenv.mkDerivation {
  pname = "clavis-core";
  version = "c9ecd66";
  inherit src;

  sourceRoot = "source/core";

  patches = [
    ./patches/clavis-niri-metadata-updates.patch
  ];

  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    patchelf
    pkg-config
  ];

  buildInputs = with pkgs; [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qtshadertools
    qt6.qttools
    qt6Packages.qtkeychain
    pipewire
    ncurses
    libcava
    libglvnd.dev
  ];

  cmakeFlags = [
    "-DBUILD_TESTING=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_BUILD_RPATH_USE_ORIGIN=ON"
  ];

  dontWrapQtApps = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/key "$out/bin/key"
    mkdir -p "$out/lib/qt-6/qml"
    cp -r Clavis M3Shapes "$out/lib/qt-6/qml/"

    m3ShapesLibrary="$(find . -type f -name libM3Shapes.so -print -quit)"
    test -n "$m3ShapesLibrary"
    install -Dm755 "$m3ShapesLibrary" "$out/lib/qt-6/qml/M3Shapes/libM3Shapes.so"
    patchelf --add-rpath '$ORIGIN' "$out/lib/qt-6/qml/M3Shapes/libM3Shapesplugin.so"

    runHook postInstall
  '';
}
