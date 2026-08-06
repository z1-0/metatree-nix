# Unit tests for metatree-nix: one `_meta` behaviour per fixture, checked
# through the real parse/render pipeline (IFD).
#
#   - `_meta` extracted onto `meta`, stripped from `content`
#   - files without `_meta` pass through, no `meta` attribute added
#   - `_meta = null` still strips the binding and yields `meta = null`
#   - nested `_meta` stays untouched
#   - `withMeta` handles a hand-built srctree tree
#   - missing and non-directory paths handled
#
# Returns the failing tests (empty when everything passes); the test flake
# feeds this to `pkgs.lib.debug.throwTestFailures`.
{ lib, pkgs }:

let
  inherit (builtins) elemAt;

  check = name: expected: result:
    if expected == result then [ ] else [ { inherit name expected result; } ];

  expectFailure = name: expr:
    if (builtins.tryEval expr).success then
      [
        {
          inherit name;
          expected = "evaluation failure";
          result = "evaluated successfully";
        }
      ]
    else
      [ ];

  # --- fixtures ---
  basic = lib.load pkgs ./fixtures/basic;
  server = lib.alg.find (n: n.name == "server") basic;
  plain = lib.alg.find (n: n.name == "plain") basic;
  nullmeta = lib.alg.find (n: n.name == "nullmeta") basic;
  nested = lib.alg.find (n: n.name == "nested") basic;

  bare = lib.load pkgs ./fixtures/no-meta;
  bareOnly = lib.alg.find (n: n.name == "only") bare;

  # Hand-built srctree tree so `withMeta` can be tested on its own.
  manual = {
    name = "basic";
    path = ./fixtures/basic;
    type = "dir";
    children = [
      {
        name = "server";
        path = ./fixtures/basic/server.nix;
        type = "file";
        content = { };
      }
      {
        name = "plain";
        path = ./fixtures/basic/plain.nix;
        type = "file";
        content = { };
      }
    ];
  };
  enriched = lib.withMeta pkgs manual;
  enrichedServer = elemAt enriched.children 0;
  enrichedPlain = elemAt enriched.children 1;
in
  (check "load: root node is a dir" "dir" basic.type)
  ++ (check "load: root name comes from the directory" "basic" basic.name)
  ++ (check "load: extracts _meta into the node's meta" {
    description = "web server";
    version = 1;
  } server.meta)
  ++ (check "load: strips _meta from the content" {
    port = 8080;
    host = "0.0.0.0";
  } server.content)
  ++ (check "load: bare file gets no meta attribute" false (plain ? meta))
  ++ (check "load: bare file keeps its content" {
    enabled = true;
    level = "debug";
  } plain.content)
  ++ (check "load: _meta = null still strips the binding" { stale = true; } nullmeta.content)
  ++ (check "load: _meta = null attaches a meta attribute" true (nullmeta ? meta))
  ++ (check "load: _meta = null yields meta = null" true (nullmeta.meta == null))
  ++ (check "load: nested _meta is left untouched" {
    keep = true;
    nested = {
      _meta = { v = 1; };
    };
  } nested.content)
  ++ (check "load: nested _meta is not promoted to meta" false (nested ? meta))
  ++ (check "load: missing path yields null" true (lib.load pkgs ./no-such-dir == null))
  ++ (expectFailure "load: a file as root throws (not a directory)" (lib.load pkgs ./fixtures/basic/server.nix))
  ++ (check "load: no-meta subtree loads one leaf" [ "only" ] (map (n: n.name) (lib.alg.leaves bare)))
  ++ (check "load: no-meta file has no meta attribute" false (bareOnly ? meta))
  ++ (check "load: no-meta file keeps its content" { value = 42; tag = "plain"; } bareOnly.content)
  ++ (check "withMeta: enriches a hand-built tree" "dir" enriched.type)
  ++ (check "withMeta: keeps children in order" [ "server" "plain" ] (map (n: n.name) enriched.children))
  ++ (check "withMeta: extracts meta" { description = "web server"; version = 1; } enrichedServer.meta)
  ++ (check "withMeta: strips _meta from content" {
    port = 8080;
    host = "0.0.0.0";
  } enrichedServer.content)
  ++ (check "withMeta: bare child keeps content" {
    enabled = true;
    level = "debug";
  } enrichedPlain.content)
  ++ (check "withMeta: bare child gains no meta attr" false (enrichedPlain ? meta))