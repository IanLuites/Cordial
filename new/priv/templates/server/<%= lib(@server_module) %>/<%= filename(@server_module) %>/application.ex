defmodule <%= inspect @server_module %>.Application do
  @moduledoc false
  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      <%= inspect @server_module %>
    ]

    opts = [strategy: :one_for_one, name: <%= inspect @server_module %>.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
