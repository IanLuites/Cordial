defmodule Cordial.GRPCTest do
  use ExUnit.Case
  doctest Cordial.GRPC

  test "greets the world" do
    assert Cordial.GRPC.hello() == :world
  end
end
