defmodule Cordial.HTTP.Escape do
  @moduledoc ~S"""
  Escape plug to allow use of literal ':' in paths.

  This functionality is required, because some gRPC definitions
  use `<resource>:<action>` syntax.
  See for example: [Google Datastore](https://github.com/googleapis/googleapis/blob/master/google/datastore/v1/datastore.proto).

  For now the solution is to replace ':' with '@' in paths
  and to use this plug to apply the same replacement for each request.
  """
  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn = %{path_info: path_info}, _opts) do
    %{conn | path_info: Enum.map(path_info, &String.replace(&1, ":", "@"))}
  end
end
