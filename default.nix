{ nix-meta, srctree, ... }:

let
  inherit (builtins) concatLists elemAt genList length listToAttrs unsafeDiscardStringContext;
  inherit (nix-meta.lib) get parse remove render;
  inherit (srctree.lib) alg toAttrs;

  mapOption = f: tree:
    if tree == null then null else f tree;

  withMeta = pkgs: tree:
    assert tree != null;
    let
      paths = map (n: n.path) (alg.leaves tree);
      pathsCount = length paths;

      # 1. Parse all files. This produces a single batch derivation.
      asts = parse pkgs paths;

      # 2. Filter ASTs in Nix memory to find those with `_meta`.
      #    `remove` works without pkgs and catches cases like `_meta = null;` that `get` would miss.
      metaASTList = concatLists (genList (i:
        let
          ast = elemAt asts i;
          removed = remove ast;
        in
        if removed != ast then
          [ { inherit i ast removed; path = elemAt paths i; } ]
        else
          [ ]
      ) pathsCount);

      # 3. Run get and render on the filtered ASTs.
      metasEvaluated = if metaASTList == [] then [] else get pkgs (map (x: x.ast) metaASTList);
      renderedPaths  = if metaASTList == [] then [] else render pkgs (map (x: x.removed) metaASTList);

      # 4. Build rewrite mappings for files with `_meta`.
      enrich = listToAttrs (genList (idx:
        let
          item = elemAt metaASTList idx;
        in
        {
          name = unsafeDiscardStringContext (toString item.path);
          value = {
            content = import (elemAt renderedPaths idx);
            meta = elemAt metasEvaluated idx;
          };
        }
      ) (length metaASTList));

      newTree = alg.map (node:
        if node.type == "file" then
          let
            extra = enrich.${unsafeDiscardStringContext (toString node.path)} or null;
          in
          if extra != null then node // extra else node
        else
          node
      ) tree;
    in
    newTree;
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
