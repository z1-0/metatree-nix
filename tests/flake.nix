{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-meta.url = "github:z1-0/nix-meta";
    srctree.url = "github:z1-0/srctree-nix";
  };

  outputs =
    { nixpkgs, flake-utils, nix-meta, srctree, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = import ../default.nix { inherit nix-meta srctree; };
        failures =
          import ./unit.nix { inherit lib pkgs; } ++ import ./integration.nix { inherit lib pkgs; };
      in
      {
        checks.tests = pkgs.runCommand "metatree-nix-tests" {
          requiredTestResults = pkgs.lib.debug.throwTestFailures { inherit failures; };
        } "echo all tests passed > $out";
      }
    );
}