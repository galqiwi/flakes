{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      version = "0.116.0";
      tag = "rust-v${version}";
      base = "https://github.com/openai/codex/releases/download/${tag}";

      platforms = {
        aarch64-darwin = {
          url = "${base}/codex-aarch64-apple-darwin.tar.gz";
          hash = "sha256-FIc19fIgmy9qMb18o2icYowubFJo/7oL6T93IPz4kvU=";
          bin = "codex-aarch64-apple-darwin";
        };
        aarch64-linux = {
          url = "${base}/codex-aarch64-unknown-linux-musl.tar.gz";
          hash = "sha256-NEX69ZHy4KLWqvpyYI/PPt72cz09imsO/VVZSKWGF7o=";
          bin = "codex-aarch64-unknown-linux-musl";
        };
        x86_64-linux = {
          url = "${base}/codex-x86_64-unknown-linux-musl.tar.gz";
          hash = "sha256-r6CJwDLDExeSGrwC+4gUU67UqoADWEEhce/NBp7OoeM=";
          bin = "codex-x86_64-unknown-linux-musl";
        };
      };

      claudeCodeVersion = "2.1.81";
      claudeCodeSrc = {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${claudeCodeVersion}.tgz";
        hash = "sha256-h1rMZyQalKYiC1WXEq/wssImRYUHZIwwjHPJeIvEWy8=";
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
