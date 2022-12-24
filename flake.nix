let
  name = "acl2s-overlay";
  description = "An acl2s build for Nix";
in {
  inherit name description;

  inputs = {
    nixpkgs.url     = github:nixos/nixpkgs/release-22.05;
    flake-utils.url = github:numtide/flake-utils;

    # Used for shell.nix
    flake-compat = {
      url = github:edolstra/flake-compat;
      flake = false;
    };

    scripts = {
      url = "https://gitlab.com/acl2s/external-tool-support/scripts.git";
      flake = false;
    };

    acl2 = {
      url = github:acl2/acl2;
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, scripts, acl2, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;
        package = import ./default.nix { inherit lib system; };
      in rec {
          defaultPackage = package;
          packages.acl2s = defaultPackage;

          apps = rec {
            default = apps.acl2s;
            acl2s = flake-utils.lib.mkApp { drv = packages.default; };
          };

          overlays.default = final: prev: {
            acl2s = outputs.packages.default;
          };

          devShells.default = pkgs.mkShell {
            inherit name description;
            buildInputs = with pkgs; [
              sbcl
              openssl
              z3
              z3.lib
              gcc
              pkg-config
              zlib
              clang
            ];
            LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (with pkgs; [
              sbcl
              openssl
              z3
              z3.lib
              gcc
              pkg-config
              zlib
              clang
            ])}:$LD_LIBRARY_PATH";
          };

          # For compatibility with older versions of the `nix` binary
          devShell = self.devShells.${system}.default;
        }
    );
}
