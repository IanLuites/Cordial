defmodule <%= inspect module(@service, @server_module) %> do
  @moduledoc ~S"""
  <%= @service.name %> implementation.

  See: `<%= inspect module(@service, @prefix) %>`.
  """
  @behaviour <%= inspect module(@service, @prefix) %>
  <%= for function <- @service.functions do %>
  @doc ~S"""
  <%= function.name %> implementation.

  See: `<%= inspect module(@service, @prefix) %>.<%= Macro.underscore(function.name) %>/1`.
  """
  @impl <%= inspect module(@service, @prefix) %>
  def <%= Macro.underscore(function.name) %>(%<%= inspect module(function.argument.type, @prefix) %>{}) do
    # TODO: Implement <%= @service.name %> <%= function.name %>.
    {:ok, %<%= inspect module(function.return.type, @prefix) %>{}}
  end
<% end %>end
