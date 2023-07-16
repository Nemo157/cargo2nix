{
  pkgs,
  lib,
  rustBuilder,
  rustLib,
  stdenv,
  mkRustCrate,
  mkRustCrateNoBuild,
  workspaceShell,
}:
{
  packageFun,
  workspaceSrc ? null,
  rustToolchain,
  buildRustPackages ? null,
  packageOverrides ? rustBuilder.overrides.all,
  fetchCrateAlternativeRegistry ? _: throw "fetchCrateAlternativeRegistry is required, but not specified in makePackageSet",
  release ? null,
  rootFeatures ? null,
  hostPlatformCpu ? null,
  hostPlatformFeatures ? [],
  target,
  codegenOpts ? null,
  profileOpts ? null,
  rustcLinkFlags ? [],
  rustcBuildFlags ? [],
}:
lib.fix' (self:
  let
    rustPackages = self;
    buildRustPackages' = if buildRustPackages == null then self else buildRustPackages;
    mkScope = scope:
      let
        prevStage = pkgs.__splicedPackages;
        scopeSpliced = rustLib.splicePackages (buildRustPackages != null) {
          pkgsBuildBuild = scope.buildRustPackages.buildRustPackages;
          pkgsBuildHost = scope.buildRustPackages;
          pkgsBuildTarget = {};
          pkgsHostHost = {};
          pkgsHostTarget = scope;
          pkgsTargetTarget = {};
        } // {
          inherit (scope) pkgs buildRustPackages rustToolchain config __splicedPackages;
        };
      in
        prevStage // prevStage.xorg // prevStage.gnome2 // { inherit stdenv; } // scopeSpliced;
    defaultScope = mkScope self;
    callPackage = lib.callPackageWith defaultScope;

    mkRustCrate' = lib.makeOverridable (callPackage mkRustCrate { inherit rustLib; });
    combinedOverride = builtins.foldl' rustLib.combineOverrides rustLib.nullOverride packageOverrides;
    packageFunWith = { mkRustCrate, buildRustPackages }: lib.fix (rustPackages: packageFun {
      inherit rustPackages buildRustPackages lib workspaceSrc target profileOpts codegenOpts rustcLinkFlags rustcBuildFlags;
      inherit (stdenv) hostPlatform;
      mkRustCrate = rustLib.runOverride combinedOverride mkRustCrate;
      rustLib = rustLib // {
        inherit fetchCrateAlternativeRegistry;
        fetchCrateLocal = { name, version, workspaceSrc, path }:
          let
            rustPlatform = pkgs.makeRustPlatform {
              cargo = rustToolchain;
              rustc = rustToolchain;
            };
          in rustPlatform.buildRustPackage {
              src = workspaceSrc;
              name = "source-${name}-${version}";
              cargoLock = {
                lockFile = "${workspaceSrc}/Cargo.lock";
                allowBuiltinFetchGit = true;
              };
              doCheck = false;
              nativeBuildInputs = [ pkgs.jq pkgs.remarshal ];
              buildPhase = ''
                set -euo pipefail
                pushd ${path}
                cargo metadata --format-version 1 | jq '.resolve.root as $root | .packages[] | select(.id == $root)' \
                  | jq '{package: {name: .name, authors: .authors, categories: .categories, description: .description, documentation: .documentation, edition: .edition, exclude: .exclude, homepage: .homepage, include: .include, keywords: .keywords, license: .license, publish: .publish, readme: .readme, repository: .repository, version: .version,}}' \
                  | jq 'del(..|nulls)' \
                  > Cargo.metadata.json
                mv Cargo.toml Cargo.original.toml
                # Remarshal was failing on table names of the form:
                # [key."cfg(foo = \"a\", bar = \"b\"))".path]
                # The regex to find or deconstruct these strings must find, in order,
                # these components: open bracket, open quote, open escaped quote, and
                # their closing pairs.  Because each quoted path can contain multiple
                # quote escape pairs, a loop is employed to match the first quote escape,
                # which the sed will replace with a single quote equivalent until all
                # escaped quote pairs are replaced.  The grep regex is identical to the
                # sed regex but does not destructure the match into groups for
                # restructuring in the replacement.
                while grep '\[[^"]*"[^\\"]*\\"[^\\"]*\\"[^"]*[^]]*\]' Cargo.original.toml; do
                  sed -i -r 's/\[([^"]*)"([^\\"]*)\\"([^\\"]*)\\"([^"]*)"([^]]*)\]/[\1"\2'"'"'\3'"'"'\4"\5]/g' Cargo.original.toml
                done;
                remarshal -if toml -of json Cargo.original.toml \
                  | jq "{ package: .package
                        , lib: .lib
                        , bin: .bin
                        , test: .test
                        , example: .example
                        , bench: .bench
                        } | with_entries(select( .value != null ))
                        " \
                  | jq "del(.[][] | nulls)" > Cargo.t.json
                jq -s ".[0] * .[1]" Cargo.t.json Cargo.metadata.json | jq "del(.[][] | nulls)" > Cargo.json
                cat Cargo.json | remarshal -if json -of toml > Cargo.toml
                popd
              '';
              installPhase = ''
                cp -r ${path} $out
              '';
            };
      };
      ${ if release == null then null else "release" } = release;
      ${ if rootFeatures == null then null else "rootFeatures" } = rootFeatures;
      ${ if hostPlatformCpu == null then null else "hostPlatformCpu" } = hostPlatformCpu;
      ${ if hostPlatformFeatures == [] then null else "hostPlatformFeatures" } = hostPlatformFeatures;
    });

    noBuild = packageFunWith {
      mkRustCrate = lib.makeOverridable mkRustCrateNoBuild { };
      buildRustPackages = buildRustPackages'.noBuild;
    };

  in packageFunWith { mkRustCrate = mkRustCrate'; buildRustPackages = buildRustPackages'; } // {
    inherit rustPackages callPackage pkgs rustToolchain noBuild;
    workspaceShell = workspaceShell { inherit pkgs noBuild rustToolchain; };
    mkRustCrate = mkRustCrate';
    buildRustPackages = buildRustPackages';
    __splicedPackages = defaultScope;
  }
)
