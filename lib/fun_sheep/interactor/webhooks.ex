defmodule FunSheep.Interactor.Webhooks do
  @moduledoc """
  Interface to the Interactor Webhooks API and signature verification.

  Creates webhook subscriptions and verifies incoming webhook signatures.
  """

  alias FunSheep.Interactor.Client

  @base_path "/api/v1/webhooks"

  @doc "Creates a webhook subscription."
  @spec create_webhook(map()) :: {:ok, map()} | {:error, term()}
  def create_webhook(attrs) do
    Client.post(@base_path, attrs)
  end

  @doc """
  Verifies an Interactor webhook signature.

  Returns `true` if the signature is valid, `false` otherwise.
  In mock mode, always returns `true`.
  """
  @spec verify_signature(binary(), binary(), binary()) :: boolean()
  def verify_signature(payload, signature, secret) do
    if mock_mode?() do
      true
    else
      expected =
        :crypto.mac(:hmac, :sha256, secret, payload)
        |> Base.encode16(case: :lower)

      Plug.Crypto.secure_compare(expected, signature)
    end
  end

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)
end
