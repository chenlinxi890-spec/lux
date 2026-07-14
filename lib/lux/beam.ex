defmodule Lux.Beam do
  @moduledoc """
  Flexible workflows that orchestrate multiple actions.
  """

  defmacro __using__(_opts) do
    quote do
      import Lux.Beam
    end
  end
end
