# NixOS wrapper: the same options under services.moqs, applied to one user through Home Manager.
# Needs the Home Manager NixOS module to be imported as well.
self:
{
  config,
  lib,
  ...
}:

let
  cfg = config.services.moqs;
in
{
  options.services.moqs = import ./options.nix { inherit lib; } // {
    user = lib.mkOption {
      type = lib.types.str;
      example = "alice";
      description = "The user whose Home Manager configuration gets the shell.";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [ self.homeManagerModules.default ];
    home-manager.users.${cfg.user}.services.moqs = builtins.removeAttrs cfg [ "user" ];
  };
}
