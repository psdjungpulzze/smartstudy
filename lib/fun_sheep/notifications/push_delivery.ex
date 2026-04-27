defmodule FunSheep.Notifications.PushDelivery do
  @moduledoc """
  Delivers push notifications via the Expo Push API.

  The mobile app registers an Expo push token (`ExponentPushToken[xxx]`) using
  expo-notifications. This module sends to that token by calling Expo's HTTP API
  at https://exp.host/--/api/v2/push/send. Expo relays the message to APNs
  (iOS) or FCM (Android) on our behalf — no Firebase or Apple credentials
  required on FunSheep's side.

  Optional: set EXPO_ACCESS_TOKEN in production to raise the unauthenticated
  rate limit (600 req/min → 1,000 req/min).

  Reference: https://docs.expo.dev/push-notifications/sending-notifications/
  """

  alias FunSheep.Notifications.PushToken
  require Logger

  @expo_push_url "https://exp.host/--/api/v2/push/send"

  @doc """
  Deliver `title` + `body` to all tokens for a user.

  Returns `%{sent: n, failed: n, skipped: n}` across all tokens.
  Only Expo tokens (`ExponentPushToken[...]`) are sent; raw FCM/APNs tokens
  from an older integration are skipped.
  """
  @spec deliver([PushToken.t()], String.t(), String.t(), map()) ::
          %{sent: non_neg_integer(), failed: non_neg_integer(), skipped: non_neg_integer()}
  def deliver(tokens, title, body, extra \\ %{}) do
    expo_tokens =
      Enum.filter(tokens, fn t ->
        String.starts_with?(t.token, "ExponentPushToken[")
      end)

    skipped = length(tokens) - length(expo_tokens)

    case expo_tokens do
      [] ->
        %{sent: 0, failed: 0, skipped: skipped + length(tokens)}

      _ ->
        messages =
          Enum.map(expo_tokens, fn t ->
            %{
              "to" => t.token,
              "title" => title,
              "body" => body,
              "data" => Map.new(extra, fn {k, v} -> {to_string(k), to_string(v)} end),
              "sound" => "default",
              "badge" => 1
            }
          end)

        {sent, failed} = batch_send(messages)
        %{sent: sent, failed: failed, skipped: skipped}
    end
  end

  # ── Internal ──────────────────────────────────────────────────────────────

  defp batch_send(messages) do
    headers =
      [{"content-type", "application/json"}, {"accept", "application/json"}]
      |> maybe_add_auth()

    case Req.post(@expo_push_url, json: messages, headers: headers) do
      {:ok, %{status: 200, body: %{"data" => results}}} ->
        Enum.reduce(results, {0, 0}, fn result, {s, f} ->
          if result["status"] == "ok", do: {s + 1, f}, else: {s, f + 1}
        end)

      {:ok, %{status: status}} ->
        Logger.warning("[PushDelivery] Expo API returned HTTP #{status}")
        {0, length(messages)}

      {:error, reason} ->
        Logger.warning("[PushDelivery] Expo API request failed: #{inspect(reason)}")
        {0, length(messages)}
    end
  end

  defp maybe_add_auth(headers) do
    case Application.get_env(:fun_sheep, :expo_access_token) do
      nil -> headers
      token -> [{"authorization", "Bearer #{token}"} | headers]
    end
  end
end
