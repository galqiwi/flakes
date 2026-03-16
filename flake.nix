{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      version = "0.114.0";
      tag = "rust-v${version}";
      base = "https://github.com/openai/codex/releases/download/${tag}";

      platforms = {
        aarch64-darwin = {
          url = "${base}/codex-aarch64-apple-darwin.tar.gz";
          hash = "sha256-yY61UGlfmersJ9+ZcaG3aoOssV61VSI4P6MbBJcpfFQ=";
          bin = "codex-aarch64-apple-darwin";
        };
        aarch64-linux = {
          url = "${base}/codex-aarch64-unknown-linux-musl.tar.gz";
          hash = "sha256-fTBzVoEHfBO28NpuiCo6r5ZY3yDRVfXZkiL7ex0pAJk=";
          bin = "codex-aarch64-unknown-linux-musl";
        };
        x86_64-linux = {
          url = "${base}/codex-x86_64-unknown-linux-musl.tar.gz";
          hash = "sha256-kinejFHI7zBWW7UHyXou3ASoCzjkmkNj8zf+Bb7fNOs=";
          bin = "codex-x86_64-unknown-linux-musl";
        };
      };

      claudeCodeVersion = "2.1.76";
      claudeCodeSrc = {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${claudeCodeVersion}.tgz";
        hash = "sha256-9jZLd7ZQN49skILYN4SHUMWf2w/esCp4+crohwK7eqU=";
      };

      forEachSystem = nixpkgs.lib.genAttrs systems;
    in {
      packages = forEachSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          codexMeta = platforms.${system};
          codexSrc = pkgs.fetchurl {
            url = codexMeta.url;
            hash = codexMeta.hash;
          };
        in {
          codex = pkgs.stdenv.mkDerivation {
            pname = "codex";
            inherit version;
            src = codexSrc;
            sourceRoot = ".";
            nativeBuildInputs = [ pkgs.gnutar ];
            unpackPhase = ''
              tar xzf $src
            '';
            installPhase = ''
              mkdir -p $out/bin
              cp ${codexMeta.bin} $out/bin/codex
              chmod +x $out/bin/codex
            '';
          };

          claude-code = pkgs.stdenv.mkDerivation {
            pname = "claude-code";
            version = claudeCodeVersion;
            src = pkgs.fetchurl claudeCodeSrc;
            sourceRoot = "package";
            nativeBuildInputs = [ pkgs.makeWrapper ];
            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib/claude-code $out/bin
              cp -r . $out/lib/claude-code
              makeWrapper ${pkgs.nodejs}/bin/node $out/bin/claude \
                --add-flags "$out/lib/claude-code/cli.js"
              runHook postInstall
            '';
            meta.mainProgram = "claude";
          };
        }
      );

      apps = forEachSystem (system: {
        claude-code = {
          type = "app";
          program = "${self.packages.${system}.claude-code}/bin/claude";
        };
      });
    };
}
