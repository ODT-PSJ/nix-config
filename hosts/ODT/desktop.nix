{ inputs, pkgs, ... }:
let
  niriPackages = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.niri.enable = true;
  programs.niri.package = niriPackages.niri-unstable;

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet -r --time --cmd niri-session";
      user = "greeter";
    };
  };

  programs.firefox.enable = true;
  programs.steam.enable = true;
  programs.thunar = {
    enable = true;
    plugins = [ pkgs.thunar-archive-plugin ];
  };

  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.tumbler.enable = true;
  services.flatpak.enable = true;

  environment.systemPackages = with pkgs; [
    vim wget curl git helix
    wlogout
    qt6Packages.fcitx5-configtool
    wl-clipboard cliphist
    grim slurp
    brightnessctl playerctl
    polkit_gnome
    xdg-utils
    adwaita-icon-theme
    usbutils exfatprogs
    bluez
    loupe celluloid papers file-roller
    yazi go-musicfox
    kooha wechat protonmail-desktop zed-editor
    niriPackages.xwayland-satellite-unstable
  ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
