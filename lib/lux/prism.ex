defmodule Lux.Prism do
  @moduledoc """
  Modular, composable units of functionality for defining actions.
  """

  defmacro __using__(_opts) do
    quote do
      import Lux.Prism
    end
  end
end
