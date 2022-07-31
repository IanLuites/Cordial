defmodule <%= inspect @server_module %> do
  @moduledoc """
  Documentation for `Server`.
  """
  use Cordial.Server<%= if @grpc? do %>, grpc: true<% end %><%= if @http? do %>, http: true<% end %>
  <%= for service <- @services do %>
  service <%= inspect Module.concat(@server_module, service) %>
<% end %>end
