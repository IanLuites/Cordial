defmodule HelloWorld.Server do
  use Cordial.Server, grpc: false, http: true

  service HelloWorld.Server.Helloworld.Greeter
end
