{
  description = "ODT NixOS flake: Niri + Clavis/Quickshell + Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    niri.url = "github:sodiboo/niri-flake";
    clavis = {
      url = "github:StatIndet/quickshell/c9ecd66c66329889d48c791b30e001748eaf37a3";
      flake = false;
    };
  };

  outputs = { nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      enableRemoteAccess = false;
      hostname = "ODT";
      username = "ODT";
      homeManagerSource = nixpkgs.legacyPackages.${system}.home-manager.src;
    in
    {
      nixosConfigurations.ODT = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit enableRemoteAccess hostname inputs username; };
        modules = [
          "${homeManagerSource}/nixos"
          ./hosts/ODT/default.nix
        ];
      };
    };
}
