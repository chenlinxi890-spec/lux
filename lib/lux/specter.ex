defmodule Lux.Specter do
  @moduledoc """
  The Specter is the main entry point for the Lux library.
  """

  defmacro __using__(_opts) do
    quote do
      import Lux.Lens
      import Lux.Signal
      import Lux.Beam
      import Lux.Specter
    end
  end
end
