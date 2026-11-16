{
  description = "moqs: a minimal Quickshell shell for Hyprland";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # The QML sources only; settings files are added by the module.
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      homeManagerModules = {
        moqs = import ./nix/home-manager.nix self;
        default = self.homeManagerModules.moqs;
      };

      nixosModules = {
        moqs = import ./nix/nixos.nix self;
        default = self.nixosModules.moqs;
      };

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
