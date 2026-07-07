defmodule Lux.LLM.OllamaTest do
  use ExUnit.Case, async: true

  describe "Config defaults" do
    test "has correct default endpoint" do
      assert Lux.LLM.Ollama.default_endpoint() == "http://localhost:11434"
    end

    test "has correct default model" do
      assert Lux.LLM.Ollama.default_model() == "llama3.3"
    end
  end

  describe "performance metrics" do
    setup do
      Lux.LLM.Ollama.clear_performance_metrics()
    end

    test "records and retrieves perf metrics" do
      Lux.LLM.Ollama.record_perf("llama3.3", 100, 200, 5000)
      metrics = Lux.LLM.Ollama.performance_metrics()
      assert length(metrics) == 1
      assert hd(metrics).model == "llama3.3"
      assert hd(metrics).prompt_tokens == 100
      assert hd(metrics).output_tokens == 200
      assert hd(metrics).duration_ms == 5000
    end

    test "perf_summary returns correct averages" do
      Lux.LLM.Ollama.record_perf("llama3.3", 100, 200, 5000)
      Lux.LLM.Ollama.record_perf("llama3.3", 200, 300, 3000)
      summary = Lux.LLM.Ollama.perf_summary()
      assert summary.total_requests == 2
      assert summary.avg_duration_ms == 4000.0
      assert summary.avg_prompt_tokens == 150.0
      assert summary.avg_output_tokens == 250.0
    end

    test "perf_summary returns zeros when empty" do
      summary = Lux.LLM.Ollama.perf_summary()
      assert summary.total_requests == 0
      assert summary.avg_duration_ms == 0
    end
  end

  describe "health_check" do
    test "returns error when Ollama is not running" do
      result = Lux.LLM.Ollama.health_check()
      assert {:error, _} = result
    end
  end
end