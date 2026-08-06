{
  _meta = {
    description = "service config";
    version = 2;
  };
  port = 8080;
  host = "127.0.0.1";
  region = (import ./env.nix).region;
}