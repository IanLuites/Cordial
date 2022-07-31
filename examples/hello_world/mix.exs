defmodule HelloWorld.MixProject do
  use Mix.Project

  def project do
    [
      app: :hello_world,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {HelloWorld.Application, []}
    ]
  end

  defp deps do
    [
      {:cordial, github: "ianluites/cordial", sparse: "cordial"},
      {:cordial_http, github: "ianluites/cordial", sparse: "http"}
    ]
  end
end
