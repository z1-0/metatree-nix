rec {
  _meta = { description = "server module"; };
  config = import ../config.nix;
  port = config.port;
  host = config.host;
}