{
  lib,
  stdenv,
  fetchFromGitHub,
  which,
  libiconv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "ksh";
  version = "1.0.10";

  src = fetchFromGitHub {
    owner = "ksh93";
    repo = "ksh";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hrXW+PKQ6v0CCKiZ8E3HAEcrt9m4ZO5QfwFT9rCgbxc=";
  };

  nativeBuildInputs = [
    which
  ];

  buildInputs = [ libiconv ];

  strictDeps = true;

  # ksh93u+m uses a custom POSIX sh build system, not meson.
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
    description = "KornShell Command And Programming Language";
    longDescription = ''
      The KornShell language was designed and developed by David G. Korn at
      AT&T Bell Laboratories. It is an interactive command language that
      provides access to the UNIX system and to many other systems, on the
      many different computers and workstations on which it is implemented.
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
