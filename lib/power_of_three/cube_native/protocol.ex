defmodule PowerOfThree.CubeNative.Protocol do
  @moduledoc false
  # Wire format of CubeSQL's Arrow Native server (port 8120), mirroring
  # cube/rust/cubesql/cubesql/src/sql/arrow_native/protocol.rs.
  #
  # A frame is <<len::32, payload::binary-size(len)>>; the length prefix is
  # handled by :gen_tcp with `packet: 4`, so this module works on payloads:
  # <<type::8, body::binary>>. Integers are big-endian; strings and byte blobs
  # are <<len::32, data::binary-size(len)>>.

  # Version 2 adds an optional user name to the auth request, so the server
  # authenticates exactly as its Postgres endpoint does. Version 1 sends the
  # token only; servers that predate version 2 accept nothing else.
  @version 2
  @versions [1, 2]

  @handshake_request 0x01
  @handshake_response 0x02
  @auth_request 0x03
  @auth_response 0x04
  @query_request 0x10
  @query_response_schema 0x11
  @query_response_batch 0x12
  @query_complete 0x13
  @error 0xFF

  def version, do: @version
  def supported_version?(version), do: version in @versions

  def encode({:handshake_request, version}), do: [@handshake_request, <<version::32>>]

  def encode({:handshake_response, version, server_version}),
    do: [@handshake_response, <<version::32>>, str(server_version)]

  def encode({:auth_request, 1, _user, token, database}),
    do: [@auth_request, str(token), opt_str(database)]

  def encode({:auth_request, _version, user, token, database}),
    do: [@auth_request, opt_str(user), str(token), opt_str(database)]

  def encode({:auth_response, success, session_id}),
    do: [@auth_response, if(success, do: 1, else: 0), str(session_id)]

  def encode({:query_request, sql}), do: [@query_request, str(sql)]
  def encode({:schema, ipc}), do: [@query_response_schema, str(ipc)]
  def encode({:batch, ipc}), do: [@query_response_batch, str(ipc)]
  def encode({:complete, rows}), do: [@query_complete, <<rows::signed-64>>]
  def encode({:error, code, message}), do: [@error, str(code), str(message)]

  def decode(<<@handshake_response, version::32, rest::binary>>) do
    with {:ok, server_version, _} <- get_str(rest),
         do: {:ok, {:handshake_response, version, server_version}}
  end

  def decode(<<@auth_response, success, rest::binary>>) do
    with {:ok, session_id, _} <- get_str(rest),
         do: {:ok, {:auth_response, success != 0, session_id}}
  end

  def decode(<<@query_response_schema, rest::binary>>) do
    with {:ok, ipc, _} <- get_str(rest), do: {:ok, {:schema, ipc}}
  end

  def decode(<<@query_response_batch, rest::binary>>) do
    with {:ok, ipc, _} <- get_str(rest), do: {:ok, {:batch, ipc}}
  end

  def decode(<<@query_complete, rows::signed-64>>), do: {:ok, {:complete, rows}}

  def decode(<<@error, rest::binary>>) do
    with {:ok, code, rest} <- get_str(rest),
         {:ok, message, _} <- get_str(rest),
         do: {:ok, {:error, code, message}}
  end

  # Client->server messages, decoded so the fake server in tests can share this module.
  def decode(<<@handshake_request, version::32>>), do: {:ok, {:handshake_request, version}}

  def decode(<<@query_request, rest::binary>>) do
    with {:ok, sql, _} <- get_str(rest), do: {:ok, {:query_request, sql}}
  end

  def decode(other),
    do: {:error, {:bad_message, binary_part(other, 0, min(byte_size(other), 16))}}

  # The auth request's layout depends on the version agreed in the handshake.
  def decode(<<@auth_request, rest::binary>>, 1) do
    with {:ok, token, rest} <- get_str(rest),
         {:ok, database, _} <- get_opt_str(rest),
         do: {:ok, {:auth_request, 1, nil, token, database}}
  end

  def decode(<<@auth_request, rest::binary>>, version) do
    with {:ok, user, rest} <- get_opt_str(rest),
         {:ok, token, rest} <- get_str(rest),
         {:ok, database, _} <- get_opt_str(rest),
         do: {:ok, {:auth_request, version, user, token, database}}
  end

  def decode(payload, _version), do: decode(payload)

  defp str(s), do: [<<byte_size(s)::32>>, s]
  defp opt_str(nil), do: <<0>>
  defp opt_str(s), do: [1, str(s)]

  defp get_str(<<len::32, s::binary-size(len), rest::binary>>), do: {:ok, s, rest}
  defp get_str(other), do: {:error, {:bad_message, {:short_string, byte_size(other)}}}

  defp get_opt_str(<<0, rest::binary>>), do: {:ok, nil, rest}
  defp get_opt_str(<<1, rest::binary>>), do: get_str(rest)
  defp get_opt_str(other), do: {:error, {:bad_message, {:short_optional, byte_size(other)}}}
end
