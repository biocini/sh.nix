{ callPackage, fetchFromGitHub }:

let
  version = "1.0.10";
in
callPackage ./generic.nix {
  inherit version;

  src = fetchFromGitHub {
    owner = "ksh93";
    repo = "ksh";
    tag = "v${version}";
    hash = "sha256-hrXW+PKQ6v0CCKiZ8E3HAEcrt9m4ZO5QfwFT9rCgbxc=";
  };

  description = "KornShell Command And Programming Language";
  longDescription = ''
    The KornShell language was designed and developed by David G. Korn at
    AT&T Bell Laboratories. It is an interactive command language that
    provides access to the UNIX system and to many other systems, on the
    many different computers and workstations on which it is implemented.
  '';
}
