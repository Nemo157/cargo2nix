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
        fetchCrateLocal = workspace: path:
          let
            name = (builtins.fromTOML (builtins.readFile "${workspace}/${path}/Cargo.toml")).package.name;
            rustPlatform = pkgs.makeRustPlatform {
              cargo = rustToolchain;
              rustc = rustToolchain;
            };
            package = rustPlatform.buildRustPackage {
              src = workspace;
              name = "${name}.crate.tar.gz";
              cargoLock = {
                lockFile = "${workspace}/Cargo.lock";
                allowBuiltinFetchGit = true;
              };
              doCheck = false;
              buildPhase = ''
                cargo package --manifest-path ${path}/Cargo.toml --no-verify --no-metadata --allow-dirty --locked --offline
              '';
              installPhase = ''
                mv target/package/*.crate $out
              '';
            };
          in stdenv.mkDerivation {
            name = "${name}-source";
            src = package;
            installPhase = ''
              ls -al
              mkdir $out
              mv * $out
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
