defmodule FunSheep.Notifications.UnsubscribeToken do
  @moduledoc """
  Signed, purpose-scoped unsubscribe tokens (spec §8.4).

  Uses `Phoenix.Token` under the app's endpoint. The token carries only
  the guardian's `user_role_id` and an issued-at claim — verification
  accepts tokens up to 90 days old so emails sent two months ago still
  honour the opt-out.
  """

  @salt "parent-digest-unsubscribe"
  # 90 days
  @max_age 90 * 24 * 60 * 60

  def mint(guardian_id) when is_binary(guardian_id) do
    Phoenix.Token.sign(FunSheepWeb.Endpoint, @salt, guardian_id)
  end

  @spec verify(String.t()) :: {:ok, binary()} | {:error, atom()}
  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(FunSheepWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_), do: {:error, :invalid}
end
