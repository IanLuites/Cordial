defmodule <%= inspect @server_module %>.MixProject do
  use Mix.Project

  def project do
    [
      app: <%= inspect @server_app %>,
      version: "0.0.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],<%= if @client_app do %>
      included_application: [<%= inspect @client_app %>],<% end %>
      mod: {<%= inspect @server_module %>.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cordial, github: "ianluites/cordial", sparse: "cordial"}<%= if @grpc? do %>,
      {:cordial_http, github: "ianluites/cordial", sparse: "grpc"}<% end %><%= if @http? do %>,
      {:cordial_http, github: "ianluites/cordial", sparse: "http"}<% end %><%= if @client_app do %>,
      {<%= inspect @client_app %>, path: "../client", runtime: false}<% end %>
    ]
  end
end
