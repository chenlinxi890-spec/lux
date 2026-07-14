defmodule Lux.Signal do
  @moduledoc """
  A signal represents messages that can be sent between Specters.
  """

  defmacro __using__(_opts) do
    quote do
      import Lux.Signal
    end
  end
end
