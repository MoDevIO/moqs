{
  lib,
  runCommand,
  python3,
  hunspellDicts,
}:

let
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../shell.qml
      ../greeter.qml
      ../assets
      ../config
      ../modules
      ../services
    ];
  };

  # Common German words for the vocabulary's sound-alike keywords (nix/german-words.py).
  germanWords =
    runCommand "moqs-german-words"
      {
        nativeBuildInputs = [ (python3.withPackages (p: [ p.wordfreq ])) ];
      }
      ''
        python3 ${./german-words.py} ${hunspellDicts.de_DE}/share/hunspell/de_DE.dic $out
      '';
in
runCommand "moqs" { passthru = { inherit germanWords; }; } ''
  cp -r ${src} $out
  chmod u+w $out
  cp ${germanWords} $out/german-words.txt
''
