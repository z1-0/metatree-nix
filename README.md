# metatree-nix

Add AST-extracted metadata from `.nix` module files to a [srctree](https://github.com/z1-0/srctree-nix) filesystem tree using [nix-meta](https://github.com/z1-0/nix-meta).

Embed metadata (descriptions, author info, version numbers) in your Nix modules without affecting the evaluated configuration. metatree-nix strips `_meta` before evaluation.

## How it works

1. `nix-meta` parses `.nix` files at the AST level and extracts the top-level `_meta` attribute set.
2. `nix-meta` removes `_meta` from each AST and renders the modified AST to temporary files.
3. `srctree` evaluates the stripped files.
4. metatree-nix merges the evaluated content and the extracted metadata into the final tree.

> [!NOTE]
> Because stripping happens before evaluation, modules never see `_meta`. Strict modules then evaluate without type errors or warnings.

## Installation

Add `metatree-nix` to your `flake.nix` inputs:

```nix
{
  inputs.metatree.url = "github:z1-0/metatree-nix";

  outputs = { metatree, ... }: {
    lib = metatree.lib;
  };
}
```

## Usage

### 1. Declare metadata

Add a top-level `_meta` attribute set to your module files:

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
  workers = 4;
}
```

### 2. Load the metatree

```nix
let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  metatree = metatree.lib.load pkgs ./src;
in
  metatree
```

### 3. Tree vs attributes

- `load` returns the enriched tree structure directly.
- `loadHaumea` returns `{ tree, attrs }` for haumea-style access.

#### File node

```nix
{
  name = "web";
  path = "/abs/path/to/src/services/web.nix";
  type = "file";
  content = {
    port = 8080;
    host = "0.0.0.0";
    workers = 4;
  };
  meta = {
    description = "Web server service module";
    author = "team-infra";
    version = 1;
  };
}
```

> [!TIP]
> Use `loadHaumea` when you need both tree and attrs. Use `load` for direct tree access.

## API

### load

```
load :: pkgs -> src -> tree
```

Load a directory with `srctree`, extract `_meta` from Nix files, strip it, evaluate, and return the enriched tree.

- `pkgs`: package set for running the parser/renderer utilities.
- `src`: source directory to load.

### loadHaumea

```
loadHaumea :: pkgs -> args -> { tree, attrs }
```

Load with a haumea-style return, giving you the tree and clean attrs.

- `pkgs`: package set for running the parser/renderer utilities.
- `args`: arguments forwarded to `srctree.lib.loadHaumea`.

### withMeta

```
withMeta :: pkgs -> tree -> tree
```

Enrich an already loaded `srctree` tree with AST-extracted `_meta` attributes.

- `pkgs`: package set for running the parser/renderer utilities.
- `tree`: srctree tree structure to enrich.
