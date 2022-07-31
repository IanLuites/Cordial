defmodule Cordial.Definition.Parser do
  alias Cordial.Definition.Source
  alias Cordial.Definition.Parser.Context

  @type opt :: {:cwd, Path.t()}
  @type opts :: [opt]

  @spec load(
          source :: Cordial.Definition.Source.t() | URI.t() | String.t(),
          opts :: Cordial.Definition.Parser.opts()
        ) :: Cordial.Definition.Parser.Context.t()
  def load(source, opts \\ []), do: load(Context.new(opts), source, opts)

  @spec load(
          context :: Cordial.Definition.Parser.Context.t(),
          source :: Cordial.Definition.Source.t() | URI.t() | String.t(),
          opts :: Cordial.Definition.Parser.opts()
        ) :: Cordial.Definition.Parser.Context.t()
  def load(source, context, opts)

  def load(context, maybe_source, _opts) do
    with {:ok, source} <- verify_source(maybe_source, Context.source(context)),
         nil <- if(Context.source_loaded?(context, source), do: context),
         {:ok, data} <- read(source, context.root_dir, context.cwd) do
      context
      |> Context.context_new(source, Path.dirname(source.local))
      |> (&Cordial.Parsers.GRPC.parse(data, &1)).()
      |> Context.context_pop()
    end
  end

  @spec verify_source(
          source :: Cordial.Definition.Source.t() | URI.t() | String.t(),
          relative :: Cordial.Definition.Source.t() | nil
        ) ::
          {:ok, Cordial.Definition.Source.t()} | {:error, atom}
  defp verify_source(source, relative)
  defp verify_source(source = %Source{}, _relative), do: {:ok, source}

  defp verify_source("cordial.proto", _),
    do: {:ok, %Source{uri: %URI{path: "cordial.proto"}, local: "cordial.proto"}}

  defp verify_source(source, relative) when is_binary(source),
    do: verify_source(URI.parse(source), relative)

  defp verify_source(source = %URI{scheme: web, path: path}, _relative)
       when web in ~W(http https) do
    {:ok, %Source{uri: source, local: String.trim_leading(path, "/")}}
  end

  defp verify_source(source = %URI{scheme: nil, path: path}, relative) when is_binary(path) do
    cond do
      path =~ ~r/^google\/([a-z0-9_\/]+)\.proto$/ -> {:ok, %Source{uri: source, local: path}}
      path =~ ~r/^[^\n]+\.proto/ -> join(relative, path)
      :maybe_data -> verify_source("data:," <> URI.encode(path), relative)
    end
  end

  defp verify_source(source = %URI{scheme: "data", path: path}, _relative) do
    local =
      case Regex.run(~r/package\s*([^;]+);/, path) do
        [_, file] -> file <> ".proto"
        _ -> ".proto"
      end

    {:ok, %Source{uri: source, local: local}}
  end

  defp verify_source(source = %URI{scheme: "file", path: path}, _relative) do
    {:ok, %Source{uri: source, local: path}}
  end

  @spec join(relative :: Cordial.Definition.Source.t() | nil, path :: Path.t()) ::
          {:ok, Cordial.Definition.Source.t()} | {:error, atom}
  defp join(relative, path)
  defp join(nil, "/" <> path), do: verify_source("file://" <> path, nil)
  defp join(nil, path), do: verify_source("file://./" <> path, nil)

  defp join(relative = %Source{uri: uri = %URI{}}, path = "/" <> _),
    do: verify_source(%{uri | path: path}, relative)

  defp join(relative = %Source{uri: uri = %URI{path: p}}, path) do
    dir = p |> Path.dirname() |> String.replace_suffix(Path.dirname(path), "")

    verify_source(%{uri | path: Path.join(dir, path)}, relative)
  end

  @spec read(source :: Cordial.Definition.Source.t(), root :: Path.t(), cwd :: Path.t()) ::
          {:ok, binary}
  defp read(source, root, cwd)

  defp read(source = %Source{local: local}, root, cwd) do
    rel = if String.starts_with?(source.uri.path, "./"), do: cwd, else: root
    file = Path.join(rel, local)
    File.mkdir_p!(Path.dirname(file))

    if File.exists?(file) do
      File.read(file)
    else
      with {:ok, data} <- pull(source),
           :ok <- File.write(file, data),
           do: {:ok, data}
    end
  end

  @spec pull(source :: Cordial.Definition.Source.t()) :: {:ok, binary}
  defp pull(source)

  defp pull(%Source{uri: %URI{scheme: nil, path: "cordial.proto"}}), do: {:ok, ""}

  defp pull(%Source{uri: uri = %URI{scheme: scheme, authority: authority}})
       when scheme in ~W(http https) do
    uri =
      case authority do
        "github.com" ->
          path = String.replace(uri.path, ~r/^\/([^\/]+)\/([^\/]+)\/blob\//, "/\\1/\\2/raw/")
          %{uri | path: path}

        _ ->
          uri
      end

    uri |> to_string() |> download()
  end

  defp pull(%Source{uri: uri = %URI{scheme: "file"}}),
    do: File.read(to_string(%{uri | scheme: nil}))

  defp pull(%Source{uri: %URI{scheme: nil, path: file = "google/protobuf/" <> _}}),
    do: download("https://github.com/protocolbuffers/protobuf/raw/main/src/#{file}")

  defp pull(%Source{uri: %URI{scheme: nil, path: file = "google/" <> _}}),
    do: download("https://github.com/googleapis/googleapis/raw/master/#{file}")

  defp pull(%Source{uri: %URI{scheme: "data", path: path}}),
    do: {:ok, path |> String.split(",", parts: 2) |> List.last()}

  defp download(url) do
    :inets.start()
    :ssl.start()

    case :httpc.request(
           :get,
           {String.to_charlist(url), []},
           [ssl: [verify: :verify_none]],
           []
         ) do
      {:ok, {_, _, schema}} -> {:ok, to_string(schema)}
      _ -> {:error, :download_failed}
    end
  end
end
