defmodule FunSheepWeb.PracticeRequestLive.ParentCardComponent do
  @moduledoc """
  Renders a parent's pending practice requests on the parent dashboard
  (§4.6.2, §8.3). Accept navigates to `/subscription?request=<id>` —
  the subscription page picks up the request and scopes checkout.
  Decline fires the context's `decline/3` and refreshes the card.

  Embed with:

      <.live_component
        module={FunSheepWeb.PracticeRequestLive.ParentCardComponent}
        id="parent-requests"
        parent_id={@user_role && @user_role.id}
      />
  """

  use FunSheepWeb, :live_component

  alias FunSheep.PracticeRequests
  alias FunSheepWeb.BillingComponents

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_requests(assigns[:parent_id])}
  end

  defp assign_requests(socket, nil), do: assign(socket, requests: [])

  defp assign_requests(socket, parent_id) do
    requests = PracticeRequests.list_pending_for_guardian(parent_id)
    # Mark them viewed as soon as the parent lands on the page.
    Enum.each(requests, fn r ->
      if r.status == :pending, do: PracticeRequests.view(r.id)
    end)

    assign(socket, requests: requests)
  end

  @impl true
  def handle_event("decline_request", %{"id" => id}, socket) do
    _ = PracticeRequests.decline(id, nil)
    {:noreply, assign_requests(socket, socket.assigns.parent_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <BillingComponents.parent_request_card requests={@requests} target={@myself} />
    </div>
    """
  end
end
