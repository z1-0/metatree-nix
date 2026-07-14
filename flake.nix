{
  inputs.nix-meta.url = "github:z1-0/nix-meta";
  inputs.srctree.url = "github:z1-0/srctree-nix";

  outputs = inputs: {lib = import ./default.nix inputs;};
}
