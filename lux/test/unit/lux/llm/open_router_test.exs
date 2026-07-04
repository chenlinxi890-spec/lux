defmodule Lux.LLM.OpenRouterTest do
  use ExUnit.Case, async: true
  alias Lux.LLM.OpenRouter

  setup do
    OpenRouter.clear_cost_tracking()
    :ok
  end

  describe "call/2" do
    test "makes successful API call and returns response" do
      System.put_env("OPENROUTER_API_KEY", "test-key")
      on_exit(fn -> System.delete_env("OPENROUTER_API_KEY") end)

      MockReq.stub(:post, fn %{url: url} ->
        if String.contains?(url, "openrouter.ai") do
          {:ok, %MockReq.Response{
            status: 200,
            body: %{
              "choices" => [%{"message" => %{"content" => "Hello from OpenRouter!"}}],
              "usage" => %{prompt_tokens: 5, completion_tokens: 10, total_tokens: 15},
              "model" => "meta-llama/llama-3.3-70b-instruct:free"
            }
          }}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, response} = OpenRouter.call("Test prompt", %{})
      assert response.content == "Hello from OpenRouter!"
      assert response.model == "meta-llama/llama-3.3-70b-instruct:free"
      assert response.provider == :openrouter
    end

    test "raises when API key is not configured" do
      System.delete_env("OPENROUTER_API_KEY")
      assert_raise ArgumentError, fn ->
        OpenRouter.call("test", %{})
      end
    end

    test "handles rate limiting with retry" do
      System.put_env("OPENROUTER_API_KEY", "test-key")
      on_exit(fn -> System.delete_env("OPENROUTER_API_KEY") end)

      call_count = ref_count()
      MockReq.stub(:post, fn %{url: url} ->
        if String.contains?(url, "openrouter.ai") do
          cond do
            call_count.value < 2 ->
              call_count.value = call_count.value + 1
              {:ok, %MockReq.Response{status: 429, body: %{}}}
            true ->
              {:ok, %MockReq.Response{
                status: 200,
                body: %{"choices" => [%{"message" => %{"content" => "retry succeeded"}}], "usage" => %{}, "model" => "test"}
              }}
          end
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, response} = OpenRouter.call("retry test", %{})
      assert response.content == "retry succeeded"
    end

    test "tracks costs" do
      System.put_env("OPENROUTER_API_KEY", "test-key")
      on_exit(fn -> System.delete_env("OPENROUTER_API_KEY") end)

      MockReq.stub(:post, fn %{url: url} ->
        if String.contains?(url, "openrouter.ai") do
          {:ok, %MockReq.Response{
            status: 200,
            body: %{
              "choices" => [%{"message" => %{"content" => "ok"}}],
              "usage" => %{prompt_tokens: 100, completion_tokens: 200, total_tokens: 300},
              "model" => "anthropic/claude-3.5-sonnet"
            }
          }}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, _} = OpenRouter.call("cost test", %{})
      costs = OpenRouter.cost_tracking()
      assert length(costs) == 1
      assert costs |> Enum.at(0) |> Map.get(:input_tokens) == 100
      assert costs |> Enum.at(0) |> Map.get(:output_tokens) == 200
    end
  end

  describe "cost_tracking/0" do
    test "returns empty list initially" do
      assert OpenRouter.cost_tracking() == []
    end

    test "clears tracking data" do
      OpenRouter.record_cost("test", 10, 20, 0.001)
      assert length(OpenRouter.cost_tracking()) == 1
      OpenRouter.clear_cost_tracking()
      assert OpenRouter.cost_tracking() == []
    end
  end

  describe "list_models/0" do
    test "returns list of available models" do
      MockReq.stub(:get, fn %{url: url} ->
        if String.contains?(url, "openrouter.ai") and String.contains?(url, "models") do
          {:ok, %MockReq.Response{
            status: 200,
            body: %{
              "data" => [
                %{
                  "id" => "anthropic/claude-3.5-sonnet",
                  "name" => "Claude 3.5 Sonnet",
                  "context_length" => 200000,
                  "pricing" => %{"input" => "0.003", "output" => "0.015"},
                  "architecture" => %{"modality" => "text->text"}
                }
              ]
            }
          }}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, models} = OpenRouter.list_models()
      assert length(models) == 1
      assert models |> Enum.at(0) |> Map.get(:id) == "anthropic/claude-3.5-sonnet"
      assert models |> Enum.at(0) |> Map.get(:context_length) == 200000
    end
  end

  describe "select_model/1" do
    test "selects model matching criteria" do
      MockReq.stub(:get, fn %{url: url} ->
        if String.contains?(url, "models") do
          {:ok, %MockReq.Response{
            status: 200,
            body: %{
              "data" => [
                %{"id" => "cheap-model", "context_length" => 4000, "pricing" => %{"input" => "0.0001"}},
                %{"id" => "expensive-model", "context_length" => 128000, "pricing" => %{"input" => "0.003"}},
                %{"id" => "long-context-model", "context_length" => 1000000, "pricing" => %{"input" => "0.001"}}
              ]
            }
          }}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, model} = OpenRouter.select_model(min_context: 100000)
      assert model in ["expensive-model", "long-context-model"]
    end

    test "returns error when no matching model" do
      MockReq.stub(:get, fn %{url: url} ->
        if String.contains?(url, "models") do
          {:ok, %MockReq.Response{
            status: 200,
            body: %{"data" => [%{"id" => "small", "context_length" => 100, "pricing" => %{"input" => "0.001"}}]}
          }}
        else
          {:error, :not_found}
        end
      end)

      assert {:error, :no_matching_model} = OpenRouter.select_model(min_context: 100000)
    end
  end

  # Helper for mutable counter
  defp ref_count do
    %{value: 0}
  end
end
