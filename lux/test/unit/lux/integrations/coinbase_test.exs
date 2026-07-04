defmodule Lux.Integrations.CoinbaseTest do
  use ExUnit.Case, async: true
  alias Lux.Integrations.Coinbase

  describe "signed_headers/3" do
    test "generates valid HMAC-SHA256 signature" do
      System.put_env("COINBASE_API_KEY", "test-key")
      System.put_env("COINBASE_API_SECRET", "test-secret")
      on_exit(fn -> System.delete_env("COINBASE_API_KEY"); System.delete_env("COINBASE_API_SECRET") end)
      headers = Coinbase.signed_headers("GET", "/api/v3/brokerage/products")
      assert {"CB-ACCESS-KEY", "test-key"} in headers
      assert {"CB-ACCESS-SIGN", sign} = Enum.find(headers, fn {k, _} -> k == "CB-ACCESS-SIGN" end)
      assert sign != ""
      assert length(sign) == 64
    end
  end

  describe "products/0" do
    test "returns products from API" do
      MockReq.stub(:get, fn %{url: url} ->
        if String.contains?(url, "products") do
          {:ok, %MockReq.Response{status: 200, body: %{"products" => [%{id: "BTC-USD"}]}}}
        else
          {:error, :not_found}
        end
      end)
      assert {:ok, products} = Coinbase.products()
      assert length(products) == 1
      assert hd(products).id == "BTC-USD"
    end
  end

  describe "account_balance/1" do
    test "returns balance for existing currency" do
      MockReq.stub(:get, fn %{url: url} ->
        if String.contains?(url, "accounts") do
          {:ok, %MockReq.Response{status: 200, body: %{"accounts" => [%{currency: "BTC", balance: "1.5"}]}}}
        else
          {:error, :not_found}
        end
      end)
      assert {:ok, "1.5"} = Coinbase.account_balance("BTC")
    end
  end

  describe "health_check/0" do
    test "returns server time" do
      MockReq.stub(:get, fn %{url: url} ->
        if String.contains?(url, "time") do
          {:ok, %MockReq.Response{status: 200, body: %{iso: "2026-07-04T00:00:00Z", epoch: 1751577600}}}
        else
          {:error, :not_found}
        end
      end)
      assert {:ok, time} = Coinbase.health_check()
      assert time.iso == "2026-07-04T00:00:00Z"
    end
  end

  describe "endpoint helpers" do
    test "base_url returns correct URL" do
      assert Coinbase.base_url() == "https://api.coinbase.com"
    end
    test "ws_url returns websocket URL" do
      assert Coinbase.ws_url() == "wss://advanced-trade-ws.coinbase.com"
    end
    test "products_url includes correct path" do
      assert Coinbase.products_url() == "https://api.coinbase.com/api/v3/brokerage/products"
    end
  end

  describe "rate_limit_delay/1" do
    test "parses seconds correctly" do
      assert Coinbase.rate_limit_delay("5") == 5000
    end
    test "defaults to 1000ms on parse error" do
      assert Coinbase.rate_limit_delay("invalid") == 1000
    end
  end
end
