defmodule Lux.RustTestRunnerTest do
  use ExUnit.Case, async: true

  doctest Lux.RustTestRunner

  describe "test_utils" do
    test "returns expected utility function names" do
      utils = Lux.RustTestRunner.test_utils()
      assert :assert_exit_code_zero in utils
      assert :assert_test_output_contains in utils
      assert :assert_no_failures in utils
    end
  end

  describe "create_fixture / load_fixture" do
    setup do
      on_exit fn ->
        fixture_file = Path.join([:code.priv_dir(:lux), "rust_test_fixtures", "test_fixture.json"])
        if File.exists?(fixture_file), do: File.rm!(fixture_file)
      end
    end

    test "creates and loads a fixture", _ do
      Lux.RustTestRunner.create_fixture("test_fixture", %{name: "test", value: 42})
      assert {:ok, %{name: "test", value: 42}} = Lux.RustTestRunner.load_fixture("test_fixture")
    end

    test "returns error for non-existent fixture", _ do
      assert {:error, _} = Lux.RustTestRunner.load_fixture("nonexistent")
    end
  end

  describe "summary" do
    test "returns correct summary from results" do
      results = %{tests_passed: 10, tests_failed: 2, duration: "1.5s"}
      summary = Lux.RustTestRunner.summary(results)
      assert summary.total == 12
      assert summary.passed == 10
      assert summary.failed == 2
      assert summary.duration == "1.5s"
    end
  end

  describe "parse_cargo_output" do
    test "parses standard cargo test success output" do
      output = """
      running 42 tests
      test result: ok. 42 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.12s
      """

      result = Lux.RustTestRunner.parse_cargo_output(output)
      assert result.tests_passed == 42
      assert result.tests_failed == 0
      assert result.duration == "0.12"
    end

    test "parses cargo test with failures" do
      output = """
      running 10 tests
      test result: FAILED. 7 passed; 3 failed; 0 ignored; 0 measured; 0 filtered out; finished in 1.23s
      """

      result = Lux.RustTestRunner.parse_cargo_output(output)
      assert result.tests_passed == 7
      assert result.tests_failed == 3
      assert result.duration == "1.23"
    end

    test "handles empty output gracefully" do
      result = Lux.RustTestRunner.parse_cargo_output("")
      assert result.tests_passed == 0
      assert result.tests_failed == 0
      assert result.duration == "unknown"
    end
  end

  describe "parse_coverage_output" do
    test "parses tarpaulin coverage percentage" do
      output = """
      [tarpaulin] Coverage Results:
      Coverage : 85.7% (120/140 lines)
      """

      result = Lux.RustTestRunner.parse_coverage_output(output)
      assert result.coverage_percentage == 85.7
    end

    test "handles missing coverage data" do
      result = Lux.RustTestRunner.parse_coverage_output("")
      assert result.coverage_percentage == 0.0
    end
  end
end
