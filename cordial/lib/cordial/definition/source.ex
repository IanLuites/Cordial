defmodule Cordial.Definition.Source do
  @type t :: %__MODULE__{
          uri: URI.t(),
          local: Path.t(),
          line: pos_integer() | nil
        }

  defstruct [:uri, :local, line: nil]

  defimpl Inspect do
    import Inspect.Algebra
    def inspect(source, _opts), do: concat(["#Source<", to_string(source.uri), ">"])
  end

  defimpl String.Chars do
    def to_string(source), do: Kernel.to_string(source.uri)
  end
end
