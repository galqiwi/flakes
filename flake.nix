{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      version = "0.107.0";
      tag = "rust-v${version}";
      base = "https://github.com/openai/codex/releases/download/${tag}";

      platforms = {
        aarch64-darwin = {
          url = "${base}/codex-aarch64-apple-darwin.tar.gz";
          hash = "sha256-mH5zDJyCJXU18rRepHAJMjJ1ajdw9ftDcOZShaN6/Bs=";
          bin = "codex-aarch64-apple-darwin";
        };
        aarch64-linux = {
          url = "${base}/codex-aarch64-unknown-linux-musl.tar.gz";
          hash = "sha256-uZTHHRxIqk40CqOqKVYxulS2uU8OLV7OPKdE6G/lLZ0=";
          bin = "codex-aarch64-unknown-linux-musl";
        };
        x86_64-linux = {
          url = "${base}/codex-x86_64-unknown-linux-musl.tar.gz";
          hash = "sha256-nBoWCG6XFXjwwW1Y0H/oKVeRwKWX7rf9Y4j4o/FXnO4=";
          bin = "codex-x86_64-unknown-linux-musl";
        };
      };

      forEachSystem = nixpkgs.lib.genAttrs (builtins.attrNames platforms);
    in {
      packages = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          meta = platforms.${system};
          src = pkgs.fetchurl {
            url = meta.url;
            hash = meta.hash;
          };
        in {
          codex = pkgs.stdenv.mkDerivation {
            pname = "codex";
            inherit version src;
            sourceRoot = ".";
            nativeBuildInputs = [ pkgs.gnutar ];
            unpackPhase = ''
              tar xzf $src
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp ${meta.bin} $out/bin/codex
              chmod +x $out/bin/codex
            '';
          };
        }
      );
    };
}
