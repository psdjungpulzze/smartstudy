defmodule FunSheepWeb.NotFoundError do
  @moduledoc """
  Raised to render a 404 response without leaking the reason.

  Used by authorization layers (e.g. admin routes) that must be
  indistinguishable from non-existent routes to unauthorized users.
  """
  defexception [:message, plug_status: 404]

  @impl true
  def exception(opts) when is_list(opts) do
    %__MODULE__{message: Keyword.get(opts, :message, "Not found")}
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message}
  end

  def exception(_), do: %__MODULE__{message: "Not found"}
end
