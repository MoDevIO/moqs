{ lib, runCommand }:

let
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../shell.qml
      ../config
      ../modules
      ../services
    ];
  };
in
runCommand "moqs" { } ''
  cp -r ${src} $out
''
