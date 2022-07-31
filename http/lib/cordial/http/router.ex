defmodule Cordial.HTTP.Router do
  # https://cloud.google.com/endpoints/docs/grpc/transcoding
  # https://cloud.google.com/endpoints/docs/grpc-service-config/reference/rpc/google.api#google.api.HttpRule

  @typep segment :: {path :: binary, dirty? :: boolean()}
  @typep path :: [segment]
  @typep variables :: %{required(atom) => [atom]}
  @typep route ::
           {method :: atom, path :: path(), variables :: variables, function :: map,
            service :: module, implementation :: module}
  @typep forward :: {path :: path(), router :: module}
  @typep router :: %{name: module, prefix: path(), routes: [route], forwards: [forward]}

  def child_spec(config) do
    quote do
      Buckaroo.child_spec(plug: unquote(config.http.module), port: unquote(config.http.port))
    end
  end

  def generate(config) do
    config
    |> routers()
    |> Enum.sort_by(&to_string(&1.name), :desc)
    |> Enum.map(&build_router(&1, config))
  end

  defp build_router(router, config) do
    root = Elixir

    root_router =
      if router.name == config.http.name do
        quote do
          plug(Plug.Parsers,
            parsers: [:json],
            json_decoder: Jason
          )
        end
      end

    dirty =
      if not Enum.any?(router.prefix, &elem(&1, 1)) and
           (Enum.any?(router.forwards, fn f -> Enum.any?(elem(f, 0), &elem(&1, 1)) end) or
              Enum.any?(router.routes, fn r -> Enum.any?(elem(r, 1), &elem(&1, 1)) end)) do
        quote do
          plug(Cordial.HTTP.Escape)
        end
      end

    forwards =
      Enum.map(router.forwards, fn {path, to} ->
        quote do
          forward(unquote(path(path)), to: unquote(to))
        end
      end)

    routes = Enum.map(router.routes, &gen_route(&1, root))

    quote location: :keep do
      defmodule unquote(router.name) do
        @moduledoc false
        use Buckaroo.Router

        unquote(dirty)
        unquote(root_router)

        plug(:match)
        plug(:dispatch)

        unquote(forwards)
        unquote(routes)

        match _ do
          var!(conn)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(404, ~s|{}|)
        end
      end
    end
  end

  defp path(path), do: "/" <> Enum.map_join(path, "/", &elem(&1, 0))

  defp gen_route(route, root)

  defp gen_route({method, path, variables, function, _service, implementation}, root) do
    call = function.name |> Macro.underscore() |> String.to_atom()

    helper = Cordial.Definition.Resource
    req_module = helper.module(function.argument.type, root)

    path_vars =
      Enum.map(variables, fn {var, path} ->
        quote do
          var!(data) =
            put_in(
              var!(data),
              unquote(Enum.map(path, &to_string/1)),
              Map.get(var!(path_params), unquote(to_string(var)))
            )
        end
      end)

    path_parsing =
      unless Enum.empty?(path_vars) do
        quote do
          var!(path_params) = var!(conn).path_params
          unquote(path_vars)
        end
      end

    body =
      quote do
        var!(data) = var!(conn).body_params
        unquote(path_parsing)

        with {:ok, req} <- unquote(req_module).from_json(var!(data)),
             {:ok, resp} <- unquote(implementation).unquote(call)(req),
             {:ok, encoded} <- Jason.encode(resp) do
          var!(conn)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, encoded)
        else
          _ ->
            var!(conn)
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(400, ~s|{"error":"bad_request"}|)
        end
      end

    quote do
      unquote(method)(unquote(path(path)), do: unquote(body))
    end
  end

  @spec routers(config :: map) :: [router()]
  defp routers(config) do
    name = config.http.module

    routers =
      config
      |> routes()
      |> group_routes()
      |> Enum.map(fn
        {[], routes} ->
          %{
            name: name,
            prefix: [],
            routes: routes,
            forwards: []
          }

        {prefix, routes} ->
          subname =
            prefix
            |> Enum.map(fn {segment, _} -> segment |> Macro.camelize() end)
            |> Module.concat()

          range = Enum.count(prefix)..-1

          %{
            name: Module.concat(name, subname),
            prefix: prefix,
            routes:
              Enum.map(routes, fn {a, route, v, f, b, c} ->
                {a, Enum.slice(route, range), v, f, b, c}
              end),
            forwards: []
          }
      end)

    routers =
      if Enum.any?(routers, &(&1.prefix == [])),
        do: routers,
        else: [
          %{
            name: name,
            prefix: [],
            routes: [],
            forwards: []
          }
          | routers
        ]

    set_forwards(routers, name, routers)
  end

  defp set_forwards(routers, root, acc)
  defp set_forwards([], _root, acc), do: acc
  defp set_forwards([%{prefix: []} | routers], root, acc), do: set_forwards(routers, root, acc)

  defp set_forwards([%{name: name, prefix: prefix} | routers], root, acc) do
    {length, mod} =
      acc
      |> Enum.map(&{match_length(prefix, &1.prefix), &1.name})
      |> Enum.filter(fn {l, n} -> n != name and l > 0 end)
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> List.first()
      |> Kernel.||({0, root})

    acc =
      Enum.map(acc, fn
        r = %{name: ^mod, forwards: f} ->
          %{r | forwards: [{Enum.slice(prefix, length..-1), name} | f]}

        r ->
          r
      end)

    set_forwards(routers, root, acc)
  end

  defp match_length(a, b, v \\ 0)
  defp match_length([h | a], [h | b], v), do: match_length(a, b, v + 1)
  defp match_length(_, _, v), do: v

  @spec group_routes(routes :: [route]) :: [{prefix :: path, routes :: [route()]}]
  defp group_routes(routes) do
    length =
      Enum.reduce(routes, 0, fn {_, path, _, _, _, _}, acc -> max(acc, Enum.count(path) - 1) end)

    do_group(routes, length, %{})
  end

  defp do_group([], _length, grouped), do: grouped
  defp do_group(routes, 0, grouped), do: Map.put(grouped, [], routes)

  defp do_group(routes, length, grouped) do
    {left, grouped} =
      routes
      |> Enum.group_by(fn {_, path, _, _, _, _} -> Enum.slice(path, 0..length) end)
      |> Enum.reduce({[], grouped}, fn {prefix, routes}, {left, grouped} ->
        case routes do
          [r] -> {[r | left], grouped}
          l -> {left, Map.put(grouped, prefix, l)}
        end
      end)

    do_group(left, length - 1, grouped)
  end

  @spec routes(config :: map) :: [route()]
  defp routes(config) do
    Enum.flat_map(config.services, fn {implementation, services} ->
      Enum.flat_map(services, &routes_service(&1, implementation, config))
    end)
  end

  @spec routes_service(service :: module, implementation :: module, config :: map) :: [route()]
  defp routes_service(service, implementation, config) do
    %{name: name, package: package, functions: functions} = service.__cordial__().definition
    # parent: parent,
    parent = []

    functions
    |> Enum.map(fn function ->
      cond do
        http_rule = Map.get(function.options, "google.api.http", false) ->
          {verb, path, path_vars} = method_path(http_rule)
          {verb, path, path_vars, function, service, implementation}

        config.http.expose == :all ->
          # If not strict...
          path = String.split(package, ".") ++ parent ++ [name, function.name]
          path = path |> Enum.map(&Macro.underscore/1) |> Enum.map(&{&1, false})

          {:post, path, %{}, function, service, implementation}

        :not_exposed ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @available ~w(get put post delete patch custom)

  @spec method_path(http_rule :: map) :: {atom, path(), variables()}
  defp method_path(http_rule) do
    {verb, path} =
      Enum.find_value(@available, fn verb ->
        case Map.get(http_rule, verb, "") do
          "" -> false
          %{kind: v, path: "/" <> p} when verb == "custom" -> {v, p}
          %{kind: v, path: p} when verb == "custom" -> {v, p}
          "/" <> path -> {verb, path}
          path -> {verb, path}
        end
      end)

    path = String.replace(path, ":", <<0>>)
    {path, variables} = extract_variables(path)

    path =
      path
      |> String.split("/")
      |> Enum.map(fn segment ->
        if String.contains?(segment, <<0>>) do
          {String.replace(segment, <<0>>, "@"), true}
        else
          {segment, false}
        end
      end)

    {String.to_atom(verb), path, variables}
  end

  @spec extract_variables(path :: String.t()) :: {path :: String.t(), variables()}
  defp extract_variables(path) do
    ~r/\{[^}]+\}/
    |> Regex.scan(path)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.reduce({path, %{}}, fn var, {path, vars} ->
      var_path = var |> String.slice(1..-2) |> String.split(".") |> Enum.map(&String.to_atom/1)
      name = var_path |> Enum.map_join("_", &to_string/1) |> String.to_atom()

      if Map.has_key?(vars, var), do: raise("Owh owh, duplicate var in path.")

      {String.replace(path, var, ":#{name}"), Map.put(vars, name, var_path)}
    end)
  end
end
