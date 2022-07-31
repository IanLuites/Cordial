defmodule Cordial.MixProject do
  use Mix.Project

  @app :cordial
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
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

      # Docs
      name: "Cordial",
      description: @description,
      docs: docs(),
      source_url: @scm_url,
      homepage_url: "https://github.com/#{@scm_project}"
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
        lib
        README.md
        CHANGELOG.md
        LICENSE.md
      )
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "overview",
      logo: "../logo.png",
      extra_section: "GUIDES",
      assets: "../guides/assets",
      formatters: ["html", "epub"]
    ]
  end

  def application do
    [
      extra_applications: [:inets, :logger, :ssl]
    ]
  end

  defp deps do
    [
      suite(:grpc, optional: true),
      suite(:http, optional: true),

      # Deps
      {:jason, ">= 0.0.0"},
      {:heimdallr, ">= 0.0.0", only: [:dev, :test]}
    ]
  end

  defp suite(app, opts) do
    mode =
      if System.get_env("CORDIAL_LOCAL_DEPENDENCIES", "false") == "true",
        do: [path: "../#{app}"],
        else: [github: @scm_project, sparse: to_string(app)]

    opts = Keyword.merge(opts, mode)
    {:"cordial_#{app}", @version, opts}
  end
end
