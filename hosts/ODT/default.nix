{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./system.nix
    ./hardware.nix
    ./laptop.nix
    ./desktop.nix
    ./clavis.nix
    ./home.nix
    ./proxy.nix
    ./openssh.nix
  ];
}
