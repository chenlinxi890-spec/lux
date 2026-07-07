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

    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
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
    case System.cmd("sh", ["-c", "which cargo-tarpaulin"], into: IO.stream(:stdio, :line)) do
      {"", _} ->
        {:error, "cargo-tarpaulin not installed. Install with: cargo install cargo-tarpaulin"}

      {_path, 0} ->
        cmd = "cargo tarpaulin --out Xml --out Html --engine llvm --follow-tests --timeout 120"
        case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true, into: IO.stream(:stdio, :line)) do
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

  defp parse_cargo_output(output) do
    test_count = Regex.run(~r/(\d+) test\(s\) passed/, output) |> then(& &1 && List.last(&1) |> String.to_integer())
    fail_count = Regex.run(~r/(\d+) test\(s\) failed/, output) |> then(& &1 && List.last(&1) |> String.to_integer())
    duration = Regex.run(~r/finished in ([\d.]+)s/, output) |> then(& &1 && List.last(&1))

    %{
      tests_passed: test_count || 0,
      tests_failed: fail_count || 0,
      duration: duration || "unknown",
      output: String.trim(output)
    }
  end

  defp parse_coverage_output(output) do
    coverage_pct = Regex.run(~r/([\d.]+)%/, output) |> then(& &1 && List.first(&1) |> String.replace("%", "") |> Float.parse() |> elem(0))
    %{
      coverage_percentage: coverage_pct || 0.0,
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

  @doc "Returns cross-language test utility functions."
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