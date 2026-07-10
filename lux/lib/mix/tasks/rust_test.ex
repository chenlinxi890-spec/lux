defmodule Mix.Tasks.Rust.Test do
  @shortdoc "Runs Rust tests via cargo test"
  @moduledoc """
  Runs Rust tests via `cargo test` and reports results.

  This task integrates with the Lux Rust test runner module and
  provides a CLI entry point for bounty #102.

  ## Usage

      mix rust.test
      mix rust.test Lux.Rust.TypeMappingTest

  ## Options

  - No options currently supported. Test names can be passed as positional args.

  ## Exit Codes

  - `0` — all Rust tests passed
  - `1` — one or more Rust tests failed, or cargo/tarpaulin not available

  ## Example

      $ mix rust.test
      Running cargo test...
      test result: ok. 42 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.12s
      Summary: 42 passed, 0 failed, duration: 0.12s
  """

  use Mix.Task

  require Logger

  @impl Mix.Task
  def run(args \\ []) do
    Mix.shell().info("Running Rust tests via cargo test...\\n")

    case Lux.RustTestRunner.run(args) do
      {:ok, results} ->
        summary = Lux.RustTestRunner.summary(results)
        Mix.shell().info("""
        \\nRust Test Results:
          Passed:  #{summary.passed}
          Failed:  #{summary.failed}
          Total:   #{summary.total}
          Duration: #{summary.duration}
        """)

        if summary.failed > 0 do
          Mix.shell().error("Some Rust tests failed.")
          exit({:shutdown, 1})
        else
          Mix.shell().info("All Rust tests passed. \\u{2705}")
          :ok
        end

      {:error, reason} ->
        Mix.shell().error("Rust test runner failed: #{reason}")
        exit({:shutdown, 1})
    end
  end
end
