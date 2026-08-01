{ nix-meta, srctree, ... }:

let
  inherit (builtins) concatStringsSep elemAt filter foldl' genList length stringLength substring;
  inherit (nix-meta.lib) get parse remove render;
  inherit (srctree.lib) alg toAttrs;

  mapOption = f: tree:
    if tree == null then null else f tree;

  imap0 = f: list: genList (n: f n (elemAt list n)) (length list);

  # Directory-preserving copy of the source tree with the rendered files
  # written back at their original relative paths (`-L` follows symlinks).
  copyRendered = pkgs: src: pairs:
    pkgs.runCommand "metatree-src" { } ''
      cp -Lr "${src}/." $out/
      chmod -R u+w $out/
      ${concatStringsSep "\n" (map (p: "cp -f \"${p.rendered}\" \"$out${p.rel}\"") pairs)}
    '';

  # IFD boundary: all derivation-driven work happens here; `withMeta` stays a
  # pure rewrite over the produced artifacts.
  parseAndRender = pkgs: tree:
    let
      leaves = alg.leaves tree;
      paths = map (n: n.path) leaves;

      # Parse all files (single batch derivation).
      asts = parse pkgs paths;

      # Keep ASTs with `_meta` (`remove` catches `_meta = null;` that `get` misses).
      metaASTList = filter (x: x != null) (imap0 (i: ast:
        let
          removed = remove ast;
        in
        if removed != ast then { inherit i ast removed; } else null
      ) asts);

      # Run get and render on the filtered ASTs.
      metasEvaluated = if metaASTList == [] then [] else get pkgs (map (x: x.ast) metaASTList);
      renderedPaths  = if metaASTList == [] then [] else render pkgs (map (x: x.removed) metaASTList);

      # Every leaf path is `src + "/" + <relative path>` (srctree guarantees this).
      src     = tree.path;
      relPath = leaf:
        let
          s = toString src;
          p = toString leaf.path;
        in
        assert substring 0 (stringLength s + 1) p == s + "/";
        substring (stringLength s) (stringLength p - stringLength s) p;
      srcCopy = if metaASTList == [] then null else copyRendered pkgs src (imap0 (idx: item: {
        rendered = elemAt renderedPaths idx;
        rel = relPath (elemAt leaves item.i);
      }) metaASTList);

      # Metas bound to their paths; `==` ignores string context (which Nix
      # forbids in attrset keys).
      metas = imap0 (idx: item: {
        path = (elemAt leaves item.i).path;
        meta = elemAt metasEvaluated idx;
      }) metaASTList;
    in
    { inherit metas relPath srcCopy; };

  withMeta = pkgs: tree:
    assert tree != null;
    let
      ifd = parseAndRender pkgs tree;
    in
    # All files import from srcCopy so relative imports resolve against the
    # stripped renders — otherwise `_meta` leaks through imports.
    alg.map (node:
      if node.type != "file" then node
      else if ifd.srcCopy == null then node
      else
        node // { content = import "${ifd.srcCopy}${ifd.relPath node}"; }
           // (foldl' (acc: m: if m.path == node.path then m else acc) { } ifd.metas)
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
