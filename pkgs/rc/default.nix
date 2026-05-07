{
  lib,
  stdenv,
  fetchFromGitHub,
  byacc,
  ed,
  ncurses,
  readline,
  installShellFiles,
  historySupport ? true,
  readlineSupport ? true,
  lineEditingLibrary ?
    if (stdenv.hostPlatform.isDarwin || stdenv.hostPlatform.isStatic) then "null" else "readline",
}:

assert lib.elem lineEditingLibrary [
  "null"
  "edit"
  "editline"
  "readline"
  "vrl"
];
assert
  !(lib.elem lineEditingLibrary [
    "edit"
    "editline"
    "vrl"
  ]); # broken
assert (lineEditingLibrary == "readline") -> readlineSupport;

let
  nightly = import ./nightly.nix { inherit fetchFromGitHub; };
in

stdenv.mkDerivation (finalAttrs: {
  pname = "rc";
  inherit (nightly) version src;

  outputs = [
    "out"
    "man"
  ];

  patches = [
    ./nixos-rcrc.patch
  ];

  postPatch = ''
    ed -v -s Makefile << EOS
    /version.h:/ s| .git/index||
    /v=/ c
    ${"\t"}v=${builtins.substring 0 7 finalAttrs.src.rev}
    .
    /\.git\/index:/ d
    w
    q
    EOS
  '';

  nativeBuildInputs = [
    byacc
    ed
  ]
  ++ lib.optionals historySupport [
    installShellFiles
  ];

  buildInputs = [
    ncurses
  ]
  ++ lib.optionals readlineSupport [
    readline
  ];

  makeFlags = [
    "CC=${stdenv.cc.targetPrefix}cc"
    "PREFIX=${placeholder "out"}"
    "MANPREFIX=${placeholder "man"}/share/man"
    "CPPFLAGS=\"-DSIGCLD=SIGCHLD\""
    "EDIT=${lineEditingLibrary}"
  ];

  buildFlags = [ "all" ] ++ lib.optionals historySupport [ "history" ];

  installTargets = [ "install" ];

  passthru = {
    shellPath = "/bin/rc";
  };

  meta = {
    description = "rc shell — Plan 9 re-implementation for Unix";
    homepage = "https://github.com/rakitzis/rc";
    license = lib.licenses.zlib;
    maintainers = [ ];
    platforms = lib.platforms.unix;
  };
})
