defmodule Cordial.New.MixProject do
  use Mix.Project

  @app :cordial_new
  @version "0.0.1"
  @scm_project "ianluites/cordial"
  @scm_url "https://github.com/#{@scm_project}/#{@app}"

  @external_resource readme = "./README.md"
  @description readme
               |> File.stream!([:read], :line)
               |> Enum.take(3)
               |> List.last()
               |> String.trim_trailing(".\n")

  def project do
    [
      app: @app,
      version: @version,
      description: @description,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  defp package do
    [
      maintainers: ["Ian Luites"],
      licenses: ["MIT"],
      links: %{"GitHub" => @scm_url},
      files: ~W(
        mix.exs
        .formatter.exs
        priv
        lib
        README.md
        CHANGELOG.md
        LICENSE.md
      )
    ]
  end

  def application do
    [
      extra_applications: [:eex, :inets, :logger, :ssl]
    ]
  end

  defp deps do
    []
  end
end
