defmodule TeacherAssistantWeb.SignInPhoneTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.{Accounts, TeacherFixtures}

  test "sign-in shows the phone form first, then the email form", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/sign-in")

    assert has_element?(view, "input[name='user[phone]']")
    assert has_element?(view, "input[name='user[email]']")
    assert html =~ "Numéro de téléphone"
    assert html =~ "Adresse e-mail"

    {phone_at, _} = :binary.match(html, "user[phone]")
    {email_at, _} = :binary.match(html, "user[email]")
    assert phone_at < email_at
  end

  test "register and reset pages do not show the phone form", %{conn: conn} do
    for path <- [~p"/register", ~p"/reset"] do
      {:ok, view, _html} = live(conn, path)
      refute has_element?(view, "input[name='user[phone]']")
    end
  end

  test "a teacher signs in with the number and temporary password", %{conn: conn} do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()

    {:ok, %{temporary_password: pw}} =
      Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

    {:ok, view, _html} = live(conn, ~p"/sign-in")

    form =
      form(view, "#phone-sign-in form", %{
        "user" => %{"phone" => "6 77 12 34 56", "password" => pw}
      })

    # Sign-in tokens are on: the library checks the password in the
    # LiveView, then hands a short-lived token to the auth controller.
    assert {:error, {:redirect, %{to: to}}} = render_submit(form)
    assert to =~ "/auth/user/phone/sign_in_with_token"

    conn = get(conn, to)
    assert redirected_to(conn) =~ "/"
    assert get_session(conn, "user_token") || get_session(conn, :user_token)
  end

  test "a successful sign-in records when it happened", %{conn: conn} do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()

    {:ok, %{user: user, temporary_password: pw}} =
      Accounts.add_member_by_phone(scope, %{name: "Ali", phone: "677123499", roles: [:teacher]})

    assert user.last_sign_in_at == nil

    {:ok, view, _html} = live(conn, ~p"/sign-in")

    {:error, {:redirect, %{to: to}}} =
      view
      |> form("#phone-sign-in form", %{"user" => %{"phone" => "677123499", "password" => pw}})
      |> render_submit()

    get(conn, to)

    {:ok, user} = Ash.get(TeacherAssistant.Accounts.User, user.id, authorize?: false)
    assert %DateTime{} = user.last_sign_in_at
  end

  describe "the method switch" do
    test "phone is selected by default; the switch toggles client-side", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#sign-in-methods[data-method='phone']")
      assert has_element?(view, "#sign-in-method-phone[aria-pressed='true']", "Téléphone")
      assert has_element?(view, "#sign-in-method-email[aria-pressed='false']", "Adresse e-mail")
      # both forms stay in the DOM
      assert has_element?(view, "#phone-sign-in.ta-phone-form input[name='user[phone]']")
      assert has_element?(view, "#email-sign-in.ta-email-form input[name='user[email]']")

      email_click = view |> element("#sign-in-method-email") |> render() |> phx_click()
      assert email_click =~ "data-method"
      assert email_click =~ "email"
      refute email_click =~ ~s("push")
    end

    test "register and reset have no switch and show the email form", %{conn: conn} do
      for path <- [~p"/register", ~p"/reset"] do
        {:ok, view, _html} = live(conn, path)
        refute has_element?(view, "#sign-in-method-phone")
        assert has_element?(view, "#sign-in-methods[data-method='email']")
      end
    end
  end

  describe "the phone form" do
    test "asks for the number with a +237 look and a 6XX placeholder", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(
               view,
               "#phone-sign-in input[name='user[phone]'][placeholder='6XX XX XX XX']"
             )

      assert render(view) =~ ~s(content: "+237")
      assert view |> element("#phone-sign-in") |> render() =~ "inputmode"
    end

    test "explains that the school gives a new password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#phone-forgot-password", "Mot de passe oublié ?")
      assert has_element?(view, "#phone-forgot-password", "proviseur ou au censeur")
      refute has_element?(view, "#reset-phone-info")
    end

    test "links school heads to the registration", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      assert has_element?(view, "#sign-in-register", "Vous dirigez un établissement ?")

      assert has_element?(
               view,
               "#sign-in-register a[href='/register']",
               "Inscrire mon établissement"
             )
    end
  end

  test "/reset tells phone users that only the school can reset", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reset")

    assert has_element?(view, "#reset-phone-info", "numéro de téléphone")
    assert has_element?(view, "#reset-phone-info", "Seul votre établissement")
  end

  describe "the error alert" do
    setup do
      %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()

      {:ok, %{temporary_password: pw}} =
        Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      %{password: pw}
    end

    test "no alert on a fresh page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")
      refute has_element?(view, "#sign-in-alert")
    end

    test "a wrong password shows the generic alert, not the field error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      html =
        view
        |> form("#phone-sign-in form", %{
          "user" => %{"phone" => "677123456", "password" => "not-the-password"}
        })
        |> render_submit()

      assert has_element?(
               view,
               "#sign-in-alert.ta-auth-alert--error",
               "Identifiant ou mot de passe incorrect"
             )

      assert has_element?(view, "#sign-in-alert", "Vérifiez le numéro (ou l'adresse)")
      refute html =~ "Phone or password was incorrect"
      refute has_element?(view, "#phone-sign-in .ta-error-list")
      # the number stays typed, the password does not
      assert has_element?(view, "#phone-sign-in input[name='user[phone]'][value='677123456']")
      refute has_element?(view, "#phone-sign-in input[name='user[password]'][value]")
    end

    test "while typing, the number stays as typed (no +237 prefix added)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      view
      |> form("#phone-sign-in form", %{"user" => %{"phone" => "6 77 12 34 56"}})
      |> render_change()

      assert has_element?(view, "#phone-sign-in input[name='user[phone]'][value='6 77 12 34 56']")
    end

    test "a malformed number shows the same alert, never the cast error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      html =
        view
        |> form("#phone-sign-in form", %{"user" => %{"phone" => "12", "password" => "whatever1"}})
        |> render_submit()

      assert has_element?(view, "#sign-in-alert", "Identifiant ou mot de passe incorrect")
      refute html =~ "is not a valid phone number"
      refute has_element?(view, "#phone-sign-in .ta-error-list")
    end

    test "after too many wrong passwords the page says to wait", %{conn: conn} do
      user = TeacherFixtures.user_fixture()
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      submit = fn password ->
        view
        |> form("#user-password-sign-in-with-password", %{
          "user" => %{"email" => to_string(user.email), "password" => password}
        })
        |> render_submit()
      end

      for _ <- 1..10, do: submit.("not-the-password")
      assert has_element?(view, "#sign-in-alert", "Identifiant ou mot de passe incorrect")

      submit.("password1234")
      assert has_element?(view, "#sign-in-alert.ta-auth-alert--warning", "Trop de tentatives")
    end

    test "a wrong email password shows the same alert", %{conn: conn} do
      user = TeacherFixtures.user_fixture()
      {:ok, view, _html} = live(conn, ~p"/sign-in")

      html =
        view
        |> form("#user-password-sign-in-with-password", %{
          "user" => %{"email" => to_string(user.email), "password" => "not-the-password"}
        })
        |> render_submit()

      assert has_element?(view, "#sign-in-alert", "Identifiant ou mot de passe incorrect")
      refute html =~ "Email or password was incorrect"
    end

    test "a failure redirected by the auth controller shows as the alert", %{conn: conn} do
      conn =
        post(conn, "/auth/user/phone/sign_in", %{
          "user" => %{"phone" => "677123456", "password" => "not-the-password"}
        })

      assert redirected_to(conn) == "/sign-in"

      {:ok, view, _html} = live(recycle(conn), ~p"/sign-in")

      assert has_element?(
               view,
               "#sign-in-alert.ta-auth-alert--error",
               "Identifiant ou mot de passe incorrect"
             )

      assert has_element?(view, "#sign-in-alert", "puis réessayez")
    end

    test "an expired temporary password shows the warning alert", %{conn: conn} do
      expired = "Mot de passe temporaire expiré — demandez-en un nouveau à l'établissement."

      {:ok, view, _html} =
        conn
        |> init_test_session(%{"phoenix_flash" => %{"error" => expired}})
        |> live(~p"/sign-in")

      assert has_element?(
               view,
               "#sign-in-alert.ta-auth-alert--warning",
               "Mot de passe temporaire expiré"
             )

      assert has_element?(view, "#sign-in-alert", "avait 7 jours")
    end
  end

  defp phx_click(html) do
    [_, click] = Regex.run(~r/phx-click="([^"]*)"/, html)
    click |> String.replace("&quot;", "\"")
  end
end
