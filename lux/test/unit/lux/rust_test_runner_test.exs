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
    test "creates and loads a fixture" do
      Lux.RustTestRunner.create_fixture("test_fixture", %{name: "test", value: 42})
      assert {:ok, %{name: "test", value: 42}} = Lux.RustTestRunner.load_fixture("test_fixture")
    end

    test "returns error for non-existent fixture" do
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
end