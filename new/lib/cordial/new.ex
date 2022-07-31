defmodule Cordial.New do
  @moduledoc """
  Documentation for `Cordial.New`.
  """
  alias Cordial.New.{Client, Schema, Server, Service}

  def create(config)

  def create(config) do
    priv = priv(config)
    File.mkdir_p!(priv)

    Schema.render(config.client_dir || config.server_dir, Enum.to_list(config))
    resources = read_schema(config)

    config = %{
      config
      | resources: resources,
        services:
          resources
          |> Enum.filter(&match?({_, %{__struct__: Cordial.Definition.Service}}, &1))
          |> Enum.map(&elem(&1, 0))
    }

    assigns = Enum.to_list(config)

    if config.client? do
      _ = Client
      # Client.render(config.client_dir, assigns)
      :ok
    end

    Enum.each(
      config.services,
      &Service.render(config.server_dir, [{:service, &1}, {:resource, resources[&1]} | assigns])
    )

    Server.render(config.server_dir, assigns)
    fetch_deps!(config)
    compile!(config)
  end

  @spec priv(config :: map) :: Path.t()
  defp priv(config)
  defp priv(%{client?: true, client_dir: dir}), do: Path.join(dir, "priv")
  defp priv(%{client?: false, server_dir: dir}), do: Path.join(dir, "priv")

  defp fetch_deps!(config) do
    cmd = &Mix.shell().cmd/2

    config.client? && cmd.("mix deps.get", cd: config.client_dir, quiet: not config.verbose?)
    config.server? && cmd.("mix deps.get", cd: config.server_dir, quiet: not config.verbose?)
  end

  defp compile!(config) do
    cmd = &Mix.shell().cmd/2

    config.client? && cmd.("mix compile", cd: config.client_dir, quiet: not config.verbose?)
    config.server? && cmd.("mix compile", cd: config.server_dir, quiet: not config.verbose?)
  end

  defp read_schema(config) do
    cmd = &Mix.shell().cmd/2
    schema_dir = config.client_dir || config.server_dir
    schema_mod = inspect(Module.concat(config.client_module || config.server_module, "Schema"))
    schema_file = Path.join(schema_dir, "schema.term")

    schema_cmd = ~s"""
    File.write!("schema.term", #{schema_mod}.resources |> Enum.map(&{&1, &1.__cordial__().definition}) |> :erlang.term_to_binary())
    """

    cmd.("mix deps.get", cd: schema_dir, quiet: not config.verbose?)
    cmd.("elixir -S mix run -e '#{schema_cmd}'", cd: schema_dir, quiet: not config.verbose?)

    resources = schema_file |> File.read!() |> :erlang.binary_to_term() |> Map.new()
    File.rm!(schema_file)

    resources
  end
end
