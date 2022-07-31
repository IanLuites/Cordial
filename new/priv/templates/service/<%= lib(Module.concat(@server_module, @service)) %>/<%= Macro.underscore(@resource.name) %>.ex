defmodule <%= inspect Module.concat(@server_module, @service) %> do
  @moduledoc ~S"""
  <%= @resource.name %> implementation.

  See: `<%= inspect @service %>`.
  """
  @behaviour <%= inspect @service %>
  <%= for function <- @resource.functions do %>
  @doc ~S"""
  <%= function.name %> implementation.

  See: `<%= inspect @service %>.<%= Macro.underscore(function.name) %>/1`.
  """
  @impl <%= inspect @service %>
  def <%= Macro.underscore(function.name) %>(%<%= inspect module(function.argument.type, @prefix) %>{}) do
    # TODO: Implement <%= @resource.name %> <%= function.name %>.
    {:ok, %<%= inspect module(function.return.type, @prefix) %>{}}
  end
<% end %>end
