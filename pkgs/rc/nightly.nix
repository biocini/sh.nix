{ fetchFromGitHub }:

{
  version = "unstable-2026-04-24";

  src = fetchFromGitHub {
    owner = "rakitzis";
    repo = "rc";
    rev = "418fa950edc3584d7be01c8cb982c39c933bee93";
    hash = "sha256-1O3OxapXlAmfOX266U2RyjqvRvHU8Sn0JJvKy8wZVDU=";
  };
}
