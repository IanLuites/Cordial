defmodule <%= inspect Module.concat(@client_module || @server_module, Schema) %> do
  @moduledoc ~S"""
  """
  use Cordial.Schema, root: <%= inspect (@prefix) %>
  <%= for proto <- @proto do %>
  import_schema <%= inspect proto %>
<% end %>end
