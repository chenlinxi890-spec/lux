
  @doc "Returns the Coinbase API base URL."
  @spec base_url() :: String.t()
  def base_url, do: @base_url

  @doc "Returns the Coinbase WebSocket URL for advanced trade."
  @spec ws_url() :: String.t()
  def ws_url, do: @ws_url

  @doc "Returns the API version header value."
  @spec api_version() :: String.t()
  def api_version, do: @api_version

  @doc "Returns the configured API key."
  @spec api_key() :: String.t()
  def api_key do
    Application.get_env(:lux, __MODULE__, [])[:api_key] ||
      System.get_env("COINBASE_API_KEY") || ""
  end

  @doc "Returns the configured API secret."
  @spec api_secret() :: String.t()
  def api_secret do
    Application.get_env(:lux, __MODULE__, [])[:api_secret] ||
      System.get_env("COINBASE_API_SECRET") || ""
  end

  @doc """
  Builds signed headers for Coinbase Advanced Trade API requests.
  Implements HMAC-SHA256 signature as required by Coinbase.
  """
  @spec signed_headers(method :: String.t(), path :: String.t(), body :: String.t()) :: list({String.t(), String.t()})
  def signed_headers(method, path, body \\ "") do
    timestamp = to_string(System.system_time(:second))
    secret = api_secret()
    message = timestamp <> String.upcase(method) <> path <> body
    signature = :crypto.mac(:hmac, :sha256, secret, message) |> Base.encode16(case: :lower)
    [
      {"CB-ACCESS-KEY", api_key()},
      {"CB-ACCESS-SIGN", signature},
      {"CB-ACCESS-TIMESTAMP", timestamp},
      {"CB-VERSION", @api_version},
      {"Content-Type", "application/json"}
    ]
  end

  @doc "Products endpoint URL."
  @spec products_url() :: String.t()
  def products_url, do: @base_url <> "/api/v3/brokerage/products"

  @doc "Single product endpoint URL."
  @spec product_url(product_id :: String.t()) :: String.t()
  def product_url(product_id), do: @base_url <> "/api/v3/brokerage/products/#{product_id}"

  @doc "Order book endpoint URL."
  @spec order_book_url(product_id :: String.t()) :: String.t()
  def order_book_url(product_id), do: @base_url <> "/api/v3/brokerage/product_book?product_id=#{product_id}"

  @doc "Create order endpoint URL."
  @spec create_order_url() :: String.t()
  def create_order_url, do: @base_url <> "/api/v3/brokerage/orders"

  @doc "Batch cancel orders endpoint URL."
  @spec cancel_orders_url() :: String.t()
  def cancel_orders_url, do: @base_url <> "/api/v3/brokerage/orders/batch_cancel"

  @doc "Historical orders endpoint URL."
  @spec list_orders_url() :: String.t()
  def list_orders_url, do: @base_url <> "/api/v3/brokerage/orders/historical/batch"

  @doc "Accounts endpoint URL."
  @spec accounts_url() :: String.t()
  def accounts_url, do: @base_url <> "/api/v3/brokerage/accounts"

  @doc "Candles endpoint URL."
  @spec candles_url(pid :: String.t(), start :: String.t(), end_t :: String.t(), gran :: String.t()) :: String.t()
  def candles_url(product_id, start, end_t, gran \\ "ONE_HOUR") do
    @base_url <> "/api/v3/brokerage/products/#{product_id}/candles?start=#{start}&end=#{end_t}&granularity=#{gran}"
  end

  @doc "Portfolio endpoint URL."
  @spec portfolio_url() :: String.t()
  def portfolio_url, do: @base_url <> "/api/v3/brokerage/portfolio"

  @doc "Time endpoint URL for API health check."
  @spec time_url() :: String.t()
  def time_url, do: @base_url <> "/api/v3/brokerage/time"

  @doc """
  Fetches all available trading products.
  Returns `{:ok, [map()]}` on success.
  """
  @spec products() :: {:ok, [map()]} | {:error, term()}
  def products do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(products_url(), headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"products" => prod_list}}} -> {:ok, prod_list}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches a single product by ID.
  """
  @spec product(product_id :: String.t()) :: {:ok, map()} | {:error, term()}
  def product(product_id) do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(product_url(product_id), headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: p}} -> {:ok, p}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches the order book for a product.
  """
  @spec order_book(product_id :: String.t(), level :: integer()) :: {:ok, map()} | {:error, term()}
  def order_book(product_id, level \\ 1) do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(order_book_url(product_id), query: [level: level], headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: book}} -> {:ok, book}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Places a new order.
  Parameters: product_id, side (:buy/:sell), size, order_type (:market/:limit/:stop), price (for limit), opts.
  """
  @spec place_order(pid :: String.t(), side :: :buy | :sell, size :: String.t(), order_type :: :market | :limit | :stop, price :: float() | nil, opts :: keyword()) :: {:ok, map()} | {:error, term()}
  def place_order(product_id, side, size, order_type, price \\ nil, opts \\ []) do
    body = %{
      client_order_id: generate_client_order_id(),
      product_id: product_id,
      side: to_string(side),
      order_configuration: build_order_config(order_type, price, opts)
    }
    sig_body = Jason.encode!(body)
    headers = signed_headers("POST", "/api/v3/brokerage/orders", sig_body)
    case Req.post(create_order_url(), json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: resp}} -> {:ok, resp}
      {:ok, %{status: 400, body: %{"errors" => errs}}} -> {:error, {:validation_error, errs}}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels a single order by order ID.
  """
  @spec cancel_order(order_id :: String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_order(order_id) do
    body = %{order_ids: [order_id], client_order_id: generate_client_order_id()}
    sig_body = Jason.encode!(body)
    headers = signed_headers("DELETE", "/api/v3/brokerage/orders/batch_cancel", sig_body)
    case Req.post(cancel_orders_url(), json: body, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: resp}} -> {:ok, resp}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists historical orders with optional filtering.
  """
  @spec list_orders(opts :: keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_orders(opts \\ []) do
    query = opts |> Enum.reject(&is_nil(elem(&1, 1))) |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)
    headers = [{"Content-Type", "application/json"}]
    case Req.get(list_orders_url(), query: query, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"orders" => orders}}} -> {:ok, orders}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches account information and balances.
  """
  @spec accounts() :: {:ok, [map()]} | {:error, term()}
  def accounts do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(accounts_url(), headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"accounts" => acc}}} -> {:ok, acc}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches the balance for a specific currency.
  """
  @spec account_balance(currency :: String.t()) :: {:ok, String.t()} | {:error, term()}
  def account_balance(currency) do
    case accounts() do
      {:ok, acc_list} ->
        case Enum.find(acc_list, fn acc -> Map.get(acc, "currency", "") == currency end) do
          nil -> {:error, :not_found}
          acc -> {:ok, Map.get(acc, "balance", "0")}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches portfolio summary.
  """
  @spec portfolio() :: {:ok, map()} | {:error, term()}
  def portfolio do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(portfolio_url(), headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: portfolio}} -> {:ok, portfolio}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches candlestick data for a product.
  """
  @spec candles(pid :: String.t(), start :: String.t(), end_t :: String.t(), gran :: String.t()) :: {:ok, [map()]} | {:error, term()}
  def candles(product_id, start, end_t, gran \\ "ONE_HOUR") do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(candles_url(product_id, start, end_t, gran), query: [granularity: gran], headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: %{"candles" => cl}}} ->
        parsed = Enum.map(cl, fn [ts, low, high, open, close, vol] ->
          %{started_at: ts, low: pf(low), high: pf(high), open: pf(open), close: pf(close), volume: pf(vol)}
        end)
        {:ok, parsed}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks API health by fetching server time.
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    headers = [{"Content-Type", "application/json"}]
    case Req.get(time_url(), headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: td}} -> {:ok, td}
      {:ok, %{status: s}} -> {:error, {:http_error, s}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that API credentials are configured and reachable.
  """
  @spec validate_credentials() :: :ok | {:error, term()}
  def validate_credentials do
    ak = api_key(); sk = api_secret()
    cond do
      ak == "" -> {:error, :missing_api_key}
      sk == "" -> {:error, :missing_api_secret}
      true -> case health_check() do {:ok, _} -> :ok; {:error, _} = e -> e end
    end
  end

  @doc "Calculates rate limit retry delay from retry-after header."
  @spec rate_limit_delay(ra :: String.t()) :: integer()
  def rate_limit_delay(retry_after) do
    case Integer.parse(retry_after) do {s, _} -> s * 1000; :error -> 1000 end
  end

  # ---- Internal helpers ----

  defp generate_client_order_id do
    "#{System.unique_integer([:positive])}-lux"
  end

  defp build_order_config(:market, _price, _opts) do
    %{simple_market_market_ioc: %{}}
  end

  defp build_order_config(:limit, price, opts) when is_number(price) and price > 0 do
    post_only = Keyword.get(opts, :post_only, false)
    config = %{limit_limit_gtc: %{base_amount: "1", price: to_string(price)}}
    if post_only, do: Map.put(config.limit_limit_gtc, :post_only, true), else: config
  end

  defp build_order_config(:stop, price, _opts) when is_number(price) and price > 0 do
    %{stop_limit_gtcs: %{trigger_price: to_string(price), base_amount: "1", price: to_string(price * 0.99)}}
  end

  defp build_order_config(_type, _price, _opts) do
    %{simple_market_market_ioc: %{}}
  end

  defp pf(s) when is_binary(s), do: case Float.parse(s) do {n, _} -> n; :error -> 0.0 end
  defp pf(n) when is_number(n), do: n / 1.0
  defp pf(_), do: 0.0
end
