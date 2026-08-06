# metatree-nix

**Metadata lifted into the tree.**

This library combines two others:

- [nix-meta](https://github.com/z1-0/nix-meta): parses `.nix` files at the AST level, extracts the top-level `_meta` value, and strips it before evaluation.
- [srctree-nix](https://github.com/z1-0/srctree-nix): loads a directory into a filesystem tree, evaluating each file lazily.

Use `load` to turn a directory into a tree. Every file node carries its evaluated `content` plus the extracted `_meta` as `meta`. Files are re-imported from a copy with `_meta` removed, so the metadata never reaches the evaluator: the module can't see it, imports can't pick it up, and strict modules behave as they always do.

## Quick start

Add `metatree` to your `flake.nix` inputs:

```nix
{
  inputs.metatree.url = "github:z1-0/metatree-nix";

  outputs = { metatree, ... }: {
    lib = metatree.lib;
  };
}
```

### 1. Declare data

Add a top-level `_meta` attribute set to any module file:

```nix
# src/services/web.nix
{
  _meta = {
    description = "Web server service module";
    author = "team-infra";
    version = 1;
  };

  port = 8080;
  host = "0.0.0.0";
}
```

### 2. Load the metatree

```nix
let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  tree = metatree.lib.load pkgs ./src;
in
  tree
```

Each file node exposes its `content` (as evaluated) and its `meta` (as written):

```nix
{
  name = "web";
  path = "/abs/path/to/src/services/web.nix";
  type = "file";
  content = {
    port = 8080;
    host = "0.0.0.0";
  };
  meta = {
    description = "Web server service module";
    author = "team-infra";
    version = 1;
  };
}
```

### 3. Browse it as attributes

Combine `load` with `toAttrs` (exposed through `metatree.lib`) for haumea-style attribute access:

```nix
let
  attrs = metatree.lib.toAttrs (metatree.lib.load pkgs ./src);
in
  attrs.services.web.meta.version
```

> [!TIP]
> Files without `_meta` keep their content and gain no `meta` attribute. `load` returns `null` for a missing directory, so optional trees need no special handling.

## API

### load

```
load :: pkgs -> src -> tree | null
```

Load a directory as a `srctree`, read each file's `_meta` out of the AST, then strip it and evaluate, returning the enriched tree. Returns `null` when `src` doesn't exist.

- `pkgs`: package set for running the parser/renderer utilities.
- `src`: source directory to load.

### withMeta

```
withMeta :: pkgs -> tree -> tree
```

Enrich an already loaded `srctree` tree with AST-extracted `_meta` attributes. Use it when the tree was built by hand or does not go through `load`.

- `pkgs`: package set for running the parser/renderer utilities.
- `tree`: srctree tree structure to enrich.
