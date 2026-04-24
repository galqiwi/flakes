{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      version = "0.125.0";
      tag = "rust-v${version}";
      base = "https://github.com/openai/codex/releases/download/${tag}";

      platforms = {
        aarch64-darwin = {
          url = "${base}/codex-aarch64-apple-darwin.tar.gz";
          hash = "sha256-apJtwMuWOdNJtivtoZB8U8sTSXCefcnPxTJo9DjLdJ8=";
          bin = "codex-aarch64-apple-darwin";
        };
        aarch64-linux = {
          url = "${base}/codex-aarch64-unknown-linux-musl.tar.gz";
          hash = "sha256-cAvDskCWPWrg9PYHjU7eDrB5mf/AjRNIuLCR3qxLecg=";
          bin = "codex-aarch64-unknown-linux-musl";
        };
        x86_64-linux = {
          url = "${base}/codex-x86_64-unknown-linux-musl.tar.gz";
          hash = "sha256-SiClOUOn5qDF+kRj1OR8WN2OVT7OveRVpBB+mQa/sAE=";
          bin = "codex-x86_64-unknown-linux-musl";
        };
      };

      claudeCodeVersion = "2.1.110";
      claudeCodeSrc = {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${claudeCodeVersion}.tgz";
        hash = "sha256-qeaNuuKyeJO+4TsBnP9kF6ydtZR8vCCdodqGuJX3alg=";
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
                --add-flags "$out/lib/claude-code/cli.js" \
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
