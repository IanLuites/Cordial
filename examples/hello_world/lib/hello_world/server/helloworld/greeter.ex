defmodule HelloWorld.Server.Helloworld.Greeter do
  @behaviour Helloworld.Greeter

  @impl Helloworld.Greeter
  def say_hello(%Helloworld.HelloRequest{name: name}) do
    {:ok, %Helloworld.HelloReply{message: "Hello #{name}!"}}
  end
end
