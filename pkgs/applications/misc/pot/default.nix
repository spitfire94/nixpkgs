{ lib
, stdenv
, stdenvNoCC
, rustPlatform
, fetchFromGitHub
, wrapGAppsHook
, cargo
, rustc
, cargo-tauri
, pkg-config
, nodePackages
, esbuild
, buildGoModule
, jq
, moreutils
, libayatana-appindicator
, gtk3
, webkitgtk
, libsoup
, openssl
, xdotool
}:

stdenv.mkDerivation rec {
  pname = "pot";
  version = "2.6.2";

  src = fetchFromGitHub {
    owner = "pot-app";
    repo = "pot-desktop";
    rev = version;
    hash = "sha256-0NnZe1o8HsB1GR6wp8Da/CTLhcve/sGIumD2qb9DC3s=";
  };

  sourceRoot = "${src.name}/src-tauri";

  postPatch = ''
    substituteInPlace $cargoDepsCopy/libappindicator-sys-*/src/lib.rs \
      --replace "libayatana-appindicator3.so.1" "${libayatana-appindicator}/lib/libayatana-appindicator3.so.1"
  '';

  pnpm-deps = stdenvNoCC.mkDerivation {
    pname = "${pname}-pnpm-deps";
    inherit src version;

    nativeBuildInputs = [
      jq
      moreutils
      nodePackages.pnpm
    ];

    installPhase = ''
      export HOME=$(mktemp -d)
      pnpm config set store-dir $out
      # use --ignore-script and --no-optional to avoid downloading binaries
      # use --frozen-lockfile to avoid checking git deps
      pnpm install --frozen-lockfile --no-optional --ignore-script

      # Remove timestamp and sort the json files
      rm -rf $out/v3/tmp
      for f in $(find $out -name "*.json"); do
        sed -i -E -e 's/"checkedAt":[0-9]+,//g' $f
        jq --sort-keys . $f | sponge $f
      done
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = "sha256-m83cDKtFfwA3Xv8EqXNyF37ss+8qFDdFhu/1X1g7n/0=";
  };

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
    outputHashes = {
      # All other crates in the same workspace reuse this hash.
      "tauri-plugin-autostart-0.0.0" = "sha256-hvR9tUp7yFhSP2bqE0mGwT8NHL7fGOYQ3Gz2wYi0bXI=";
    };
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    cargo-tauri
    wrapGAppsHook
    nodePackages.pnpm
    pkg-config
  ];

  buildInputs = [
    gtk3
    libsoup
    libayatana-appindicator
    openssl
    webkitgtk
    xdotool
  ];

  ESBUILD_BINARY_PATH = "${lib.getExe (esbuild.override {
    buildGoModule = args: buildGoModule (args // rec {
      version = "0.18.20";
      src = fetchFromGitHub {
        owner = "evanw";
        repo = "esbuild";
        rev = "v${version}";
        hash = "sha256-mED3h+mY+4H465m02ewFK/BgA1i/PQ+ksUNxBlgpUoI=";
      };
      vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
    });
  })}";

  preBuild = ''
    export HOME=$(mktemp -d)
    pnpm config set store-dir ${pnpm-deps}
    chmod +w ..
    pnpm install --offline --frozen-lockfile --no-optional --ignore-script
    chmod -R +w ../node_modules
    pnpm rebuild
    # Use cargo-tauri from nixpkgs instead of pnpm tauri from npm
    cargo tauri build -b deb
  '';

  preInstall = ''
    mv target/release/bundle/deb/*/data/usr/ $out
  '';

  meta = with lib; {
    description = "A cross-platform translation software";
    homepage = "https://pot.pylogmon.com";
    platforms = platforms.linux;
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ linsui ];
  };
}

