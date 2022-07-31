defmodule Mix.Tasks.Local.Cordial do
  @moduledoc ~S"""
  Updates the Cordial project generator locally.

  ```shell
  $ mix local.cordial
  ```

  Accepts the same command line options as `archive.install hex cordial_new`.
  """
  use Mix.Task

  @shortdoc ~S"Updates the Cordial project generator locally."
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("archive.install", ["hex", "cordial_new" | args])
  end
end
