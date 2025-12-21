defmodule PowerOfThree.QueryError do
  @moduledoc """
  Unified error struct for query errors across different connection types (ADBC, HTTP).

  Provides consistent error handling regardless of the underlying protocol.
  """

  @enforce_keys [:message, :type]
  defstruct [:message, :type, :details, :original_error]

  @type error_type ::
          :connection_error
          | :query_error
          | :timeout
          | :auth_error
          | :parse_error
          | :translation_error

  @type t :: %__MODULE__{
          message: String.t(),
          type: error_type(),
          details: map(),
          original_error: term()
        }

  @doc """
  Creates a new QueryError.

  ## Examples

      iex> PowerOfThree.QueryError.new("Connection failed", :connection_error)
      %PowerOfThree.QueryError{message: "Connection failed", type: :connection_error, details: %{}}

      iex> PowerOfThree.QueryError.new("Invalid query", :query_error, %{status: 400})
      %PowerOfThree.QueryError{message: "Invalid query", type: :query_error, details: %{status: 400}}
  """
  def new(message, type, details \\ %{}, original_error \\ nil) do
    %__MODULE__{
      message: message,
      type: type,
      details: details || %{},
      original_error: original_error
    }
  end

  @doc """
  Creates a QueryError from an HTTP response status code.

  Maps HTTP status codes to appropriate error types.
  """
  def from_http_status(status, body \\ nil) do
    case status do
      400 ->
        new("Invalid query", :query_error, %{status: 400, body: body})

      401 ->
        new("Authentication failed", :auth_error, %{status: 401})

      403 ->
        new("Access forbidden", :auth_error, %{status: 403})

      404 ->
        new("Resource not found", :connection_error, %{status: 404})

      500 ->
        new("Internal server error", :query_error, %{status: 500, body: body})

      503 ->
        new("Service unavailable", :connection_error, %{status: 503})

      _ ->
        new("HTTP error #{status}", :connection_error, %{status: status, body: body})
    end
  end

  @doc """
  Creates a QueryError from a timeout.
  """
  def timeout(details \\ %{}) do
    new("Request timeout", :timeout, details)
  end

  @doc """
  Creates a QueryError from a connection failure.
  """
  def connection_error(message, original_error \\ nil) do
    new(message, :connection_error, %{}, original_error)
  end

  @doc """
  Creates a QueryError from a parse error.
  """
  def parse_error(message, original_error \\ nil) do
    new(message, :parse_error, %{}, original_error)
  end

  @doc """
  Creates a QueryError from a translation error (e.g., WHERE clause parsing).
  """
  def translation_error(message) do
    new(message, :translation_error, %{})
  end
end

defimpl String.Chars, for: PowerOfThree.QueryError do
  def to_string(%PowerOfThree.QueryError{message: message, type: type}) do
    "[#{type}] #{message}"
  end
end
