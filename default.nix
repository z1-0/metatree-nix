{ nix-meta, srctree, ... }:

let
  inherit (builtins) elemAt filter foldl' genList length listToAttrs map toString;
  inherit (nix-meta.lib) get parse remove render;
  inherit (srctree.lib) alg toAttrs;

  mapOption = f: tree:
    if tree == null then null else f tree;

  imap0 = f: list: genList (n: f n (elemAt list n)) (length list);

  # Inject extra into file nodes by leaf index, aligned with `alg.leaves`
  # (DFS pre-order, children in original order). The path check on each file
  # fails loudly instead of silently enriching the wrong file.
  zipMeta = extraOf: leaves: tree:
    let
      go = node: n:
        if node.type == "file" then
          let
            extra = assert node.path == (elemAt leaves n).path; extraOf n;
          in
          { node = if extra == null then node else node // extra; n = n + 1; }
        else
          let
            folded = foldl' (acc: child:
              let r = go child acc.n; in
              { children = acc.children ++ [ r.node ]; n = r.n; }
            ) { children = [ ]; n = n; } node.children;
          in
          { node = node // { children = folded.children; }; n = folded.n; };
    in
    (go tree 0).node;

  withMeta = pkgs: tree:
    assert tree != null;
    let
      leaves = alg.leaves tree;
      paths = map (n: n.path) leaves;

      # 1. Parse all files. This produces a single batch derivation.
      asts = parse pkgs paths;

      # 2. Filter ASTs in Nix memory to find those with `_meta`.
      #    `remove` works without pkgs and catches cases like `_meta = null;` that `get` would miss.
      metaASTList = filter (x: x != null) (imap0 (i: ast:
        let
          removed = remove ast;
        in
        if removed != ast then { inherit i ast removed; } else null
      ) asts);

      # 3. Run get and render on the filtered ASTs.
      metasEvaluated = if metaASTList == [] then [] else get pkgs (map (x: x.ast) metaASTList);
      renderedPaths  = if metaASTList == [] then [] else render pkgs (map (x: x.removed) metaASTList);

      # 4. Build rewrite mappings keyed by leaf index (leaves[i] ↔ the metaASTList entry with the same i).
      byIdx = listToAttrs (imap0 (idx: item:
        {
          name = toString item.i;
          value = {
            content = import (elemAt renderedPaths idx);
            meta = elemAt metasEvaluated idx;
          };
        }
      ) metaASTList);
    in
    zipMeta (n: byIdx.${toString n} or null) leaves tree;
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
