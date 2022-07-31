defmodule HelloWorld.Schemas do
  use Cordial.Schema, root: Elixir

  import_schema "https://github.com/grpc/grpc/blob/master/examples/protos/helloworld.proto"
end
