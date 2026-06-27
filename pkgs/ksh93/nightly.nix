{
  lib,
  stdenv,
  fetchFromGitHub,
  which,
  libiconv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ksh";
  version = "unstable-2026-06-23";

  src = fetchFromGitHub {
    owner = "ksh93";
    repo = "ksh";
    rev = "b3fa3ffb40ecc000fbe8375dd54783cf08f0d16c";
    hash = "sha256-I2yFgbgWnvPvglUZD3URlVpeQRCW7mXSarFb1DaeFCY=";
  };

  nativeBuildInputs = [
    which
  ];

  buildInputs = [ libiconv ];

  strictDeps = true;

  buildPhase = ''
    runHook preBuild
    sh bin/package make
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    sh bin/package install "$out"
    runHook postInstall
  '';

  postFixup = ''
    for bin in "$out"/bin/ksh "$out"/bin/shcomp; do
      if [ -e "$bin" ]; then
        install_name_tool -change libshell.2.dylib "$out/lib/libshell.2.dylib" "$bin" || true
        install_name_tool -change libast.6.dylib "$out/lib/libast.6.dylib" "$bin" || true
        install_name_tool -change libcmd.2.dylib "$out/lib/libcmd.2.dylib" "$bin" || true
        install_name_tool -change libcmd.dylib "$out/lib/libcmd.dylib" "$bin" || true
        install_name_tool -change libdll.2.dylib "$out/lib/libdll.2.dylib" "$bin" || true
      fi
    done
  '';

  enableParallelBuilding = true;

  meta = {
    description = "KornShell Command And Programming Language (nightly dev build)";
    longDescription = ''
      The KornShell language was designed and developed by David G. Korn at
      AT&T Bell Laboratories. This is a nightly build from the upstream dev
      branch of the ksh93u+m fork.
    '';
    homepage = "https://github.com/ksh93/ksh";
    license = lib.licenses.epl20;
    maintainers = [ ];
    mainProgram = "ksh";
    platforms = lib.platforms.all;
  };

  passthru = {
    shellPath = "/bin/ksh";
  };
})
