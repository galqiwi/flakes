{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      version = "0.128.0";
      tag = "rust-v${version}";
      base = "https://github.com/openai/codex/releases/download/${tag}";

      platforms = {
        aarch64-darwin = {
          url = "${base}/codex-aarch64-apple-darwin.tar.gz";
          hash = "sha256-8GggLoqJjCQMjAaEAbzNMLp7VvYfX/zRSD1UXUeq89U=";
          bin = "codex-aarch64-apple-darwin";
        };
        aarch64-linux = {
          url = "${base}/codex-aarch64-unknown-linux-musl.tar.gz";
          hash = "sha256-MWG01TBP6ve++7D8tBv5p+5A4xun4+821AoAqjumy9A=";
          bin = "codex-aarch64-unknown-linux-musl";
        };
        x86_64-linux = {
          url = "${base}/codex-x86_64-unknown-linux-musl.tar.gz";
          hash = "sha256-iGuF5hGMC0MjRDfKAH++kjYRpTsQPQDg0650rvsg4jo=";
          bin = "codex-x86_64-unknown-linux-musl";
        };
      };

      claudeCodeVersion = "2.1.154";
      claudeCodeBase = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
      claudeCodePlatforms = {
        aarch64-darwin = {
          key = "darwin-arm64";
          sha256 = "bc9881b107d7be1743c64c8b72dd66798f5d0947dbc48ed0d77964c473661fd4";
        };
        aarch64-linux = {
          key = "linux-arm64";
          sha256 = "9f732de278f7adc61d29fd5b055ddaf1bae3bb26d75fe6e06a125602565777a8";
        };
        x86_64-linux = {
          key = "linux-x64";
          sha256 = "67f6cab7e6c124010f62ac18f8078bc09e0db6a5b9e8ae874e9e73033c451793";
        };
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
          claudeCodeMeta = claudeCodePlatforms.${system};

          # Install a nix-ld shim at the FHS loader path so foreign prebuilt
          # binaries (e.g. uv's managed CPython) can execute inside the
          # nix-only container. Linux-only; darwin already has a working loader.
          isLinux = pkgs.stdenv.hostPlatform.isLinux;
          isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
          ldName = if isAarch64 then "ld-linux-aarch64.so.1" else "ld-linux-x86-64.so.2";
          fhsLoaderPath = if isAarch64 then "/lib/${ldName}" else "/lib64/${ldName}";
          nixLoaderPath = "${pkgs.glibc}/lib/${ldName}";
          nixLdLibraryPath = pkgs.lib.makeLibraryPath [
            pkgs.glibc
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
            pkgs.openssl
          ];
          fhsWrapperArgs = pkgs.lib.optionalString isLinux ''
            --run 'if [ ! -e ${fhsLoaderPath} ]; then mkdir -p "$(dirname ${fhsLoaderPath})" 2>/dev/null && ln -sf ${pkgs.nix-ld}/libexec/nix-ld ${fhsLoaderPath} 2>/dev/null || true; fi' \
            --set NIX_LD ${nixLoaderPath} \
            --set NIX_LD_LIBRARY_PATH ${nixLdLibraryPath} \
          '';
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

          claude-code = pkgs.stdenvNoCC.mkDerivation {
            pname = "claude-code";
            version = claudeCodeVersion;
            src = pkgs.fetchurl {
              url = "${claudeCodeBase}/${claudeCodeVersion}/${claudeCodeMeta.key}/claude";
              sha256 = claudeCodeMeta.sha256;
            };
            dontUnpack = true;
            dontBuild = true;
            dontStrip = true;
            nativeBuildInputs = [ pkgs.makeWrapper ]
              ++ pkgs.lib.optionals isLinux [ pkgs.autoPatchelfHook ];
            buildInputs = pkgs.lib.optionals isLinux [ pkgs.alsa-lib ];
            installPhase = ''
              runHook preInstall
              install -Dm755 $src $out/bin/claude
              wrapProgram $out/bin/claude \
                --set DISABLE_AUTOUPDATER 1 \
                --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
                --set DISABLE_INSTALLATION_CHECKS 1 \
                --set USE_BUILTIN_RIPGREP 0 \
                --prefix PATH : ${pkgs.lib.makeBinPath (
                  [ pkgs.procps pkgs.ripgrep ]
                  ++ pkgs.lib.optionals isLinux [ pkgs.bubblewrap pkgs.socat ]
                )} \
                ${fhsWrapperArgs}
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
