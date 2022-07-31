defmodule <%= inspect @client_module || @server_module %>.MixProject do
  use Mix.Project

  def project do
    [
      app: <%= inspect (@client_app || @server_app) %>,
      version: "0.0.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cordial, github: "ianluites/cordial", sparse: "cordial"}
    ]
  end
end
