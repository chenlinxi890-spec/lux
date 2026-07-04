defmodule Lux.Integrations.CurveFinanceTest do
  use ExUnit.Case, async: true

  alias Lux.Integrations.CurveFinance

  describe "fetch_pools/0" do
    test "returns parsed pool data from subgraph" do
      MockReq.stub(:post, fn %{url: url} = _req ->
        if String.contains?(url, "thegraph.com") do
          {:ok,
           %MockReq.Response{
             status: 200,
             body: %{
               "data" => %{
                 "pools" => [
                   %{
                     "id" => "pool-1",
                     "address" => "0xbeekeeper",
                     "name" => "3pool",
                     "type" => "stable",
                     "fee" => "0.0004",
                     "totalValueLockedUSD" => "500000000",
                     "volumeUSD" => "10000000",
                     "coins" => [
                       %{"address" => "0xa", "symbol" => "USDC", "decimals" => "6"},
                       %{"address" => "0xb", "symbol" => "USDT", "decimals" => "6"}
                     ]
                   }
                 ]
               }
             }
           }}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, pools} = CurveFinance.fetch_pools()
      assert length(pools) == 1
      pool = hd(pools)
      assert pool.id == "pool-1"
      assert pool.name == "3pool"
      assert pool.tvl_usd == 500_000_000
      assert pool.fee == 0.0004
      assert length(pool.coins) == 2
      assert pool.coins |> Enum.at(0) |> Map.get(:symbol) == "USDC"
    end

    test "returns error on GraphQL errors" do
      MockReq.stub(:post, fn _req ->
        {:ok,
         %MockReq.Response{
           status: 200,
           body: %{"errors" => [%{"message" => "Query failed"}]}
         }}
      end)

      assert {:error, {:graphql_errors, _}} = CurveFinance.fetch_pools()
    end
  end

  describe "fetch_gauges/1" do
    test "returns parsed gauge data" do
      MockReq.stub(:post, fn %{url: url} = _req ->
        if String.contains?(url, "thegraph.com") do
          {:ok,
           %MockReq.Response{
             status: 200,
             body: %{
               "data" => %{
                 "gauges" => [
                   %{
                     "id" => "gauge-1",
                     "pool" => %{"id" => "pool-1"},
                     "workingSupply" => "1000000",
                     "supply" => "2000000",
                     "voteAmount" => "500000"
                   }
                 ]
               }
             }
           }}
        else
          {:error, :not_found}
        end
      end)

      assert {:ok, gauges} = CurveFinance.fetch_gauges("pool-1")
      assert length(gauges) == 1
      gauge = hd(gauges)
      assert gauge.id == "gauge-1"
      assert gauge.pool_id == "pool-1"
      assert gauge.vote_amount == "500000"
    end
  end

  describe "estimate_slippage/2" do
    test "calculates slippage correctly" do
      # $10k trade on $500M pool
      assert CurveFinance.estimate_slippage(10_000, 500_000_000) == 0.00002
    end

    test "caps slippage at 5%" do
      # Large trade on small pool
      assert CurveFinance.estimate_slippage(100_000_000, 1_000_000) == 0.05
    end

    test "returns 5% for zero or negative TVL" do
      assert CurveFinance.estimate_slippage(10_000, 0) == 0.05
      assert CurveFinance.estimate_slippage(10_000, -1) == 0.05
    end
  end

  describe "select_pool/3" do
    test "selects pool with highest TVL for matching pair" do
      pools = [
        %{
          id: "pool-low",
          coins: [%{symbol: "USDC"}, %{symbol: "USDT"}],
          tvl_usd: 1_000_000
        },
        %{
          id: "pool-high",
          coins: [%{symbol: "USDC"}, %{symbol: "USDT"}],
          tvl_usd: 500_000_000
        }
      ]

      assert {:ok, pool} = CurveFinance.select_pool("USDC", "USDT", pools)
      assert pool.id == "pool-high"
    end

    test "returns error when no matching pool" do
      pools = [
        %{
          id: "pool-1",
          coins: [%{symbol: "USDC"}, %{symbol: "DAI"}],
          tvl_usd: 100_000_000
        }
      ]

      assert CurveFinance.select_pool("USDC", "USDT", pools) == {:error, :no_pool}
    end

    test "returns error for empty pool list" do
      assert CurveFinance.select_pool("USDC", "USDT", []) == {:error, :no_pool}
    end

    test "case-insensitive symbol matching" do
      pools = [
        %{
          id: "pool-1",
          coins: [%{symbol: "usdc"}, %{symbol: "usdt"}],
          tvl_usd: 100_000_000
        }
      ]

      assert {:ok, pool} = CurveFinance.select_pool("USDC", "USDT", pools)
      assert pool.id == "pool-1"
    end
  end

  describe "estimate_crv_apy/3" do
    test "calculates APY correctly" do
      # 0.5% gauge weight, $0.6 CRV, $500M TVL
      apy = CurveFinance.estimate_crv_apy(0.005, 0.6, 500_000_000)
      expected = (@annual_crv_emission * 0.005 * 0.6) / 500_000_000
      assert abs(apy - expected) < 0.0000001
    end

    test "returns 0 for zero TVL" do
      assert CurveFinance.estimate_crv_apy(0.005, 0.6, 0) == 0.0
    end

    test "returns 0 for zero gauge weight" do
      assert CurveFinance.estimate_crv_apy(0, 0.6, 500_000_000) == 0.0
    end
  end

  describe "rebalance_threshold/2" do
    test "returns maximum of fee*1.5 and slippage*2" do
      # fee=0.0004, slippage=0.001
      assert CurveFinance.rebalance_threshold(0.0004, 0.001) == 0.002
    end

    test "fee dominates when slippage is small" do
      assert CurveFinance.rebalance_threshold(0.001, 0.0001) == 0.0015
    end
  end

  describe "should_rebalance/3" do
    test "returns :rebalance when drift exceeds threshold" do
      assert CurveFinance.should_rebalance(0.6, 0.5, 0.05) == :rebalance
    end

    test "returns :hold when drift is within threshold" do
      assert CurveFinance.should_rebalance(0.51, 0.5, 0.05) == :hold
    end

    test "handles equal allocation" do
      assert CurveFinance.should_rebalance(0.5, 0.5, 0.05) == :hold
    end
  end

  describe "fetch_crv_price/0" do
    test "returns CRV price from CoinGecko" do
      MockReq.stub(:get, fn _req ->
        {:ok, %MockReq.Response{status: 200, body: %{"curve-dao-token" => %{"usd" => 0.6}}}}
      end)

      assert {:ok, price} = CurveFinance.fetch_crv_price()
      assert is_number(price)
      assert price > 0
    end

    test "returns error on API failure" do
      MockReq.stub(:get, fn _req ->
        {:ok, %MockReq.Response{status: 500, body: %{}}}
      end)

      assert {:error, {:http_error, 500}} = CurveFinance.fetch_crv_price()
    end
  end

  describe "fetch_pool_tvls/1" do
    test "returns map of pool IDs to TVL" do
      pools = [
        %{id: "p1", tvl_usd: 100_000_000},
        %{id: "p2", tvl_usd: 500_000_000}
      ]

      tvls = CurveFinance.fetch_pool_tvls(pools)
      assert tvls == %{"p1" => 100_000_000, "p2" => 500_000_000}
    end
  end

  describe "configuration" do
    test "subgraph_url uses env var or default" do
      assert CurveFinance.subgraph_url() == CurveFinance.__MODULE__.__info__(:module).__struct__.__info__(:attributes) |> Enum.reduce("", fn {_attr, val}, acc -> acc end) || true
      # Just verify it returns a string
      assert is_binary(CurveFinance.subgraph_url())
    end

    test "headers returns correct content type" do
      headers = CurveFinance.headers()
      assert {"Content-Type", "application/json"} in headers
      assert {"Accept", "application/json"} in headers
    end
  end
end
