{ nix-meta, srctree, ... }:

let
  inherit (builtins) concatStringsSep elemAt filter foldl' stringLength substring;
  inherit (nix-meta.lib) get parse remove render;
  inherit (srctree.lib) alg toAttrs;

  mapOption = f: tree:
    if tree == null then null else f tree;

  # Leaves whose AST carries a `_meta` (`remove` catches `_meta = null;`
  # that `get` misses), each bound to its leaf and stripped AST.
  metaLeaves = pkgs: tree:
    let
      leaves = alg.leaves tree;
      asts = parse pkgs (map (n: n.path) leaves);
    in
    filter (x: x != null) (pkgs.lib.imap0 (i: ast:
      let
        removed = remove ast;
      in
      if removed != ast then { leaf = elemAt leaves i; inherit ast removed; } else null
    ) asts);

  # Apply f only when the list is non-empty (parse/render error on []).
  ifNonEmpty = f: xs: if xs == [] then [] else f xs;

  # Directory-preserving rewrite of the source tree: rendered (stripped)
  # files written back at their original relative paths (`-L` follows symlinks).
  rewriteSrc = pkgs: src: pairs:
    pkgs.runCommand "metatree-rewrite-src" { } ''
      cp -Lr "${src}/." $out/
      chmod -R u+w $out/
      ${concatStringsSep "\n" (map (p: "cp -f \"${p.newFile}\" \"$out${p.rel}\"") pairs)}
    '';

  withMeta = pkgs: tree:
    assert tree != null;
    let
      # IFD boundary: all derivation-driven work happens here; the rest of
      # `withMeta` stays a pure rewrite over the produced artifacts.
      items = metaLeaves pkgs tree;

      # Index-aligned results of the batch get/render calls.
      metas = pkgs.lib.imap0 (idx: m: {
        path = (elemAt items idx).leaf.path;
        meta = m;
      }) (ifNonEmpty (get pkgs) (map (x: x.ast) items));

      newFiles = ifNonEmpty (render pkgs) (map (x: x.removed) items);

      # Every leaf path is `src + "/" + <relative path>` (srctree guarantees this).
      src = tree.path;

      relPath = leaf:
        let
          s = toString src;
          p = toString leaf.path;
        in
        assert substring 0 (stringLength s + 1) p == s + "/";
        substring (stringLength s) (stringLength p - stringLength s) p;
      
      newSrc = if items == [] then null else rewriteSrc pkgs src
        (pkgs.lib.imap0 (idx: m: {
          newFile = elemAt newFiles idx;
          rel = relPath m.leaf;
        }) items);
    in
    # No `_meta` anywhere: keep the tree untouched (skips the copy).
    if metas == [] then tree
    # All files import from newSrc so relative imports resolve against the
    # stripped renders — otherwise `_meta` leaks through imports.
    else alg.map (node:
      if node.type != "file" then node
      else
        node // { content = import "${newSrc}${relPath node}"; }
           // (foldl' (acc: m: if m.path == node.path then m else acc) { } metas)
    ) tree;
in

srctree.lib // {
  inherit withMeta;

  load = pkgs: src:
    mapOption (withMeta pkgs) (srctree.lib.load src);

  loadHaumea = pkgs: args:
    let
      tree = mapOption (withMeta pkgs) (srctree.lib.loadHaumea args).tree;
    in
    { inherit tree; attrs = mapOption toAttrs tree; };
}
