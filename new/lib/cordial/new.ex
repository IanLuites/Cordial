defmodule Cordial.New do
  @moduledoc """
  Documentation for `Cordial.New`.
  """
  alias Cordial.New.{Client, Schema, Server, Service}

  def create(config)

  def create(config) do
    priv = priv(config)
    File.mkdir_p!(priv)
    definition = Cordial.Definition.load(List.first(config.proto), cwd: priv)

    config = %{
      config
      | services: Enum.filter(definition, &match?(%Cordial.Definition.Service{}, &1))
    }

    assigns = Enum.to_list(config)

    if config.client? do
      _ = Client
      # Client.render(config.client_dir, assigns)
      :ok
    end

    Enum.each(
      config.services,
      &Service.render(config.server_dir, [{:service, &1} | assigns])
    )

    Server.render(config.server_dir, assigns)
    Schema.render(config.client_dir || config.server_dir, assigns)
  end

  @spec priv(config :: map) :: Path.t()
  defp priv(config)
  defp priv(%{client?: true, client_dir: dir}), do: Path.join(dir, "priv")
  defp priv(%{client?: false, server_dir: dir}), do: Path.join(dir, "priv")
end
