{ callPackage, fetchFromGitHub }:

callPackage ./generic.nix {
  version = "unstable-2026-10-15";

  src = fetchFromGitHub {
    owner = "ksh93";
    repo = "ksh";
    rev = "ed70ab83e185668a01f3b67f326a3120a9524bc2";
    hash = "sha256-eH0tQMJ1ZdA5h6uSg6dV0Ui57HxK9Sp0Fm5xwXCUgaY=";
  };

  description = "KornShell Command And Programming Language (nightly dev build)";
  longDescription = ''
    The KornShell language was designed and developed by David G. Korn at
    AT&T Bell Laboratories. This is a nightly build from the upstream dev
    branch of the ksh93u+m fork.
  '';
}
