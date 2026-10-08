{
  description = "terraform-cloudflare-backend - R2 as a Terraform state backend, with credentials from the environment.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;
        version = (lib.importJSON ./.github/config/release-please-manifest.json).".";
        name = "terraform-cloudflare-backend";
      in
      {
        # jq is its only dependency: the credentials come from the
        # environment, which the cloudflare-sts action, `cloudflare-sts exec`,
        # or an exported R2 API token sets.
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = name;
          inherit version;
          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./${name}
              ./backend.jq
            ];
          };
          nativeBuildInputs = [ pkgs.makeWrapper ];
          # For patchShebangs.
          buildInputs = [ pkgs.bash ];
          # The script finds backend.jq beside itself, so both go in libexec,
          # and bin gets a wrapper rather than a symlink.
          installPhase = ''
            runHook preInstall
            install -Dm755 ${name} $out/libexec/${name}/${name}
            install -Dm644 backend.jq $out/libexec/${name}/backend.jq
            makeWrapper $out/libexec/${name}/${name} $out/bin/${name} \
              --prefix PATH : ${lib.makeBinPath [ pkgs.jq ]}
            runHook postInstall
          '';
          meta = {
            description = "R2 credentials for Terraform's S3 backend, from the environment";
            homepage = "https://github.com/tf-contrib/terraform-cloudflare-backend";
            license = lib.licenses.mpl20;
            mainProgram = name;
            platforms = lib.platforms.unix;
          };
        };

        # The tests, against the package as people install it.
        checks.default =
          pkgs.runCommand "${name}-tests"
            {
              nativeBuildInputs = [
                pkgs.jq
                pkgs.shellcheck
              ];
            }
            ''
              shellcheck ${./${name}} ${./tests/run.sh}
              bash ${./tests/run.sh} ${self.packages.${system}.default}/bin/${name}
              touch $out
            '';

        devShells.default = pkgs.mkShell {
          inherit name;
          packages = [
            pkgs.jq
            pkgs.shellcheck
          ];
        };
      }
    );
}
