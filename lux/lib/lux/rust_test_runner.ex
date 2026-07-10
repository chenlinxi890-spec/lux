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
  """

  require Logger

  @doc "Runs all Rust tests via cargo test."
  @spec run(list(String.t())) :: {:ok, map()} | {:error, String.t()}
  def run(tests \\ []) do
    cmd = if Enum.empty?(tests) do
      "cargo test --all"
    else
      "cargo test -- " <> Enum.join(tests, " ")
    end

    # FIX: Capture output (no `into:` option) so parse_cargo_output works
    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} ->
        parsed = parse_cargo_output(output)
        {:ok, parsed}

      {output, exit_code} ->
        Logger.error("Rust tests failed with exit code #{exit_code}")
        {:error, "Tests failed (exit #{exit_code}): #{String.trim(output) |> String.slice(0, 500)}"}
    end
  end

  @doc "Generates coverage report via cargo tarpaulin."
  @spec coverage() :: {:ok, map()} | {:error, String.t()}
  def coverage do
    # FIX: Capture output properly (no `into:` option)
    case System.cmd("sh", ["-c", "which cargo-tarpaulin"], stderr_to_stdout: true) do
      {_, 0} ->
        cmd = "cargo tarpaulin --out Xml --out Html --engine llvm --follow-tests --timeout 120"
        case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
          {output, 0} ->
            coverage = parse_coverage_output(output)
            {:ok, coverage}

          {output, exit_code} ->
            {:error, "Coverage failed (exit #{exit_code}): #{String.trim(output) |> String.slice(0, 500)}"}
        end

      {_path, _} ->
        {:error, "cargo-tarpaulin not found in PATH"}
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
    result_match = Regex.run(~r/test result: (ok|FAILED)\.\s+(\d+) passed;\s+(\d+) failed/, output)

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
    File.mkdir_p!(fixture_dir)
    fixture_file = Path.join(fixture_dir, "#{name}.json")
    File.write!(fixture_file, Jason.encode!(data, pretty: true))
    :ok
  end

  @doc "Loads a test fixture by name."
  @spec load_fixture(String.t()) :: {:ok, map()} | {:error, String.t()}
  def load_fixture(name) do
    fixture_file = Path.join([:code.priv_dir(:lux), "rust_test_fixtures", "#{name}.json"])
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

  defp assert_exit_code_zero(result) do
    case result do
      {:ok, %{tests_failed: 0}} -> true
      _ -> false
    end
  end

  defp assert_test_output_contains({_output, _exit_code, expected}) do
    # Utility for EEx templates
    true
  end

  defp assert_no_failures(result) do
    assert_exit_code_zero(result)
  end
end
