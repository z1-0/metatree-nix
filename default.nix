{ nix-meta, srctree, ... }:

let
  inherit (builtins) concatStringsSep filter foldl' stringLength substring;
  inherit (nix-meta.lib) get parse remove render;
  inherit (srctree.lib) alg;

  # `remove` catches `_meta = null;` that `get` misses.
  metaChanges = pkgs: tree:
    let
      leaves = alg.leaves tree;
      asts = parse pkgs (map (n: n.path) leaves);
    in
    filter (x: x != null) (pkgs.lib.zipListsWith (leaf: ast:
      let
        removed = remove ast;
      in
      if removed != ast then { path = leaf.path; inherit ast removed; } else null
    ) leaves asts);

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
      leaves = metaChanges pkgs tree;

      metas = pkgs.lib.zipListsWith (leaf: meta: {
        path = leaf.path;
        inherit meta;
      }) leaves (ifNonEmpty (get pkgs) (map (x: x.ast) leaves));

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

      # Reached only when `metas != []`, which implies `leaves != []`, so the
      # zip below gets pairs for every leaf.
      newSrc = rewriteSrc pkgs src
        (pkgs.lib.zipListsWith (leaf: newFile: {
          inherit newFile;
          rel = relPath leaf.path;
        }) leaves newFiles);
    in
    # No `_meta` anywhere: keep the tree untouched.
    if metas == [] then tree
    # All files import from newSrc: relative imports must resolve against the
    # stripped files, or `_meta` leaks through.
    else alg.mapLeaves (node:
      node // { content = import "${newSrc}${relPath node.path}"; } // findMeta node.path metas
    ) tree;
in

srctree.lib // {
  inherit withMeta;

  load = pkgs: src: pkgs.lib.mapNullable (withMeta pkgs) (srctree.lib.load src);
}
