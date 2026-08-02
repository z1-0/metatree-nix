{ nix-meta, srctree, ... }:

let
  inherit (builtins) concatStringsSep elemAt filter foldl' stringLength substring;
  inherit (nix-meta.lib) get parse remove render;
  inherit (srctree.lib) alg toAttrs;

  mapOption = f: tree: if tree == null then null else f tree;

  # `remove` catches `_meta = null;` that `get` misses.
  metaLeaves = pkgs: tree:
    let
      leaves = alg.leaves tree;
      asts = parse pkgs (map (n: n.path) leaves);
    in
    filter (x: x != null) (pkgs.lib.imap0 (i: ast:
      let
        removed = remove ast;
      in
      if removed != ast then { path = (elemAt leaves i).path; inherit ast removed; } else null
    ) asts);

  # parse/render error on [].
  ifNonEmpty = f: xs: if xs == [] then [] else f xs;

  # `-L` follows symlinks.
  rewriteSrc = pkgs: src: pairs:
    pkgs.runCommand "metatree-rewrite-src" { } ''
      cp -Lr "${src}/." $out/
      chmod -R u+w $out/
      ${concatStringsSep "\n" (map (p: "cp -f \"${p.newFile}\" \"$out${p.rel}\"") pairs)}
    '';

  # `==` ignores string context (which Nix forbids in attrset keys).
  findMeta = path: metas: foldl' (acc: m: if m.path == path then m else acc) { } metas;

  withMeta = pkgs: tree:
    assert tree != null;
    let
      # IFD boundary: all derivation-driven work happens here; the rest is
      # a pure rewrite over the produced artifacts.
      leaves = metaLeaves pkgs tree;

      metas = pkgs.lib.imap0 (idx: m: {
        path = (elemAt leaves idx).path;
        meta = m;
      }) (ifNonEmpty (get pkgs) (map (x: x.ast) leaves));

      newFiles = ifNonEmpty (render pkgs) (map (x: x.removed) leaves);

      src = tree.path;

      # srctree guarantees every leaf path is `src + "/" + <relative path>`.
      relPath = path:
        let
          s = toString src;
          p = toString path;
        in
        assert substring 0 (stringLength s + 1) p == s + "/";
        substring (stringLength s) (stringLength p - stringLength s) p;

      newSrc = if leaves == [] then null else rewriteSrc pkgs src
        (pkgs.lib.imap0 (idx: m: {
          newFile = elemAt newFiles idx;
          rel = relPath (elemAt leaves idx).path;
        }) leaves);
    in
    # No `_meta` anywhere: keep the tree untouched.
    if metas == [] then tree
    # All files import from newSrc: relative imports must resolve against the
    # stripped files, or `_meta` leaks through.
    else alg.map (node:
      if node.type != "file" then node
      else node // { content = import "${newSrc}${relPath node.path}"; } // findMeta node.path metas
    ) tree;
in

srctree.lib // {
  inherit withMeta;

  load = pkgs: src: mapOption (withMeta pkgs) (srctree.lib.load src);

  loadHaumea = pkgs: args:
    let
      tree = mapOption (withMeta pkgs) (srctree.lib.loadHaumea args).tree;
    in
    { inherit tree; attrs = mapOption toAttrs tree; };
}
