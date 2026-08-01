{ nix-meta, srctree, ... }:

let
  inherit (builtins) concatStringsSep elemAt filter foldl' genList length listToAttrs map stringLength substring toString;
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

      # 4. Directory-preserving copy. Rendered files are written back at their
      #    original relative paths so that relative imports (e.g. `import ./helper.nix`)
      #    resolve against the source tree instead of the flat render directory.
      #    The tree root path is the source directory and every leaf path is
      #    `src + "/" + <relative path>` (srctree guarantees this shape).
      src     = tree.path;
      relPath = leaf:
        let
          s = toString src;
          p = toString leaf.path;
        in
        assert substring 0 (stringLength s + 1) p == s + "/";
        substring (stringLength s) (stringLength p - stringLength s) p;
      # Aligned with metaASTList: each entry's relative path, computed once.
      relPaths = map (item: relPath (elemAt leaves item.i)) metaASTList;
      # Follow symlinks (`-L`) so rendered files overwrite real files, not the
      # tree the symlink points at. srctree admits symlink nodes (dir + file).
      srcCopy = if metaASTList == [] then null else pkgs.runCommand "metatree-src" { } ''
        cp -Lr "${src}/." $out/
        chmod -R u+w $out/
        ${concatStringsSep "\n" (imap0 (idx: _:
          "cp -f \"${elemAt renderedPaths idx}\" \"$out${elemAt relPaths idx}\"") metaASTList)}
      '';

      # 5. Build rewrite mappings keyed by leaf index (leaves[i] ↔ the metaASTList entry with the same i).
      byIdx = listToAttrs (imap0 (idx: item:
        {
          name = toString item.i;
          value = {
            content = import "${srcCopy}${elemAt relPaths idx}";
            meta = elemAt metasEvaluated idx;
          };
        }
      ) metaASTList);
    in
    # Every leaf imports from srcCopy so that relative imports inside a module
    # resolve against the copy, where _meta files are the stripped renders.
    # Without this, a `_meta`-free module importing a `_meta` module gets the
    # original (unstripped) file and leaks `_meta` into its evaluated value.
    zipMeta (n:
      let entry = byIdx.${toString n} or null; in
      if srcCopy == null then null
      else if entry != null then entry
      else { content = import "${srcCopy}${relPath (elemAt leaves n)}"; }
    ) leaves tree;
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
