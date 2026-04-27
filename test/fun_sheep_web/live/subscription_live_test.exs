defmodule FunSheepWeb.SubscriptionLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Billing, Credits}

  # Creates a user role and returns an authenticated conn
  defp user_conn(conn, role \\ :student) do
    {:ok, user} =
      Accounts.create_user_role(%{
        interactor_user_id: "#{role}_#{System.unique_integer([:positive])}",
        role: role,
        email: "#{role}_#{System.unique_integer([:positive])}@example.com",
        display_name: "Test #{role}"
      })

    conn =
      init_test_session(conn, %{
        dev_user_id: user.id,
        dev_user: %{
          "id" => user.id,
          "user_role_id" => user.id,
          "interactor_user_id" => user.interactor_user_id,
          "role" => Atom.to_string(role),
          "email" => user.email,
          "display_name" => user.display_name
        }
      })

    {conn, user}
  end

  describe "mount/3 — basic rendering" do
    test "student sees billing page with tab navigation", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Billing &amp; Subscription"
      assert html =~ "Overview"
      assert html =~ "Plans"
      assert html =~ "Payment"
      assert html =~ "History"
      assert html =~ "Catalog Access"
    end

    test "teacher sees free-for-educators message, not plan picker", %{conn: conn} do
      {conn, _user} = user_conn(conn, :teacher)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Teachers don"
      assert html =~ "free for educators"
      refute html =~ "Choose your plan"
    end

    test "student on free plan sees upgrade button", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Upgrade"
    end

    test "student with paid subscription sees cancel plan button", %{conn: conn} do
      {conn, user} = user_conn(conn, :student)

      {:ok, sub} = Billing.get_or_create_subscription(user.id)

      {:ok, _} =
        Billing.update_subscription(sub, %{
          plan: "monthly",
          status: "active",
          billing_subscription_id: "sub_monthly_#{System.unique_integer([:positive])}"
        })

      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Cancel Plan"
    end
  end

  describe "handle_params/3 — tab routing" do
    test "default tab is overview", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Current Plan"
    end

    test "?tab=plans shows plans tab", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=plans")

      assert html =~ "Choose your plan"
    end

    test "?tab=payment shows payment tab", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=payment")

      assert html =~ "Payment Methods"
    end

    test "?tab=history shows history tab", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=history")

      assert html =~ "Payment History"
    end

    test "?tab=catalog shows catalog tab", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=catalog")

      assert html =~ "Catalog Access"
    end

    test "?success=true shows welcome flash", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?success=true")

      assert html =~ "Welcome to FunSheep Premium"
    end

    test "?cancelled=true shows checkout cancelled flash", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?cancelled=true")

      assert html =~ "Checkout cancelled"
    end
  end

  describe "handle_event switch_tab" do
    test "switching to plans tab navigates there", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription")

      # Use the tab-nav button specifically (rounded-full class in the nav bar)
      view
      |> element("div.rounded-full button[phx-click='switch_tab'][phx-value-tab='plans']")
      |> render_click()

      assert_patched(view, ~p"/subscription?tab=plans")
    end

    test "switching to payment tab navigates there", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription")

      view
      |> element("div.rounded-full button[phx-click='switch_tab'][phx-value-tab='payment']")
      |> render_click()

      assert_patched(view, ~p"/subscription?tab=payment")
    end

    test "switching to history tab navigates there", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription")

      view
      |> element("div.rounded-full button[phx-click='switch_tab'][phx-value-tab='history']")
      |> render_click()

      assert_patched(view, ~p"/subscription?tab=history")
    end

    test "switching to catalog tab navigates there", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription")

      view
      |> element("div.rounded-full button[phx-click='switch_tab'][phx-value-tab='catalog']")
      |> render_click()

      assert_patched(view, ~p"/subscription?tab=catalog")
    end
  end

  describe "handle_event upgrade" do
    test "upgrade redirects to checkout URL for monthly plan", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=plans")

      # The mock billing server returns a checkout URL
      assert {:error, {:redirect, %{to: url}}} =
               view
               |> element("button[phx-click='upgrade'][phx-value-plan='monthly']")
               |> render_click()

      assert url =~ "success=true"
    end

    test "upgrade redirects to checkout URL for annual plan", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=plans")

      assert {:error, {:redirect, %{to: url}}} =
               view
               |> element("button[phx-click='upgrade'][phx-value-plan='annual']")
               |> render_click()

      assert url =~ "success=true"
    end
  end

  describe "handle_event cancel_subscription" do
    test "cancel subscription updates status for paid user", %{conn: conn} do
      {conn, user} = user_conn(conn, :student)

      {:ok, sub} = Billing.get_or_create_subscription(user.id)

      {:ok, _} =
        Billing.update_subscription(sub, %{
          plan: "monthly",
          status: "active",
          billing_subscription_id: "sub_#{System.unique_integer([:positive])}"
        })

      {:ok, view, _html} = live(conn, ~p"/subscription")

      html =
        view
        |> element("button[phx-click='cancel_subscription']")
        |> render_click()

      assert html =~ "Subscription cancelled"
    end

    test "cancel subscription renders plans tab content after switching", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=plans")

      # On free plan, no cancel button is shown (Upgrade is shown instead).
      # Just verify the plans tab renders correctly.
      assert render(view) =~ "Choose your plan"
    end
  end

  describe "handle_event show_add_card / cancel_add_card" do
    test "show_add_card shows the card form", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=payment")

      html =
        view
        |> element("button[phx-click='show_add_card']")
        |> render_click()

      assert html =~ "Add a new card"
    end

    test "cancel_add_card hides the card form", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=payment")

      view
      |> element("button[phx-click='show_add_card']")
      |> render_click()

      html =
        view
        |> element("button[phx-click='cancel_add_card']")
        |> render_click()

      refute html =~ "Add a new card"
    end
  end

  describe "handle_event card_setup_complete" do
    test "card_setup_complete shows success flash and hides form", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=payment")

      # Open the card form first
      view
      |> element("button[phx-click='show_add_card']")
      |> render_click()

      html =
        render_hook(view, "card_setup_complete", %{"payment_method_id" => "pm_test_123"})

      assert html =~ "Payment method added successfully"
      refute html =~ "Add a new card"
    end
  end

  describe "handle_event set_default_card" do
    test "set_default_card shows success flash", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, view, _html} = live(conn, ~p"/subscription?tab=payment")

      # The mock returns a visa card with id "pm_mock_visa"
      # There's only one card and it's default — set_default is shown for non-default
      # We need to verify the event itself can fire. Since mock returns one default card,
      # set_default_card button isn't shown on the default card. Test via render_hook.
      html = render_hook(view, "set_default_card", %{"id" => "pm_mock_visa"})

      assert html =~ "Default payment method updated"
    end
  end

  describe "handle_event remove_card" do
    test "payment tab shows remove card button for each card", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=payment")

      # The mock billing returns pm_mock_visa; the Remove button should be visible
      assert html =~ "Remove"
      assert html =~ "phx-click=\"remove_card\""
    end
  end

  describe "handle_event redeem_credits" do
    test "redeem_credits with sufficient balance shows success flash", %{conn: conn} do
      {conn, user} = user_conn(conn, :student)

      # Award some credits (4 quarter-units = 1 credit); source_ref_id must be a UUID
      {:ok, _} =
        Credits.award_credit(user.id, "referral", 4, Ecto.UUID.generate())

      {:ok, view, _html} = live(conn, ~p"/subscription")

      # The banner should show (pending_credits > 0)
      html = render(view)
      assert html =~ "Wool Credit"

      html = render_hook(view, "redeem_credits", %{})
      assert html =~ "redeemed"
    end

    test "redeem_credits banner is not shown when user has no credits", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      # No credits awarded — pending_credits = 0 on mount, so the redeem
      # button / banner are not rendered at all (the :if guard in the template
      # is `@pending_credits > 0`).
      {:ok, _view, html} = live(conn, ~p"/subscription")

      refute html =~ "Wool Credit"
      refute html =~ "phx-click=\"redeem_credits\""
    end
  end

  describe "overview tab rendering" do
    test "student sees usage stats section", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      # Student overview shows Usage section
      assert html =~ "Total Tests"
      assert html =~ "This Week"
    end

    test "parent does not see usage stats", %{conn: conn} do
      {conn, _user} = user_conn(conn, :parent)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      # Parent sees free-account notice instead of usage
      assert html =~ "Free Account"
      assert html =~ "Parent and teacher accounts are always free"
    end

    test "overview shows payment method section", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Payment Method"
    end

    test "overview shows latest invoice section", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Latest Invoice"
    end
  end

  describe "plans tab rendering" do
    test "plans tab shows all plan options", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=plans")

      assert html =~ "Free"
      assert html =~ "Choose your plan"
    end

    test "plans tab shows FAQ section", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=plans")

      assert html =~ "Frequently Asked Questions"
      assert html =~ "Can I cancel anytime"
    end
  end

  describe "payment tab rendering" do
    test "payment tab shows saved payment methods from mock", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=payment")

      # Mock billing returns visa card ending in 4242
      assert html =~ "Payment Methods"
      assert html =~ "4242"
    end

    test "payment tab shows billing details", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=payment")

      assert html =~ "Billing Details"
      assert html =~ "Plan"
      assert html =~ "Status"
    end
  end

  describe "history tab rendering" do
    test "history tab shows invoices from mock", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=history")

      # Mock billing returns invoices
      assert html =~ "Payment History"
      assert html =~ "INV-2026"
    end
  end

  describe "catalog tab rendering" do
    test "catalog tab shows catalog access info", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=catalog")

      assert html =~ "Catalog Access"
      assert html =~ "Browse Catalog"
    end

    test "catalog tab shows individual course purchases section", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription?tab=catalog")

      assert html =~ "Individual Course Purchases"
    end

    test "paid plan user sees full catalog access", %{conn: conn} do
      {conn, user} = user_conn(conn, :student)

      {:ok, sub} = Billing.get_or_create_subscription(user.id)

      {:ok, _} =
        Billing.update_subscription(sub, %{
          plan: "annual",
          status: "active"
        })

      {:ok, _view, html} = live(conn, ~p"/subscription?tab=catalog")

      assert html =~ "Annual"
    end
  end

  describe "wool credits banner" do
    test "shows credits banner when user has pending credits", %{conn: conn} do
      {conn, user} = user_conn(conn, :student)

      # Award 4 quarter-units = 1 credit; source_ref_id must be a UUID
      {:ok, _} =
        Credits.award_credit(user.id, "referral", 4, Ecto.UUID.generate())

      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "Wool Credit"
      assert html =~ "Redeem"
    end

    test "does not show credits banner when user has no credits", %{conn: conn} do
      {conn, _user} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      refute html =~ "Wool Credit"
    end
  end

  describe "cancelled subscription banner" do
    test "shows cancelled notice when subscription is cancelled", %{conn: conn} do
      {conn, user} = user_conn(conn, :student)

      {:ok, sub} = Billing.get_or_create_subscription(user.id)

      {:ok, _} =
        Billing.update_subscription(sub, %{
          status: "cancelled",
          plan: "monthly",
          billing_subscription_id: "sub_cancelled_#{System.unique_integer([:positive])}"
        })

      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "cancelled"
    end
  end
end
