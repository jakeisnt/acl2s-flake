
{
  pkgs ? import <nixpkgs> {},
  system ? builtins.currentSystem,
  acl2-source ? (pkgs.fetchFromGitHub {
    owner = "acl2";
    repo = "acl2";
    rev = "master";
    sha256 = "0yg7kfj0xnmz5v9dx1g1f8sbc9xmmyciq4qhv4jkqijz91i00vig";
  }),
  certifyBooks ? true,
}: let
  inherit (pkgs) lib;

# inspiration: https://github.com/mitchellh/zig-overlay/blob/main/default.nix

# { lib, stdenv, callPackage, fetchFromGitHub, runCommandLocal, makeWrapper, substituteAll
# , sbcl, bash, which, perl, nettools
# , openssl, glucose, minisat, abc-verifier, z3, python, acl2
# , certifyBooks ? true
# } @ args:

  # Disable immobile space so we don't run out of memory on large books, and
  # supply 2GB of dynamic space to avoid exhausting the heap while building the
  # ACL2 system itself; see
  # https://www.cs.utexas.edu/users/moore/acl2/current/HTML/installation/requirements.html#Obtaining-SBCL
  sbcl' = pkgs.sbcl.override { disableImmobileSpace = true; };
  sbcl = pkgs.runCommandLocal pkgs.sbcl.name { buildInputs = [ pkgs.makeWrapper ]; } ''
    makeWrapper ${sbcl'}/bin/sbcl $out/bin/sbcl \
      --add-flags "--dynamic-space-size 2000"
  '';

in pkgs.stdenv.mkDerivation rec {
  pname = "acl2";
  version = "8.4";

  src = acl2-source;
  # You can swap this out with any other IPASIR implementation at
  # build time by using overrideAttrs (make sure the derivation you
  # use has a "libname" attribute so we can plug it into the patch
  # below).  Or, you can override it at runtime by setting the
  # $IPASIR_SHARED_LIBRARY environment variable.
  libipasir = pkgs.callPackage ./libipasirglucose4 { };

  # patches = [(substituteAll {
  #   src = ./0001-Fix-some-paths-for-Nix-build.patch;
  #   libipasir = "${libipasir}/lib/${libipasir.libname}";
  #   openssl = openssl.out;
  # })];

  buildInputs = [
    # ACL2 itself only needs a Common Lisp compiler/interpreter:
    sbcl
  ] ++ lib.optionals certifyBooks (with pkgs; [
    # To build community books, we need Perl and a couple of utilities:
    which perl nettools makeWrapper
    # Some of the books require one or more of these external tools:
    openssl.out glucose minisat abc-verifier libipasir
    z3 (python.withPackages (ps: [ ps.z3 ]))
  ]);

  # NOTE: Parallel building can be memory-intensive depending on the number of
  # concurrent jobs.  For example, this build has been seen to use >120GB of
  # RAM on an 85 core machine.
  enableParallelBuilding = true;

  preConfigure = ''
    # When certifying books, ACL2 doesn't like $HOME not existing.
    export HOME=$(pwd)/fake-home
  '' + lib.optionalString certifyBooks ''
    # Some books also care about $USER being nonempty.
    export USER=nobody
  '';

  postConfigure = ''
    # ACL2 and its books need to be built in place in the out directory because
    # the proof artifacts are not relocatable. Since ACL2 mostly expects
    # everything to exist in the original source tree layout, we put it in
    # $out/share/${pname} and create symlinks in $out/bin as necessary.
    mkdir -p $out/share/${pname}
    cp -pR . $out/share/${pname}
    cd $out/share/${pname}
  '';

  preBuild = "mkdir -p $HOME";
  makeFlags = "LISP=${sbcl}/bin/sbcl ACL2_MAKE_LOG=NONE";

  doCheck = true;
  checkTarget = "mini-proveall";

  installPhase = ''
    mkdir -p $out/bin
    ln -s $out/share/${pname}/saved_acl2           $out/bin/${pname}
  '' + lib.optionalString certifyBooks ''
    ln -s $out/share/${pname}/books/build/cert.pl  $out/bin/${pname}-cert
    ln -s $out/share/${pname}/books/build/clean.pl $out/bin/${pname}-clean
  '';

  preDistPhases = [ (if false then "certifyBooksPhase" else "removeBooksPhase") ];

  certifyBooksPhase = ''
    # Certify the community books
    pushd $out/share/${pname}/books
    makeFlags="ACL2=$out/share/${pname}/saved_acl2"
    buildFlags="all"
    buildPhase
    # Clean up some stuff to save space
    find -name '*@useless-runes.lsp' -execdir rm {} +  # saves ~1GB of space
    find -name '*.cert.out' -execdir gzip {} +         # saves ~400MB of space
    popd
  '';

  removeBooksPhase = ''
    # Delete the community books
    rm -rf $out/share/${pname}/books
  '';

  meta = with lib; {
    description = "An interpreter and a prover for a Lisp dialect";
    longDescription = ''
      ACL2 is a logic and programming language in which you can model computer
      systems, together with a tool to help you prove properties of those
      models. "ACL2" denotes "A Computational Logic for Applicative Common
      Lisp".
      ACL2 is part of the Boyer-Moore family of provers, for which its authors
      have received the 2005 ACM Software System Award.
      This package installs the main ACL2 executable ${pname}, as well as the
      build tools cert.pl and clean.pl, renamed to ${pname}-cert and
      ${pname}-clean.
    '' + (if certifyBooks then ''
      The community books are also included and certified with the `make
      everything` target.
    '' else ''
      The community books are not included in this package.
    '');
    homepage = "https://www.cs.utexas.edu/users/moore/acl2/";
    downloadPage = "https://github.com/acl2-devel/acl2-devel/releases";
    license = with licenses; [
      # ACL2 itself is bsd3
      bsd3
    ] ++ optionals certifyBooks [
      # The community books are mostly bsd3 or mit but with a few
      # other things thrown in.
      mit gpl2 llgpl21 cc0 publicDomain # unfreeRedistributable: omitted for the sake of an easy install
    ];
    maintainers = with maintainers; [ jakeisnt ];
    platforms = platforms.all;
  };
}
