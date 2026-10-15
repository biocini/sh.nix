# Shared build for ksh93u+m. stable.nix and nightly.nix supply the
# version, source and description.
{
  lib,
  stdenv,
  which,
  libiconv,
  version,
  src,
  description,
  longDescription,
}:

stdenv.mkDerivation {
  pname = "ksh";
  inherit version src;

  nativeBuildInputs = [ which ];

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

  # The build links the shared libraries by bare install name; point the
  # binaries at the installed copies. install_name_tool ignores a -change
  # whose old name the binary does not reference.
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    for bin in "$out"/bin/ksh "$out"/bin/shcomp; do
      if [ -e "$bin" ]; then
        for dylib in libshell.2 libast.6 libcmd.2 libcmd libdll.2; do
          install_name_tool -change "$dylib.dylib" "$out/lib/$dylib.dylib" "$bin"
        done
      fi
    done
  '';

  enableParallelBuilding = true;

  meta = {
    inherit description longDescription;
    homepage = "https://github.com/ksh93/ksh";
    license = lib.licenses.epl20;
    maintainers = [ ];
    mainProgram = "ksh";
    platforms = lib.platforms.all;
  };

  passthru = {
    shellPath = "/bin/ksh";
  };
}
