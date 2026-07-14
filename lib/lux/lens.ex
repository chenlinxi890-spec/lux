defmodule Lux.Lens do
  @moduledoc """
  Event-driven sensors for data gathering and broadcasting.
  """

  defmacro __using__(_opts) do
    quote do
      import Lux.Lens
    end
  end
end
