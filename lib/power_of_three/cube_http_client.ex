defmodule PowerOfThree.CubeHttpClient do
  @moduledoc """
  HTTP client for querying the Cube REST API.

  Provides an alternative to ADBC for environments where the native driver
  is not available. Uses the Cube REST API at `/cubejs-api/v1/load`.

  ## Usage

      # Create a client
      {:ok, client} = PowerOfThree.CubeHttpClient.new(
        base_url: "http://localhost:4008",
        api_token: "test"
      )

      # Execute a query
      cube_query = %{
        "dimensions" => ["of_customers.brand"],
        "measures" => ["of_customers.count"],
        "limit" => 10
      }

      {:ok, result} = PowerOfThree.CubeHttpClient.query(client, cube_query)
      # Returns columnar data: %{"of_customers.brand" => [...], "of_customers.count" => [...]}

  ## Configuration

  - `:base_url` - Cube server URL (required, e.g., "http://localhost:4008")
  - `:api_token` - Authentication token (optional)
  - `:timeout` - Request timeout in milliseconds (default: 30_000)
  - `:retry` - Retry configuration (default: no retries)

  ## Response Format

  The Cube API returns row-oriented data, which this module transforms to
  columnar format (matching ADBC output):

      # Cube API response:
      %{"data" => [
        %{"of_customers.brand" => "NIKE", "of_customers.count" => "42"},
        %{"of_customers.brand" => "Adidas", "of_customers.count" => "38"}
      ]}

      # Transformed output:
      %{
        "of_customers.brand" => ["NIKE", "Adidas"],
        "of_customers.count" => [42, 38]  # Type-converted from strings
      }

  ## Type Conversion

  All values in the Cube API response are strings. This module uses the
  `annotation` metadata to convert values to proper types:

  - `type: "number"` → integer or float
  - `type: "string"` → string (unchanged)
  - `type: "boolean"` → boolean
  - `type: "time"` → DateTime or Date
  """

  require Explorer.DataFrame
  alias PowerOfThree.QueryError

  @enforce_keys [:req]
  defstruct [:req, :base_url, :api_token]

  @type t :: %__MODULE__{
          req: Req.Request.t(),
          base_url: String.t(),
          api_token: String.t() | nil
        }

  @doc """
  Creates a new HTTP client for the Cube API.

  ## Options

  - `:base_url` - Cube server URL (required)
  - `:api_token` - Authentication token (optional)
  - `:timeout` - Request timeout in ms (default: 30_000)
  - `:retry` - Retry options (default: no retries)

  ## Examples

      iex> PowerOfThree.CubeHttpClient.new(base_url: "http://localhost:4008")
      {:ok, %PowerOfThree.CubeHttpClient{...}}

      iex> PowerOfThree.CubeHttpClient.new(base_url: "http://localhost:4008", api_token: "secret", timeout: 60_000)
      {:ok, %PowerOfThree.CubeHttpClient{...}}
  """
  def new(opts \\ []) do
    base_url = Keyword.get(opts, :base_url, "http://localhost:4008")
    api_token = Keyword.get(opts, :api_token)
    timeout = Keyword.get(opts, :timeout, 30_000)

    req_opts = [
      base_url: base_url,
      receive_timeout: timeout
    ]

    req_opts =
      if api_token do
        Keyword.put(req_opts, :auth, {:bearer, api_token})
      else
        req_opts
      end

    req_opts =
      req_opts
      |> Keyword.put(:headers, [{:accept, "application/x-ndjson"}])

    req = Req.new(req_opts)

    {:ok,
     %__MODULE__{
       req: req,
       base_url: base_url,
       api_token: api_token
     }}
  rescue
    error ->
      {:error, QueryError.connection_error("Failed to create HTTP client", error)}
  end

  @doc """
  Creates a new HTTP client, raising on error.

  See `new/1` for options.
  """
  def new!(opts \\ []) do
    case new(opts) do
      {:ok, client} -> client
      {:error, error} -> raise error.message
    end
  end

  @doc """
  Executes a Cube Query and returns columnar result data.

  ## Parameters

  - `client` - The CubeHttpClient struct
  - `cube_query` - Map representing the Cube Query JSON format

  ## Returns

  - `{:ok, result_map}` - Columnar data where keys are field names and values are lists
  - `{:error, %QueryError{}}` - Error details

  ## Examples

      iex> cube_query = %{
      ...>   "dimensions" => ["of_customers.brand"],
      ...>   "measures" => ["of_customers.count"],
      ...>   "limit" => 5
      ...> }
      iex> PowerOfThree.CubeHttpClient.query(client, cube_query)
      {:ok, %{
        "of_customers.brand" => ["NIKE", "Adidas", "Puma"],
        "of_customers.count" => [42, 38, 25]
      }}
  """
  def query(client, cube_query) do
    request_body = %{"query" => cube_query}

    case Req.post(client.req, url: "/cubejs-api/v1/load", json: request_body) do
      {:ok, %{status: 200, body: body}} ->
        parse_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, QueryError.from_http_status(status, body)}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, QueryError.timeout()}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, QueryError.connection_error("Connection refused. Is the Cube server running?")}

      {:error, error} ->
        {:error, QueryError.connection_error("HTTP request failed", error)}
    end
  end

  @doc """
  Executes a Cube Query and returns arrow TODO result data.

  ## Parameters

  - `client` - The CubeHttpClient struct
  - `cube_query` - Map representing the Cube Query JSON format

  ## Returns

  - `{:ok, result_map}` - Columnar data where keys are field names and values are lists
  - `{:error, %QueryError{}}` - Error details

  ## Examples

      iex> cube_query = %{
      ...>   "dimensions" => ["of_customers.brand"],
      ...>   "measures" => ["of_customers.count"],
      ...>   "limit" => 5
      ...> }
      iex> PowerOfThree.CubeHttpClient.arrow(client, cube_query)
      {:ok, %{
        "of_customers.brand" => ["NIKE", "Adidas", "Puma"],
        "of_customers.count" => [42, 38, 25]
      }}
  """
  def arrow(client, cube_query) do
    request_body = %{"query" => cube_query}

    case Req.post(client.req, url: "/cubejs-api/v1/arrow", json: request_body) do
      {:ok, %{status: 200, body: body}} ->
        # TODO parse actual arrow ->>>------>-
        parse_response(body)

      {:ok, %{status: status, body: body}} ->
        {:error, QueryError.from_http_status(status, body)}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, QueryError.timeout()}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, QueryError.connection_error("Connection refused. Is the Cube server running?")}

      {:error, error} ->
        {:error, QueryError.connection_error("HTTP request failed", error)}
    end
  end

  @spec query!(any(), any()) :: %{
          optional(:__struct__) => Explorer.DataFrame,
          optional(:data) => struct(),
          optional(:dtypes) => %{
            optional(binary()) =>
              :binary
              | :boolean
              | :category
              | :date
              | :null
              | :string
              | :time
              | {any(), any()}
              | {any(), any(), any()}
          },
          optional(:groups) => %{columns: list(), stable?: boolean()},
          optional(:names) => [binary()],
          optional(:remote) => any()
        }
  @doc """
  Executes a Cube Query, raising on error.

  See `query/2` for details.
  """
  def query!(client, cube_query) do
    case query(client, cube_query) do
      {:ok, result} -> result
      {:error, error} -> raise error.message
    end
  end

  # Parses the Cube API JSON response and transforms it to columnar format
  defp parse_response(%{"data" => data, "annotation" => annotation}) when is_list(data) do
    case transform_to_columnar(data, annotation) do
      {:ok, result} -> {:ok, result}
      {:error, _} = error -> error
    end
  end

  defp parse_response(%{"error" => error_msg}) do
    {:error, QueryError.new(error_msg, :query_error)}
  end

  defp parse_response(_body) do
    {:error, QueryError.parse_error("Unexpected response format from Cube API")}
  end

  # Transforms row-oriented data to columnar format with type conversion
  defp transform_to_columnar([], _annotation), do: {:ok, %{}}

  defp transform_to_columnar(rows, _annotations) do
    {
      :ok,
      Explorer.DataFrame.new(rows)
      |> Explorer.DataFrame.dump_csv!(quote_style: :non_numeric)
      |> Explorer.DataFrame.load_csv!()
    }
  rescue
    error ->
      {:error, QueryError.parse_error("Failed to transform response", error)}
  end

  # Gets the type of a field from annotation metadata
  defp get_field_type(field_name, %{
         "dimensions" => dimensions,
         "measures" => measures
       }) do
    cond do
      Map.has_key?(dimensions, field_name) ->
        case dimensions[field_name]["type"] |> IO.inspect(label: :dimension_type) do
          "number" -> {:f, 64}
          _ -> :string
        end

      Map.has_key?(measures, field_name) ->
        case measures[field_name]["type"] |> IO.inspect(label: :measure_type) do
          "number" -> {:f, 64}
          _ -> :string
        end
    end
  end

  defp get_field_type(_field_name, _annotation), do: "string"
end
