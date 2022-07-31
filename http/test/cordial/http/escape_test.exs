defmodule Cordial.HTTP.EscapeTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias Cordial.HTTP.Escape

  defp call(path) do
    :get |> conn(path) |> Escape.call(Escape.init([]))
  end

  test "replaces : with @ in request path info" do
    assert call("/v1/projects/my-project-21378:lookup").path_info == [
             "v1",
             "projects",
             "my-project-21378@lookup"
           ]
  end

  test "leaves the original request path untouched" do
    assert call("/v1/projects/my-project-21378:lookup").request_path ==
             "/v1/projects/my-project-21378:lookup"
  end
end
