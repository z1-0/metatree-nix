# End-to-end tests for metatree-nix: the full pipeline over a realistic
# nested app tree.
#
# Exercises `load`/`withMeta` + `toAttrs` against:
#   - files that both carry and omit `_meta`
#   - cross-module `import` resolving against the stripped copy, so `_meta`
#     never leaks into a sibling
#   - let-wrapped and function-style modules
#   - the haumea-style attribute view over the enriched tree
#
# Returns the failing tests (empty when everything passes); the test flake
# feeds this to `pkgs.lib.debug.throwTestFailures`.
{ lib, pkgs }:

let
  inherit (builtins) length sort;

  check = name: expected: actual:
    if expected == actual then [ ] else [ { inherit name expected; result = actual; } ];

  sortedNames = nodes: sort (a: b: a < b) (map (n: n.name) nodes);

  tree = lib.load pkgs ./fixtures/app;
  config = lib.alg.find (n: n.name == "config") tree;
  env = lib.alg.find (n: n.name == "env") tree;
  letwrapped = lib.alg.find (n: n.name == "letwrapped") tree;
  server = lib.alg.find (n: n.name == "server") tree;
  fnmod = lib.alg.find (n: n.name == "fnmod") tree;
in
  (check "integration: root node is a dir" "dir" tree.type)
  ++ (check "integration: root name comes from the directory" "app" tree.name)
  ++ (check "integration: loads the whole tree" [
    "config"
    "env"
    "fnmod"
    "letwrapped"
    "sub"
  ] (sortedNames tree.children))
  ++ (check "integration: counts the file leaves" 5 (length (lib.alg.leaves tree)))
  ++ (check "integration: config meta extracted" {
    description = "service config";
    version = 2;
  } config.meta)
  ++ (check "integration: config content resolves its env import" {
    port = 8080;
    host = "127.0.0.1";
    region = "eu-central-1";
  } config.content)
  ++ (check "integration: env module stays bare" { region = "eu-central-1"; ssl = true; } env.content)
  ++ (check "integration: env module gains no meta attr" false (env ? meta))
  ++ (check "integration: server imports the stripped sibling" 8080 server.content.port)
  ++ (check "integration: sibling import hides the meta source" true (server.content.config.port == 8080))
  ++ (check "integration: no _meta leaks through the import" true (!(server.content.config ? _meta)))
  ++ (check "integration: server meta extracted" { description = "server module"; } server.meta)
  ++ (check "integration: let-wrapped meta extracted" { description = "top-wrapped meta"; } letwrapped.meta)
  ++ (check "integration: let-wrapped module keeps its bindings" { region = "prod"; } letwrapped.content)
  ++ (check "integration: function module meta extracted" { description = "function module"; } fnmod.meta)
  ++ (check "integration: function module stays callable" 1 (fnmod.content { config = { port = 1; }; }).port)
  ++ (check "integration: toAttrs indexes the enriched tree" { description = "service config"; version = 2; } (lib.toAttrs tree).config.meta)
  ++ (check "integration: toAttrs resolves content through the view" 8080 (lib.toAttrs tree).sub.server.content.port)
  ++ (check "integration: toAttrs keeps leaf path segments" "server" (lib.toAttrs tree).sub.server.name)