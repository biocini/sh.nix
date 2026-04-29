{ shnixLib }:

shnixLib.mkPosixShellModule {
  name = "ksh";
  etcRcPath = "kshrc";
  homeRcPath = ".kshrc";
}
