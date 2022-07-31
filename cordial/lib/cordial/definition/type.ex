defmodule Cordial.Definition.Type do
  alias Cordial.Definition.Resource

  @type t ::
          :double
          | :float
          | :int32
          | :int64
          | :uint32
          | :uint64
          | :sint32
          | :sint64
          | :fixed32
          | :fixed64
          | :sfixed32
          | :sfixed64
          | :bool
          | :string
          | :bytes
          | {:map, key :: t, value :: t}
          | {:type, relative :: String.t(), absolute :: String.t()}

  @scalars ~W(double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes)a

  @spec scalars :: [Cordial.Definition.Type.t()]
  def scalars, do: @scalars

  def module(type, root \\ Elixir)
  def module(type, _) when type in @scalars, do: nil
  def module({:map, _, _}, _), do: nil
  def module(complex, root), do: Resource.module(complex, root)

  @spec typespec(Cordial.Definition.Type.t(), root :: module) :: term
  def typespec(type, root \\ Elixir)
  def typespec(float, _) when float in ~w(double float)a, do: type_b(:float)

  def typespec(uint, _) when uint in ~w(uint32 uint64 fixed32 fixed64)a,
    do: type_b(:non_neg_integer)

  def typespec(int, _) when int in ~w(int32 int64 sint32 sint64 sfixed32 sfixed64)a,
    do: type_b(:integer)

  def typespec(:bool, _), do: type_b(:boolean)
  def typespec(:string, _), do: type_t([:String])
  def typespec(:bytes, _), do: type_b(:binary)

  def typespec({:map, key, value}, root),
    do: {:%{}, [], [{{:required, [], [typespec(key, root)]}, typespec(value, root)}]}

  def typespec(complex, root), do: complex |> Resource.module(root) |> type_t()

  @spec proto(type :: Cordial.Definition.Type.t()) :: String.t()
  def proto(type)
  def proto({:map, key, value}), do: "map<#{proto(key)}, #{proto(value)}>"
  def proto({:type, relative, _absolute}), do: relative
  def proto(type), do: to_string(type)

  @spec default(Cordial.Definition.Type.t(), root :: module) :: term
  def default(type, root \\ Elixir)
  def default(:bool, _), do: false
  def default(:bytes, _), do: <<>>
  def default(:string, _), do: ""
  def default(float, _) when float in ~w(double float)a, do: 0.0
  def default(integer, _) when is_atom(integer), do: 0
  def default({:map, _, _}, _), do: Macro.escape(%{})

  def default(complex, root) do
    quote do
      unquote(Resource.module(complex, root)).default()
    end
  end

  @spec parser(Cordial.Definition.Type.t(), root :: module) :: {module, atom}
  def parser(type, root \\ Elixir)

  def parser(:bool, _), do: {__MODULE__, :bool}
  def parser(:bytes, _), do: {__MODULE__, :bytes}
  def parser(:string, _), do: {__MODULE__, :string}
  def parser(float, _) when float in ~w(double float)a, do: {__MODULE__, :float}
  def parser(integer, _) when is_atom(integer), do: {__MODULE__, :integer}
  def parser({:map, _, _}, _), do: {__MODULE__, :map}
  def parser(complex, root), do: {Resource.module(complex, root), :from_json}

  defp type_t(module) when is_atom(module),
    do: module |> Module.split() |> Enum.map(&String.to_atom/1) |> type_t()

  defp type_t(mod), do: {{:., [], [{:__aliases__, [alias: false], mod}, :t]}, [], []}
  defp type_b(type), do: {type, [if_undefined: :apply], Elixir}

  @doc false
  @spec package_to_module(String.t() | nil) :: module
  def package_to_module(package)
  def package_to_module(nil), do: Elixir

  def package_to_module(package) do
    package |> String.split(".") |> Enum.map(&Macro.camelize/1) |> Module.concat()
  end

  ### Parsers ###

  @doc false
  @spec bool(value :: any) :: {:ok, value :: boolean()} | {:error, :invalid_boolean}
  def bool(value)
  def bool(value) when value in [true, false], do: {:ok, value}
  def bool(_), do: {:error, :invalid_boolean}

  @doc false
  @spec bytes(value :: any) :: {:ok, value :: binary()} | {:error, :invalid_bytes}
  def bytes(value)

  def bytes(value) when is_binary(value) do
    with :error <- Base.decode64(value) do
      {:error, :invalid_bytes_base64}
    end
  end

  def bytes(_), do: {:error, :invalid_bytes}

  @doc false
  @spec string(value :: any) :: {:ok, value :: binary()} | {:error, :invalid_string}
  def string(value)
  def string(value) when is_binary(value), do: {:ok, value}
  def string(_), do: {:error, :invalid_string}

  @doc false
  @spec float(value :: any) :: {:ok, value :: float()} | {:error, :invalid_integer}
  def float(value)
  def float(value) when is_float(value), do: {:ok, value}
  def float(_), do: {:error, :invalid_float}

  @doc false
  @spec integer(value :: any) :: {:ok, value :: integer()} | {:error, :invalid_integer}
  def integer(value)
  def integer(value) when is_integer(value), do: {:ok, value}
  def integer(_), do: {:error, :invalid_integer}

  @doc false
  @spec map(value :: any) :: {:ok, value :: map()} | {:error, :invalid_map}
  def map(value)
  def map(value) when is_map(value), do: {:ok, value}
  def map(_), do: {:error, :invalid_map}
end
