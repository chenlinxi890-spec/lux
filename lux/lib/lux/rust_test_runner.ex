defmodule Lux.RustTestRunner do
  @moduledoc """
  Rust Test Runner for Lux — Integration with mix test for bounty #102.

  Provides a Rust test runner that integrates with the existing
  Elixir test infrastructure, with coverage reporting,
  cross-language test utilities, and test fixtures.

  ## Usage

      alias Lux.RustTestRunner

      # Run all Rust tests
      {:ok, results} = RustTestRunner.run()

      # Run specific test module
      {:ok, results} = RustTestRunner.run(["Lux.Rust.TypeMappingTest"])

      # Run with coverage
      {:ok, coverage} = RustTestRunner.coverage()

      # Get test summary
      summary = RustTestRunner.summary(results)

  ## Mix Integration

  This module is designed to be invoked via `mix test` through the
  ExUnit integration in `Lux.RustTestRunnerTest`. For direct CLI usage,
  implement a `Mix.Task.rust_test` module that delegates to `run/1`.

      # Example Mix.Task integration (to be added separately):
      # defmodule Mix.Tasks.RustTest do
      #   use Mix.Task
      #   def run(args) do
      #     {:ok, results} = Lux.RustTestRunner.run(args)
      #     Lux.RustTestRunner.summary(results)
      #     |> IO.inspect()
      #   end
      # end

  ## Cargo Project Resolution

  The `run/1` and `coverage/0` functions resolve the Rust project path
  from the Lux repository root. If no Cargo.toml is found in the
  expected locations, an error is returned.

  """

  require Logger

  @doc "Runs all Rust tests via cargo test."
  @spec run(list(String.t())) :: {:ok, map()} | {:error, String.t()}
  def run(tests \\ []) do
    case resolve_cargo_project_path() do
      {:ok, project_path} ->
        cmd_args = ["test", "--all"] ++ tests

        case System.cmd("cargo", cmd_args,
               cd: project_path,
               stderr_to_stdout: true
             ) do
          {output, 0} ->
            parsed = parse_cargo_output(output)
            {:ok, parsed}

          {output, exit_code} ->
            Logger.error("Rust tests failed with exit code #{exit_code}")
            {:error,
             "Tests failed (exit #{exit_code}): #{String.trim(output) |> String.slice(0, 500)}"}
        end

      {:error, reason} ->
        {:error, "Cannot locate Rust project: #{reason}"}
    end
  end

  @doc "Generates coverage report via cargo tarpaulin."
  @spec coverage() :: {:ok, map()} | {:error, String.t()}
  def coverage do
    case resolve_cargo_project_path() do
      {:ok, project_path} ->
        # Check if cargo-tarpaulin is available
        case System.cmd("cargo", ["tarpaulin", "--version"],
               cd: project_path,
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            cmd_args = [
              "tarpaulin",
              "--out",
              "Xml",
              "--out",
              "Html",
              "--engine",
              "llvm",
              "--follow-tests",
              "--timeout",
              "120"
            ]

            case System.cmd("cargo", cmd_args,
                   cd: project_path, stderr_to_stdout: true
                 ) do
              {output, 0} ->
                coverage = parse_coverage_output(output)
                {:ok, coverage}

              {output, exit_code} ->
                {:error,
                 "Coverage failed (exit #{exit_code}): #{String.trim(output) |> String.slice(0, 500)}"}
            end

          {_output, _exit_code} ->
            {:error, "cargo-tarpaulin not found (run: cargo install cargo-tarpaulin)"}
        end

      {:error, reason} ->
        {:error, "Cannot locate Rust project: #{reason}"}
    end
  end

  @doc """
  Resolves the path to the Rust Cargo project within the Lux repository.

  Searches common locations for Cargo.toml:
  - lux/rust/ (subcrate)
  - priv/rust/ (priv Rust project)
  - . (repository root)

  Returns {:ok, path} if found, {:error, reason} otherwise.
  """
  @spec resolve_cargo_project_path() :: {:ok, String.t()} | {:error, String.t()}
  def resolve_cargo_project_path do
    # Try common Rust project locations within the Lux repo
    candidates = [
      Path.join(__DIR__, "../../rust"),
      Path.join(__DIR__, "../../../priv/rust"),
      Path.join(__DIR__, "../../../..")
    ]

    Enum.find_value(candidates, {:error, "No Cargo.toml found in expected locations"}) do
      path ->
        cargo_toml = Path.join(path, "Cargo.toml")
        if File.exists?(cargo_toml), do: {:ok, path}, else: nil
    end
  end

  @doc """
  Parses standard `cargo test` output.

  Matches patterns like:
    `test result: ok. 42 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.12s`
  """
  @spec parse_cargo_output(String.t()) :: map()
  def parse_cargo_output(output) do
    # Standard cargo test result line: "test result: ok. N passed; M failed; ..."
    result_match =
      Regex.run(
        ~r/test result: (ok|FAILED)\.\s+(\d+) passed;\s+(\d+) failed/,
        output
      )

    passed =
      case result_match do
        [_, _, passed_str, _] -> String.to_integer(passed_str)
        nil -> 0
      end

    failed =
      case result_match do
        [_, _, _, failed_str] -> String.to_integer(failed_str)
        nil -> 0
      end

    # Duration: "finished in Xs" or "finished in Xm Ys"
    duration =
      Regex.run(~r/finished in ([\d.]+)s/, output)
      |> then(fn
        [_, d] -> d
        _ -> "unknown"
      end)

    %{
      tests_passed: passed,
      tests_failed: failed,
      duration: duration,
      output: String.trim(output)
    }
  end

  @doc """
  Parses cargo-tarpaulin coverage output.

  Matches patterns like:
    `Coverage : 85.7% (120/140 lines)`
  """
  @spec parse_coverage_output(String.t()) :: map()
  def parse_coverage_output(output) do
    # Try standard tarpaulin coverage percentage pattern
    coverage_pct =
      Regex.run(~r/Coverage\s*:\s*([\d.]+)%/, output)
      |> then(fn
        [_, pct] -> String.to_float(pct)
        _ -> 0.0
      end)

    %{
      coverage_percentage: coverage_pct,
      output: String.trim(output)
    }
  end

  @doc "Returns a test summary map."
  @spec summary(map()) :: map()
  def summary(results) do
    passed = Map.get(results, :tests_passed, 0)
    failed = Map.get(results, :tests_failed, 0)
    total = passed + failed

    %{
      total: total,
      passed: passed,
      failed: failed,
      duration: Map.get(results, :duration, "unknown"),
      coverage: "Run RustTestRunner.coverage() for coverage data"
    }
  end

  @doc "Creates a test fixture for Rust integration testing."
  @spec create_fixture(String.t(), map()) :: :ok
  def create_fixture(name, data \\ %{}) do
    fixture_dir = Path.join([:code.priv_dir(:lux), "rust_test_fixtures"])

    case File.mkdir_p(fixture_dir) do
      :ok ->
        fixture_file = Path.join(fixture_dir, "#{name}.json")
        File.write!(fixture_file, Jason.encode!(data, pretty: true))
        :ok

      {:error, reason} ->
        Logger.error("Failed to create fixture directory: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Loads a test fixture by name."
  @spec load_fixture(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load_fixture(name) do
    fixture_dir = :code.priv_dir(:lux)

    fixture_file =
      case fixture_dir do
        {:error, _} ->
          Path.join(["rust_test_fixtures", "#{name}.json"])

        path ->
          Path.join([path, "rust_test_fixtures", "#{name}.json"])
      end

    case File.read(fixture_file) do
      {:ok, content} -> {:ok, Jason.decode!(content)}
      {:error, _} -> {:error, "Fixture not found: #{name}"}
    end
  end

  @doc "Returns cross-language test utility function names."
  @spec test_utils() :: [atom()]
  def test_utils do
    [:assert_exit_code_zero, :assert_test_output_contains, :assert_no_failures]
  end

  @doc """
  Asserts that the test result indicates zero failures.

  Returns true only when all tests passed.
  """
  @spec assert_exit_code_zero({:ok, map()} | {:error, String.t()}) :: boolean()
  def assert_exit_code_zero({:ok, %{tests_failed: 0}}), do: true
  def assert_exit_code_zero(_result), do: false

  @doc """
  Checks if test output contains expected patterns.

  Validates that captured test output includes the given expected substring.
  Returns true if the pattern is found, false otherwise.
  """
  @spec assert_test_output_contains({String.t(), integer(), String.t()}) :: boolean()
  def assert_test_output_contains({output, exit_code, expected}) do
    exit_code == 0 and String.contains?(to_string(output), expected)
  end

  @doc """
  Asserts that no test failures were detected.

  Combines exit code and test result validation.
  """
  @spec assert_no_failures({:ok, map()} | {:error, String.t()}) :: boolean()
  def assert_no_failures({:ok, %{tests_failed: 0, tests_passed: n}}) when n > 0, do: true
  def assert_no_failures(_result), do: false
end
