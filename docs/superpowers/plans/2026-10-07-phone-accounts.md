# Phone Accounts Created by the School — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a school's staff manager create a teacher account identified by a Cameroonian phone number with a one-time temporary password, link an existing phone account instead of overwriting it, and reset passwords of accounts the school created.

**Architecture:** A custom Ash type normalises phone numbers. `User` gains `phone`, a second AshAuthentication password strategy (`:phone`) sharing `hashed_password`, and three actions (`:create_by_school`, `:reset_temporary_password`, `:set_own_password`) guarded by policies. `Accounts.add_member_by_phone/2` orchestrates user + membership in one transaction, reusing the invitation's membership code (extracted to `Accounts.Memberships`). Signed-in surfaces force a password change while `must_change_password` is set. A small custom sign-in LiveView embeds AshAuthentication.Phoenix's `Password` component once per strategy so each form gets its own label.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ash 3, AshAuthentication 4.15 / AshAuthentication.Phoenix 2.17, AshPostgres, daisyUI, Gettext.

**Spec:** `docs/superpowers/specs/2026-10-07-phone-accounts-design.md`

## Global Constraints

- Phone storage format: `+237` followed by 9 digits starting with `6` or `2`.
- Temporary password validity: 7 days. Shown once; never stored in clear, never in a flash, URL or log.
- Reset allowed only when `user.created_in_workspace_id == current workspace` and `user.role != :admin`.
- Who may create/reset: the `:head` axis (same as `Accounts.can_manage_staff?/1`), enforced by Ash policies.
- Never write migrations manually: `mix ash.codegen --dev` then `mix ash.setup` (test DB: `MIX_ENV=test mix ash.setup` is run by `mix test` aliases; if not, run `MIX_ENV=test mix ecto.migrate`).
- Ash attributes with fixed value sets use `Ash.Type.Enum`, never bare `:atom`.
- All new UI strings via `gettext`, FR msgids (the app's source language is French), EN filled in `priv/gettext/en/LC_MESSAGES/*.po`; FR `.po` msgstr filled too; no `#, fuzzy` left (a guard test exists: `test/teacher_assistant_web/gettext_fuzzy_test.exs`).
- Stage explicit paths only (`git add <paths>`), never `git commit -a` (the user runs parallel sessions).
- Finish with `mix precommit`; it does NOT fail on warnings, so also check `mix compile --warnings-as-errors` output manually.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A head of school B links a phone account created by school A** — B must not see a reset button for that member and `reset_member_password/2` must return Forbidden (Task 4 test "linked account cannot be reset").
2. **Teacher types the number in another format at sign-in** (`677 12 34 56`, `+237677123456`, `00237 6 77…`) — sign-in must succeed (Task 2 test "sign in by phone in any format").
3. **Temporary password left unused for more than 7 days** — sign-in is refused with the expiry message and no session is created (Task 5 test "expired temporary password is refused").
4. **A teacher with `must_change_password` opens a print URL directly** — redirected to `/account/password`, not served the PDF/HTML (Task 5 test "print route redirects").
5. **Two heads submit the same new number concurrently** — the second request links instead of failing. The SQL sandbox serialises transactions, so this cannot be exercised deterministically; the retry branch is covered by the duplicate-insert test in Task 3 (identity error is recognised by `phone_taken?/1`) and by review.

---

## File Structure

Create:
- `lib/teacher_assistant/accounts/phone.ex` — Ash type + `normalize/1` + `format/1`.
- `lib/teacher_assistant/accounts/temporary_password.ex` — generator.
- `lib/teacher_assistant/accounts/user/changes/set_temporary_password.ex` — hashes a fresh temp password, sets flags, exposes it as metadata.
- `lib/teacher_assistant/accounts/user/changes/set_own_password.ex` — hashes the chosen password, clears flags.
- `lib/teacher_assistant/accounts/checks/head_of_creating_school.ex` — policy check.
- `lib/teacher_assistant/accounts/memberships.ex` — `ensure_active/4`, extracted from `SchoolInvitation`.
- `lib/teacher_assistant_web/live/auth/sign_in_live.ex` — custom sign-in / register / reset page.
- `lib/teacher_assistant_web/phone_auth_overrides.ex` — label/placeholder for the phone form.
- `lib/teacher_assistant_web/live/account/password_live.ex` — forced password change.
- `lib/teacher_assistant_web/plug/require_password_change.ex` — controller-side gate.
- Tests: `test/teacher_assistant/accounts/phone_test.exs`, `test/teacher_assistant/accounts/temporary_password_test.exs`, `test/teacher_assistant/accounts/phone_accounts_test.exs`, `test/teacher_assistant_web/live/sign_in_phone_test.exs`, `test/teacher_assistant_web/live/account/password_live_test.exs`.

Modify:
- `lib/teacher_assistant/accounts/user.ex` — attributes, identity, strategy, actions, policies, `display_name/1`, `contact/1`.
- `lib/teacher_assistant/accounts.ex` — `add_member_by_phone/2`, `reset_member_password/2`, `can_reset_member_password?/2`, `revoke_all_sessions/1`, `temporary_password_expired?/1`; nil-safe `active_member_email?/2`.
- `lib/teacher_assistant/accounts/school_invitation.ex` — call `Memberships.ensure_active/4`.
- `lib/teacher_assistant_web/live_user_auth.ex`, `lib/teacher_assistant_web/router.ex`, `lib/teacher_assistant_web/controllers/auth_controller.ex`, `lib/teacher_assistant_web/components/layouts.ex`.
- `lib/teacher_assistant_web/live/school/members_live.ex` and the display call sites listed in Task 7.
- `assets/js/app.js` — `phx:copy` listener.
- `priv/gettext/{fr,en}/LC_MESSAGES/{default,errors}.po`.

---

### Task 1: Phone type

**Files:**
- Create: `lib/teacher_assistant/accounts/phone.ex`
- Test: `test/teacher_assistant/accounts/phone_test.exs`

**Interfaces:**
- Produces: `TeacherAssistant.Accounts.Phone` (an `Ash.Type`, storage `:string`); `Phone.normalize(term) :: {:ok, String.t()} | {:error, :invalid}`; `Phone.format(String.t()) :: String.t()` (`"+237677123456"` → `"6 77 12 34 56"`).

- [ ] **Step 1: Write the failing test**

```elixir
defmodule TeacherAssistant.Accounts.PhoneTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.Phone

  test "accepts the usual ways of writing a Cameroonian number" do
    for input <- [
          "677123456",
          "6 77 12 34 56",
          "6.77.12.34.56",
          "677-12-34-56",
          "+237677123456",
          "+237 6 77 12 34 56",
          "00237677123456",
          "237677123456",
          "222123456"
        ] do
      assert {:ok, "+237" <> rest} = Phone.normalize(input), "rejected #{input}"
      assert String.length(rest) == 9
    end

    assert Phone.normalize("6 77 12 34 56") == {:ok, "+237677123456"}
  end

  test "rejects anything else" do
    for input <- ["", "67712345", "6771234567", "577123456", "+33612345678", "abc", nil, 677_123_456] do
      assert Phone.normalize(input) == {:error, :invalid}, "accepted #{inspect(input)}"
    end
  end

  test "casts through Ash" do
    assert {:ok, "+237677123456"} = Ash.Type.cast_input(Phone, "677 12 34 56", [])
    assert {:ok, nil} = Ash.Type.cast_input(Phone, nil, [])
    assert {:error, _} = Ash.Type.cast_input(Phone, "12", [])
  end

  test "formats for display" do
    assert Phone.format("+237677123456") == "6 77 12 34 56"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/phone_test.exs`
Expected: FAIL — `TeacherAssistant.Accounts.Phone` is undefined.

- [ ] **Step 3: Write the implementation**

```elixir
defmodule TeacherAssistant.Accounts.Phone do
  @moduledoc """
  A Cameroonian phone number, always stored as `+237XXXXXXXXX` (9 national
  digits starting with 6 — mobile — or 2 — landline). Casting normalises
  whatever the person typed, so `6 77 12 34 56` and `+237677123456` are the
  same value everywhere (sign-in, the Members form, the unique identity).
  """
  use Ash.Type

  @impl true
  def storage_type(_constraints), do: :string

  @impl true
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_binary(value) do
    case normalize(value) do
      {:ok, phone} -> {:ok, phone}
      {:error, :invalid} -> {:error, message: "is not a valid phone number"}
    end
  end

  def cast_input(_value, _constraints), do: :error

  @impl true
  def cast_stored(nil, _constraints), do: {:ok, nil}
  def cast_stored(value, _constraints) when is_binary(value), do: {:ok, value}
  def cast_stored(_value, _constraints), do: :error

  @impl true
  def dump_to_native(nil, _constraints), do: {:ok, nil}
  def dump_to_native(value, _constraints) when is_binary(value), do: {:ok, value}
  def dump_to_native(_value, _constraints), do: :error

  @doc "`{:ok, \"+237XXXXXXXXX\"}` for a valid Cameroonian number, else `{:error, :invalid}`."
  def normalize(value) when is_binary(value) do
    national =
      case String.replace(value, ~r/[\s.\-()]/, "") do
        "+237" <> rest -> rest
        "00237" <> rest -> rest
        "237" <> rest when byte_size(rest) == 9 -> rest
        rest -> rest
      end

    if national =~ ~r/\A[62]\d{8}\z/,
      do: {:ok, "+237" <> national},
      else: {:error, :invalid}
  end

  def normalize(_value), do: {:error, :invalid}

  @doc "Human format: `6 77 12 34 56`."
  def format("+237" <> <<a::binary-size(1), b::binary-size(2), c::binary-size(2), d::binary-size(2), e::binary-size(2)>>),
    do: Enum.join([a, b, c, d, e], " ")

  def format(other), do: to_string(other)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/teacher_assistant/accounts/phone_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/accounts/phone.ex test/teacher_assistant/accounts/phone_test.exs
git commit -m "feat: Phone type normalising Cameroonian numbers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: User fields, phone identity and the `:phone` sign-in strategy

**Files:**
- Modify: `lib/teacher_assistant/accounts/user.ex`
- Generated: `priv/repo/migrations/*_phone_accounts*.exs`, `priv/resource_snapshots/repo/users/*.json` (via codegen)
- Test: `test/teacher_assistant/accounts/phone_accounts_test.exs` (created here, extended in Tasks 3–4)

**Interfaces:**
- Consumes: `TeacherAssistant.Accounts.Phone` (Task 1).
- Produces: `User` attributes `phone`, `must_change_password` (boolean, default false), `temporary_password_expires_at` (`:utc_datetime`), `created_in_workspace_id` (uuid, nullable, `belongs_to :created_in_workspace`); identity `:unique_phone`; strategy `:phone` with actions `:sign_in_with_phone` and `:sign_in_with_phone_token`; `User.display_name/1 :: String.t()`, `User.contact/1 :: String.t() | nil`.

- [ ] **Step 1: Write the failing test**

Create `test/teacher_assistant/accounts/phone_accounts_test.exs`. To create a phone user before Task 3 exists, insert through `Ash.Seed` (test-only, bypasses actions):

```elixir
defmodule TeacherAssistant.Accounts.PhoneAccountsTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.Accounts.User

  defp seed_phone_user(phone, password, attrs \\ %{}) do
    {:ok, hash} = AshAuthentication.BcryptProvider.hash(password)

    Ash.Seed.seed!(
      User,
      Map.merge(%{phone: phone, name: "Prof Téléphone", hashed_password: hash}, attrs)
    )
  end

  defp sign_in_by_phone(phone, password) do
    strategy = AshAuthentication.Info.strategy!(User, :phone)
    AshAuthentication.Strategy.action(strategy, :sign_in, %{"phone" => phone, "password" => password})
  end

  describe "sign in by phone" do
    test "sign in by phone in any format" do
      user = seed_phone_user("+237677123456", "secret-pass-1")

      for typed <- ["677123456", "6 77 12 34 56", "+237 677 12 34 56", "00237677123456"] do
        assert {:ok, signed_in} = sign_in_by_phone(typed, "secret-pass-1"), "failed for #{typed}"
        assert signed_in.id == user.id
      end
    end

    test "a wrong password or unknown number fails the same way" do
      seed_phone_user("+237677123456", "secret-pass-1")

      assert {:error, %AshAuthentication.Errors.AuthenticationFailed{}} =
               sign_in_by_phone("677123456", "wrong-pass")

      assert {:error, %AshAuthentication.Errors.AuthenticationFailed{}} =
               sign_in_by_phone("699999999", "secret-pass-1")
    end

    test "the email strategy is unchanged" do
      user = TeacherAssistant.TeacherFixtures.user_fixture(%{email: "mail@example.com"})
      strategy = AshAuthentication.Info.strategy!(User, :password)

      assert {:ok, signed_in} =
               AshAuthentication.Strategy.action(strategy, :sign_in, %{
                 "email" => "mail@example.com",
                 "password" => "password1234"
               })

      assert signed_in.id == user.id
    end
  end

  describe "identity and display" do
    test "the phone is unique" do
      seed_phone_user("+237677123456", "secret-pass-1")

      assert_raise Ash.Error.Invalid, fn ->
        User
        |> Ash.Changeset.for_create(:create, %{phone: "677123456"})
        |> Ash.create!(authorize?: false)
      end
    end

    test "an account needs an email or a phone" do
      assert {:error, %Ash.Error.Invalid{}} =
               User
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create(authorize?: false)
    end

    test "display_name and contact fall back to email, then phone" do
      assert User.display_name(%User{name: "Awa", email: nil, phone: nil}) == "Awa"
      assert User.display_name(%User{name: nil, email: "a@b.cm", phone: nil}) == "a@b.cm"
      assert User.display_name(%User{name: nil, email: nil, phone: "+237677123456"}) == "6 77 12 34 56"
      assert User.contact(%User{email: "a@b.cm", phone: "+237677123456"}) == "a@b.cm"
      assert User.contact(%User{email: nil, phone: "+237677123456"}) == "6 77 12 34 56"
      assert User.contact(%User{email: nil, phone: nil}) == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/teacher_assistant/accounts/phone_accounts_test.exs`
Expected: FAIL — no `:phone` strategy / unknown attribute `phone`.

- [ ] **Step 3: Implement the User changes**

In `lib/teacher_assistant/accounts/user.ex`:

a) In `strategies do`, add after the `password :password` block:

```elixir
      # Accounts created by a school (spec 2026-10-07): the phone number is the
      # identifier, the password is shared with the email strategy. No
      # self-registration and no self-service reset — the school resets it.
      password :phone do
        identity_field :phone
        hashed_password_field :hashed_password
        registration_enabled? false
        sign_in_action_name :sign_in_with_phone
        sign_in_with_token_action_name :sign_in_with_phone_token
      end
```

b) In `actions do`, after `read :sign_in_with_password`, add:

```elixir
    read :sign_in_with_phone do
      get? true

      argument :phone, TeacherAssistant.Accounts.Phone, allow_nil?: false
      argument :password, :string, allow_nil?: false, sensitive?: true

      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string, allow_nil?: false
    end

    read :sign_in_with_phone_token do
      get? true

      argument :token, :string, allow_nil?: false, sensitive?: true
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string, allow_nil?: false
    end
```

Change `create :create` to also accept the phone: `accept [:email, :phone, :hashed_password]`.

c) Replace the `attributes do … end` block:

```elixir
  attributes do
    uuid_v7_primary_key :id

    attribute :email, :ci_string, allow_nil?: true, public?: true
    attribute :phone, TeacherAssistant.Accounts.Phone, allow_nil?: true, public?: true
    attribute :role, TeacherAssistant.Accounts.UserRole, default: :teacher, public?: true
    attribute :name, :string, allow_nil?: true, public?: true

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    # Set while the account holds a temporary password given by the school.
    attribute :must_change_password, :boolean,
      allow_nil?: false,
      default: false,
      public?: true

    attribute :temporary_password_expires_at, :utc_datetime, public?: true

    timestamps()
  end
```

d) In `relationships do`, add:

```elixir
    # The school whose staff manager created this account (phone accounts);
    # only that school may reset its password. Nil for self-registered users.
    belongs_to :created_in_workspace, TeacherAssistant.Academics.Workspace do
      allow_nil? true
      attribute_writable? true
      public? true
    end
```

e) Replace `identities do … end`:

```elixir
  identities do
    identity :unique_email, [:email]
    identity :unique_phone, [:phone]
  end

  validations do
    validate present([:email, :phone], at_least: 1), on: [:create]
  end
```

f) At the end of the module (before the final `end`), add:

```elixir
  alias TeacherAssistant.Accounts.Phone

  @doc "How to name a person in the UI: name, else email, else formatted phone."
  def display_name(%{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%{email: email}) when not is_nil(email), do: to_string(email)
  def display_name(%{phone: phone}) when is_binary(phone), do: Phone.format(phone)
  def display_name(_user), do: ""

  @doc "How to reach a person: email, else formatted phone, else nil."
  def contact(%{email: email}) when not is_nil(email), do: to_string(email)
  def contact(%{phone: phone}) when is_binary(phone), do: Phone.format(phone)
  def contact(_user), do: nil
```

(Place the `alias` at the top of the module with any other aliases if the formatter/credo prefers; the module currently has none.)

- [ ] **Step 4: Generate and run the migration**

Run: `mix ash.codegen --dev && mix ash.setup`
Expected: a new migration altering `users` (email nullable, new columns, `users_unique_phone_index`, FK to `workspaces`). Open it and confirm it contains no unrelated changes. Then `MIX_ENV=test mix ecto.migrate`.

- [ ] **Step 5: Run the tests**

Run: `mix test test/teacher_assistant/accounts/phone_accounts_test.exs test/teacher_assistant_web/live/auth_smoke_test.exs`
Expected: PASS. If `auth_smoke_test` now shows the phone form with the label "Adresse e-mail" that is expected until Task 6; the smoke assertions themselves must still pass.

- [ ] **Step 6: Run the whole suite once (email now nullable)**

Run: `mix test --max-failures 10`
Expected: PASS. A failure here usually means code assuming `user.email` is non-nil; fix the call site with `User.display_name/1` / `User.contact/1` (the full list is handled in Task 7, only fix what breaks now).

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/accounts/user.ex priv/repo/migrations priv/resource_snapshots test/teacher_assistant/accounts/phone_accounts_test.exs
git commit -m "feat: phone identity and phone sign-in strategy on User

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Temporary passwords and the school-side User actions

**Files:**
- Create: `lib/teacher_assistant/accounts/temporary_password.ex`, `lib/teacher_assistant/accounts/user/changes/set_temporary_password.ex`, `lib/teacher_assistant/accounts/user/changes/set_own_password.ex`, `lib/teacher_assistant/accounts/checks/head_of_creating_school.ex`
- Modify: `lib/teacher_assistant/accounts/user.ex`
- Test: `test/teacher_assistant/accounts/temporary_password_test.exs`, `test/teacher_assistant/accounts/phone_accounts_test.exs`

**Interfaces:**
- Consumes: `User` fields (Task 2); `TeacherAssistant.Accounts.Checks.SchoolRole.holds?(user, workspace_id, :head)`.
- Produces:
  - `TemporaryPassword.generate() :: String.t()` matching `~r/\A[a-z]{4}-[a-z]{4}-\d{4}\z/`.
  - `User` actions: `create :create_by_school` (accepts `name`, `phone`, `created_in_workspace_id`), `update :reset_temporary_password`, `update :set_own_password` (args `password`, `password_confirmation`). The first two put the clear password in `user.__metadata__.temporary_password`.

Note on the spec: the spec says "two words from a list of ≥ 256 words". This plan uses two pronounceable 4-letter pseudo-words (consonant-vowel-consonant-vowel from 14 consonants × 5 vowels, 4 900 words) plus 4 digits: same "easy to dictate" goal, ~38 bits instead of ~29, and no word list to maintain.

- [ ] **Step 1: Write the failing generator test**

```elixir
defmodule TeacherAssistant.Accounts.TemporaryPasswordTest do
  use ExUnit.Case, async: true
  alias TeacherAssistant.Accounts.TemporaryPassword

  test "two pronounceable words and four digits" do
    for _ <- 1..200 do
      assert TemporaryPassword.generate() =~ ~r/\A[bdfgklmnprstvz][aeiou][bdfgklmnprstvz][aeiou]-[bdfgklmnprstvz][aeiou][bdfgklmnprstvz][aeiou]-\d{4}\z/
    end
  end

  test "values differ" do
    values = for _ <- 1..200, do: TemporaryPassword.generate()
    assert length(Enum.uniq(values)) == 200
  end
end
```

- [ ] **Step 2: Run it, expect FAIL** (`mix test test/teacher_assistant/accounts/temporary_password_test.exs` → module undefined).

- [ ] **Step 3: Implement the generator**

```elixir
defmodule TeacherAssistant.Accounts.TemporaryPassword do
  @moduledoc """
  One-time passwords a school hands to a teacher by voice, WhatsApp or SMS:
  two pronounceable 4-letter words and 4 digits, e.g. `kola-mabu-4827`
  (~38 bits). Letters that are easily confused when dictated (c, q, x, j, h,
  w, y) are left out. Uses `:crypto`, never `:rand`.
  """

  @consonants ~c"bdfgklmnprstvz"
  @vowels ~c"aeiou"

  def generate do
    "#{word()}-#{word()}-#{digits()}"
  end

  defp word do
    for pick <- [@consonants, @vowels, @consonants, @vowels], into: "", do: <<pick_one(pick)>>
  end

  defp digits do
    random(10_000) |> Integer.to_string() |> String.pad_leading(4, "0")
  end

  defp pick_one(chars), do: Enum.at(chars, random(length(chars)))

  defp random(n), do: :crypto.strong_rand_bytes(4) |> :binary.decode_unsigned() |> rem(n)
end
```

- [ ] **Step 4: Run it, expect PASS.**

- [ ] **Step 5: Write the failing action/policy tests**

Append to `test/teacher_assistant/accounts/phone_accounts_test.exs` (inside the module):

```elixir
  alias TeacherAssistant.TeacherFixtures

  defp head_scope do
    %{scope: scope} = TeacherFixtures.setup_complete_school_fixture()
    scope
  end

  defp create_by_school(scope, attrs) do
    User
    |> Ash.Changeset.for_create(
      :create_by_school,
      Map.merge(%{name: "Awa Nji", created_in_workspace_id: scope.current_workspace.id}, attrs),
      scope: scope
    )
    |> Ash.create()
  end

  describe "create_by_school" do
    test "a head creates a phone account with a temporary password" do
      scope = head_scope()
      assert {:ok, user} = create_by_school(scope, %{phone: "6 77 12 34 56"})

      assert user.phone == "+237677123456"
      assert user.must_change_password
      assert user.created_in_workspace_id == scope.current_workspace.id
      assert DateTime.diff(user.temporary_password_expires_at, DateTime.utc_now(), :day) in 6..7

      password = user.__metadata__.temporary_password
      assert password =~ ~r/\A[a-z]{4}-[a-z]{4}-\d{4}\z/
      assert {:ok, _} = sign_in_by_phone("677123456", password)
    end

    test "a non-head member cannot create accounts" do
      scope = head_scope()
      teacher_scope = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

      assert {:error, %Ash.Error.Forbidden{}} =
               create_by_school(teacher_scope, %{
                 phone: "677123456",
                 created_in_workspace_id: scope.current_workspace.id
               })
    end

    test "a head cannot create an account on behalf of another school" do
      scope = head_scope()
      other = head_scope()

      assert {:error, %Ash.Error.Forbidden{}} =
               create_by_school(scope, %{
                 phone: "677123456",
                 created_in_workspace_id: other.current_workspace.id
               })
    end

    test "a duplicate phone is reported as an identity error" do
      scope = head_scope()
      {:ok, _} = create_by_school(scope, %{phone: "677123456"})
      assert {:error, error} = create_by_school(scope, %{phone: "+237677123456"})
      assert TeacherAssistant.Accounts.phone_taken?(error)
    end
  end

  describe "set_own_password" do
    test "the user replaces the temporary password and the flags clear" do
      scope = head_scope()
      {:ok, user} = create_by_school(scope, %{phone: "677123456"})

      assert {:ok, updated} =
               user
               |> Ash.Changeset.for_update(
                 :set_own_password,
                 %{password: "my-own-pass", password_confirmation: "my-own-pass"},
                 actor: user
               )
               |> Ash.update()

      refute updated.must_change_password
      assert updated.temporary_password_expires_at == nil
      assert {:ok, _} = sign_in_by_phone("677123456", "my-own-pass")
    end

    test "confirmation must match and length is at least 8" do
      scope = head_scope()
      {:ok, user} = create_by_school(scope, %{phone: "677123456"})

      for {pw, confirm} <- [{"my-own-pass", "other-pass"}, {"short", "short"}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 user
                 |> Ash.Changeset.for_update(
                   :set_own_password,
                   %{password: pw, password_confirmation: confirm},
                   actor: user
                 )
                 |> Ash.update()
      end
    end

    test "nobody else can set it" do
      scope = head_scope()
      {:ok, user} = create_by_school(scope, %{phone: "677123456"})

      assert {:error, %Ash.Error.Forbidden{}} =
               user
               |> Ash.Changeset.for_update(
                 :set_own_password,
                 %{password: "my-own-pass", password_confirmation: "my-own-pass"},
                 actor: scope.current_user
               )
               |> Ash.update()
    end
  end
```

`TeacherFixtures.member_scope_fixture/2` already exists (`test/support/fixtures/teacher_fixtures.ex:124`); check its accepted attrs and adapt the `roles:` key if it differs.

- [ ] **Step 6: Run them, expect FAIL** (unknown action `:create_by_school`).

- [ ] **Step 7: Implement the changes, check and actions**

`lib/teacher_assistant/accounts/user/changes/set_temporary_password.ex`:

```elixir
defmodule TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword do
  @moduledoc """
  Gives the account a fresh temporary password (valid 7 days, change forced at
  first sign-in). Only the hash is stored; the clear value is returned once as
  `user.__metadata__.temporary_password` for the head to hand over.
  """
  use Ash.Resource.Change

  alias TeacherAssistant.Accounts.TemporaryPassword

  @validity_days 7

  @impl true
  def change(changeset, _opts, _context) do
    password = TemporaryPassword.generate()
    {:ok, hash} = AshAuthentication.BcryptProvider.hash(password)

    expires_at =
      DateTime.utc_now() |> DateTime.add(@validity_days, :day) |> DateTime.truncate(:second)

    changeset
    |> Ash.Changeset.force_change_attribute(:hashed_password, hash)
    |> Ash.Changeset.force_change_attribute(:must_change_password, true)
    |> Ash.Changeset.force_change_attribute(:temporary_password_expires_at, expires_at)
    |> Ash.Changeset.after_action(fn _changeset, user ->
      {:ok, Ash.Resource.put_metadata(user, :temporary_password, password)}
    end)
  end
end
```

`lib/teacher_assistant/accounts/user/changes/set_own_password.ex`:

```elixir
defmodule TeacherAssistant.Accounts.User.Changes.SetOwnPassword do
  @moduledoc "Stores the password the user chose and lifts the forced change."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      {:ok, hash} =
        changeset
        |> Ash.Changeset.get_argument(:password)
        |> AshAuthentication.BcryptProvider.hash()

      changeset
      |> Ash.Changeset.force_change_attribute(:hashed_password, hash)
      |> Ash.Changeset.force_change_attribute(:must_change_password, false)
      |> Ash.Changeset.force_change_attribute(:temporary_password_expires_at, nil)
    end)
  end
end
```

`lib/teacher_assistant/accounts/checks/head_of_creating_school.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Checks.HeadOfCreatingSchool do
  @moduledoc """
  Policy check for the school-managed account actions: the actor is an active
  head (`:head` axis) of the school recorded in `created_in_workspace_id` —
  the value being written on create, the stored value on update. A linked
  account created by another school therefore never matches.
  """
  use Ash.Policy.SimpleCheck

  alias TeacherAssistant.Accounts.Checks.SchoolRole

  @impl true
  def describe(_opts), do: "actor is a head of the school that created the account"

  @impl true
  def match?(actor, %{subject: %Ash.Changeset{} = changeset}, _opts) do
    workspace_id = Ash.Changeset.get_attribute(changeset, :created_in_workspace_id)
    SchoolRole.holds?(actor, workspace_id, :head)
  end

  def match?(_actor, _context, _opts), do: false
end
```

In `user.ex` `actions do`, add:

```elixir
    create :create_by_school do
      accept [:name, :phone, :created_in_workspace_id]
      validate present([:name, :phone, :created_in_workspace_id])
      change TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword
    end

    update :reset_temporary_password do
      accept []
      require_atomic? false
      change TeacherAssistant.Accounts.User.Changes.SetTemporaryPassword
    end

    update :set_own_password do
      accept []
      require_atomic? false

      argument :password, :string,
        allow_nil?: false,
        sensitive?: true,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, allow_nil?: false, sensitive?: true

      validate confirm(:password, :password_confirmation)
      change TeacherAssistant.Accounts.User.Changes.SetOwnPassword
    end
```

In `policies do`, add:

```elixir
    policy action(:create_by_school) do
      authorize_if TeacherAssistant.Accounts.Checks.HeadOfCreatingSchool
    end

    # Never an operator's account; only the school that created the account.
    policy action(:reset_temporary_password) do
      forbid_if expr(role == :admin)
      authorize_if TeacherAssistant.Accounts.Checks.HeadOfCreatingSchool
    end

    policy action(:set_own_password) do
      authorize_if expr(id == ^actor(:id))
    end
```

In `lib/teacher_assistant/accounts.ex`, add (public, used by Task 4 and the test):

```elixir
  @doc "Whether an Ash error is the `:unique_phone` identity violation."
  def phone_taken?(%Ash.Error.Invalid{errors: errors}),
    do: Enum.any?(errors, &match?(%{field: :phone}, &1))

  def phone_taken?(_error), do: false
```

- [ ] **Step 8: Run the tests**

Run: `mix test test/teacher_assistant/accounts/temporary_password_test.exs test/teacher_assistant/accounts/phone_accounts_test.exs`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/teacher_assistant/accounts/temporary_password.ex lib/teacher_assistant/accounts/user/changes lib/teacher_assistant/accounts/checks/head_of_creating_school.ex lib/teacher_assistant/accounts/user.ex lib/teacher_assistant/accounts.ex test/teacher_assistant/accounts/temporary_password_test.exs test/teacher_assistant/accounts/phone_accounts_test.exs
git commit -m "feat: school-created accounts with temporary passwords

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `add_member_by_phone`, reset and session revocation

**Files:**
- Create: `lib/teacher_assistant/accounts/memberships.ex`
- Modify: `lib/teacher_assistant/accounts.ex`, `lib/teacher_assistant/accounts/school_invitation.ex:165-198`
- Test: `test/teacher_assistant/accounts/phone_accounts_test.exs`

**Interfaces:**
- Consumes: Task 3 actions; `Accounts.can_manage_staff?/1`, `Accounts.list_members/1`.
- Produces:
  - `Memberships.ensure_active(user_id, roles, status, opts) :: :ok | {:error, term}` — `opts` are passed to every Ash call (`[scope: scope]` or `[tenant: id, authorize?: false]`).
  - `Accounts.add_member_by_phone(scope, %{name:, phone:, roles:, membership_status:}) :: {:ok, %{user: User.t(), temporary_password: String.t() | nil}} | {:error, :invalid_phone | :already_member | :forbidden | term}` (`temporary_password` is nil when an existing account was linked).
  - `Accounts.reset_member_password(scope, %SchoolMembership{}) :: {:ok, String.t()} | {:error, term}`.
  - `Accounts.can_reset_member_password?(scope, %User{}) :: boolean`.
  - `Accounts.revoke_all_sessions(%User{}) :: :ok | {:error, term}`.
  - `Accounts.temporary_password_expired?(%User{}) :: boolean`.

- [ ] **Step 1: Write the failing tests**

Append to `phone_accounts_test.exs`:

```elixir
  alias TeacherAssistant.Accounts

  defp member_ids(scope), do: scope |> Accounts.list_members() |> Enum.map(& &1.user_id)

  describe "add_member_by_phone" do
    test "new number: creates the account and the membership" do
      scope = head_scope()

      assert {:ok, %{user: user, temporary_password: pw}} =
               Accounts.add_member_by_phone(scope, %{
                 name: "Awa Nji",
                 phone: "677 12 34 56",
                 roles: [:teacher]
               })

      assert is_binary(pw)
      assert user.id in member_ids(scope)
    end

    test "existing account: linked, its name and password untouched" do
      scope_a = head_scope()
      scope_b = head_scope()

      {:ok, %{user: user, temporary_password: pw}} =
        Accounts.add_member_by_phone(scope_a, %{name: "Awa Nji", phone: "677123456", roles: [:teacher]})

      assert {:ok, %{user: linked, temporary_password: nil}} =
               Accounts.add_member_by_phone(scope_b, %{
                 name: "Autre Nom",
                 phone: "+237 677 12 34 56",
                 roles: [:teacher]
               })

      assert linked.id == user.id
      assert linked.id in member_ids(scope_b)
      reloaded = Ash.get!(User, user.id, authorize?: false)
      assert reloaded.name == "Awa Nji"
      assert {:ok, _} = sign_in_by_phone("677123456", pw)
    end

    test "already an active member" do
      scope = head_scope()
      attrs = %{name: "Awa Nji", phone: "677123456", roles: [:teacher]}
      {:ok, _} = Accounts.add_member_by_phone(scope, attrs)
      assert {:error, :already_member} = Accounts.add_member_by_phone(scope, attrs)
    end

    test "invalid phone" do
      assert {:error, :invalid_phone} =
               Accounts.add_member_by_phone(head_scope(), %{name: "X", phone: "12", roles: [:teacher]})
    end

    test "a non-head cannot add members" do
      scope = head_scope()
      teacher_scope = TeacherFixtures.member_scope_fixture(scope, %{roles: [:teacher]})

      assert {:error, :forbidden} =
               Accounts.add_member_by_phone(teacher_scope, %{
                 name: "X",
                 phone: "677123456",
                 roles: [:teacher]
               })
    end
  end

  describe "reset_member_password" do
    defp membership_of(scope, user), do: Enum.find(Accounts.list_members(scope), &(&1.user_id == user.id))

    test "the creating school resets: new password, old one stops working, sessions revoked" do
      scope = head_scope()
      {:ok, %{user: user, temporary_password: old}} =
        Accounts.add_member_by_phone(scope, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      {:ok, signed_in} = sign_in_by_phone("677123456", old)
      token = signed_in.__metadata__.token

      assert {:ok, new} = Accounts.reset_member_password(scope, membership_of(scope, user))
      assert new != old
      assert {:error, _} = sign_in_by_phone("677123456", old)
      assert {:ok, _} = sign_in_by_phone("677123456", new)

      assert AshAuthentication.TokenResource.token_revoked?(
               TeacherAssistant.Accounts.Token,
               token
             )
    end

    test "linked account cannot be reset" do
      scope_a = head_scope()
      scope_b = head_scope()
      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(scope_a, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      {:ok, _} = Accounts.add_member_by_phone(scope_b, %{name: "Awa", phone: "677123456", roles: [:teacher]})

      refute Accounts.can_reset_member_password?(scope_b, user)
      assert Accounts.can_reset_member_password?(scope_a, user)

      assert {:error, %Ash.Error.Forbidden{}} =
               Accounts.reset_member_password(scope_b, membership_of(scope_b, user))
    end

    test "an operator's account is never reset" do
      scope = head_scope()
      {:ok, %{user: user}} =
        Accounts.add_member_by_phone(scope, %{name: "Op", phone: "677123456", roles: [:teacher]})

      {:ok, _} = Accounts.promote_to_admin(user, authorize?: false)
      refute Accounts.can_reset_member_password?(scope, Ash.get!(User, user.id, authorize?: false))
    end
  end

  test "temporary_password_expired?/1" do
    past = DateTime.add(DateTime.utc_now(), -1, :day)
    future = DateTime.add(DateTime.utc_now(), 1, :day)

    assert Accounts.temporary_password_expired?(%User{must_change_password: true, temporary_password_expires_at: past})
    refute Accounts.temporary_password_expired?(%User{must_change_password: true, temporary_password_expires_at: future})
    refute Accounts.temporary_password_expired?(%User{must_change_password: false, temporary_password_expires_at: past})
  end
```

- [ ] **Step 2: Run them, expect FAIL** (`add_member_by_phone/2` undefined).

- [ ] **Step 3: Extract `Memberships.ensure_active/4`**

`lib/teacher_assistant/accounts/memberships.ex`:

```elixir
defmodule TeacherAssistant.Accounts.Memberships do
  @moduledoc """
  Create or reactivate a user's membership in a school. Shared by invitation
  acceptance (system call, `authorize?: false`) and by a head adding a phone
  account (`scope:`, policy-checked). `opts` go to every Ash call and must
  carry the school as tenant (directly or through the scope).
  """
  require Ash.Query
  alias TeacherAssistant.Accounts.SchoolMembership

  def ensure_active(user_id, roles, status, opts) do
    SchoolMembership
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.read_one(opts)
    |> case do
      {:ok, %SchoolMembership{active: true}} ->
        :ok

      {:ok, %SchoolMembership{} = m} ->
        m
        |> Ash.Changeset.for_update(:update, %{active: true, roles: roles, status: status}, opts)
        |> Ash.update()
        |> ok()

      {:ok, nil} ->
        SchoolMembership
        |> Ash.Changeset.for_create(:create, %{user_id: user_id, roles: roles, status: status}, opts)
        |> Ash.create()
        |> ok()

      {:error, error} ->
        {:error, error}
    end
  end

  defp ok({:ok, _}), do: :ok
  defp ok({:error, error}), do: {:error, error}
end
```

In `school_invitation.ex`, replace the body of `defp ensure_membership(inv, user)` (lines ~165–198) and delete its private `ok/1` helpers:

```elixir
  defp ensure_membership(inv, user) do
    TeacherAssistant.Accounts.Memberships.ensure_active(
      user.id,
      inv.roles,
      inv.membership_status,
      tenant: inv.workspace_id,
      authorize?: false
    )
  end
```

Note: `for_create/for_update` take `tenant`/`authorize?`/`scope` options in Ash 3; if Ash rejects `authorize?` in `for_*` opts, pass opts to `Ash.update/2` / `Ash.create/2` instead (split: `{action_opts, call_opts}` is not needed — Ash 3 accepts `authorize?`, `tenant`, `scope`, `actor` in both).

Run: `mix test test/teacher_assistant/accounts/school_invitations_test.exs` — expected PASS (pure refactor).

- [ ] **Step 4: Implement the Accounts functions**

In `lib/teacher_assistant/accounts.ex` add `alias TeacherAssistant.Accounts.{Memberships, Phone}` to the aliases, `require Ash.Query` if missing, then:

```elixir
  # --- Phone accounts (spec 2026-10-07) ---------------------------------------

  @doc """
  Adds a person to the current school by phone. A new number gets an account
  with a temporary password (returned once); a number that already has an
  account is linked without touching it (`temporary_password: nil`).
  """
  def add_member_by_phone(%Scope{} = scope, %{} = attrs, retries \\ 1) do
    with true <- can_manage_staff?(scope) || {:error, :forbidden},
         {:ok, phone} <- normalize_phone(attrs[:phone]),
         false <- active_member_phone?(scope, phone) || {:error, :already_member} do
      roles = attrs[:roles] || [:teacher]
      status = attrs[:membership_status]

      TeacherAssistant.Repo.transaction(fn ->
        case find_user_by_phone(phone) do
          %User{} = user -> link_user(scope, user, roles, status)
          nil -> create_and_link(scope, attrs[:name], phone, roles, status)
        end
        |> case do
          {:ok, result} -> result
          {:error, error} -> TeacherAssistant.Repo.rollback(error)
        end
      end)
      |> case do
        # Another head created the same number between our lookup and insert.
        {:error, error} when retries > 0 ->
          if phone_taken?(error),
            do: add_member_by_phone(scope, attrs, retries - 1),
            else: {:error, error}

        other ->
          other
      end
    end
  end

  defp normalize_phone(value) do
    case Phone.normalize(value) do
      {:ok, phone} -> {:ok, phone}
      {:error, :invalid} -> {:error, :invalid_phone}
    end
  end

  defp active_member_phone?(scope, phone),
    do: scope |> list_members() |> Enum.any?(&(&1.user.phone == phone))

  # System lookup: the head cannot read users outside their school, but must
  # know whether the number already has an account in order to link it.
  defp find_user_by_phone(phone) do
    User
    |> Ash.Query.filter(phone == ^phone)
    |> Ash.read_one!(authorize?: false)
  end

  defp link_user(scope, user, roles, status) do
    with :ok <- Memberships.ensure_active(user.id, roles, status, scope: scope) do
      {:ok, %{user: user, temporary_password: nil}}
    end
  end

  defp create_and_link(scope, name, phone, roles, status) do
    with {:ok, user} <-
           User
           |> Ash.Changeset.for_create(
             :create_by_school,
             %{name: name, phone: phone, created_in_workspace_id: scope.current_workspace.id},
             scope: scope
           )
           |> Ash.create(),
         :ok <- Memberships.ensure_active(user.id, roles, status, scope: scope) do
      {:ok, %{user: user, temporary_password: user.__metadata__.temporary_password}}
    end
  end

  @doc "New temporary password for a member whose account this school created; signs them out everywhere."
  def reset_member_password(%Scope{} = scope, %SchoolMembership{} = membership) do
    with {:ok, %{user: user}} <- Ash.load(membership, :user, scope: scope),
         {:ok, user} <-
           user
           |> Ash.Changeset.for_update(:reset_temporary_password, %{}, scope: scope)
           |> Ash.update(),
         :ok <- revoke_all_sessions(user) do
      {:ok, user.__metadata__.temporary_password}
    end
  end

  def can_reset_member_password?(%Scope{} = scope, %User{} = user),
    do: Ash.can?({user, :reset_temporary_password}, scope)

  @doc "Revokes every stored token of the user (sign out on every device)."
  def revoke_all_sessions(%User{} = user) do
    TeacherAssistant.Accounts.Token
    |> Ash.bulk_update(
      :revoke_all_stored_for_subject,
      %{subject: AshAuthentication.user_to_subject(user)},
      context: %{private: %{ash_authentication?: true}},
      strategy: [:atomic, :atomic_batches, :stream],
      return_errors?: true
    )
    |> case do
      %{status: :success} -> :ok
      %{errors: errors} -> {:error, errors}
    end
  end

  def temporary_password_expired?(%User{must_change_password: true, temporary_password_expires_at: %DateTime{} = at}),
    do: DateTime.compare(DateTime.utc_now(), at) == :gt

  def temporary_password_expired?(_user), do: false
```

Also make `active_member_email?/2` nil-safe (an email-less member must never match an invitation email):

```elixir
  defp active_member_email?(%Scope{} = scope, email) do
    scope
    |> list_members()
    |> Enum.any?(fn m -> m.user.email && to_string(m.user.email) == to_string(email) end)
  end
```

If `Accounts.list_members/1` does not load `:user` with `phone`, it does — `phone` is a public attribute, loaded by default with the relationship.

- [ ] **Step 5: Run the tests**

Run: `mix test test/teacher_assistant/accounts/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant/accounts/memberships.ex lib/teacher_assistant/accounts.ex lib/teacher_assistant/accounts/school_invitation.ex test/teacher_assistant/accounts/phone_accounts_test.exs
git commit -m "feat: add members by phone, reset temporary passwords

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Forced password change and expiry at sign-in

**Files:**
- Create: `lib/teacher_assistant_web/live/account/password_live.ex`, `lib/teacher_assistant_web/plug/require_password_change.ex`
- Modify: `lib/teacher_assistant_web/live_user_auth.ex:22-37`, `lib/teacher_assistant_web/router.ex` (`:school` pipeline, new live_session), `lib/teacher_assistant_web/controllers/auth_controller.ex:5-22`
- Test: `test/teacher_assistant_web/live/account/password_live_test.exs`

**Interfaces:**
- Consumes: `User.must_change_password`, action `:set_own_password` (Task 3), `Accounts.temporary_password_expired?/1`, `Accounts.revoke_all_sessions/1`, `Accounts.add_member_by_phone/2` (Task 4).
- Produces: route `/account/password` (`TeacherAssistantWeb.Account.PasswordLive`); every `:live_user_required` session and every `:school`-pipeline controller redirects there while `must_change_password` is true.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.Account.PasswordLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias TeacherAssistant.Accounts

  setup :register_and_log_in_user

  defp phone_teacher(scope) do
    {:ok, %{user: user, temporary_password: pw}} =
      Accounts.add_member_by_phone(scope, %{name: "Awa Nji", phone: "677123456", roles: [:teacher]})

    {user, pw}
  end

  test "a teacher with a temporary password is sent to /account/password", %{conn: conn, scope: scope, workspace: school} do
    {user, _pw} = phone_teacher(scope)
    conn = conn |> log_in_user(user) |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:redirect, %{to: "/account/password"}}} = live(conn, ~p"/school")
  end

  test "print route redirects", %{conn: conn, scope: scope, workspace: school} do
    {user, _pw} = phone_teacher(scope)
    conn = conn |> log_in_user(user) |> Plug.Conn.put_session(:workspace_id, school.id)

    conn = get(conn, ~p"/school/timetable/me/print")
    assert redirected_to(conn) == ~p"/account/password"
  end

  test "choosing a password lifts the gate", %{conn: conn, scope: scope, workspace: school} do
    {user, _pw} = phone_teacher(scope)
    conn = conn |> log_in_user(user) |> Plug.Conn.put_session(:workspace_id, school.id)

    {:ok, view, _html} = live(conn, ~p"/account/password")

    view
    |> form("#own-password-form", %{
      "form" => %{"password" => "my-own-pass", "password_confirmation" => "my-own-pass"}
    })
    |> render_submit()

    assert_redirect(view, ~p"/school")
    refute Ash.get!(Accounts.User, user.id, authorize?: false).must_change_password
  end

  test "mismatched confirmation shows an error", %{conn: conn, scope: scope, workspace: school} do
    {user, _pw} = phone_teacher(scope)
    conn = conn |> log_in_user(user) |> Plug.Conn.put_session(:workspace_id, school.id)
    {:ok, view, _html} = live(conn, ~p"/account/password")

    html =
      view
      |> form("#own-password-form", %{
        "form" => %{"password" => "my-own-pass", "password_confirmation" => "different"}
      })
      |> render_submit()

    assert html =~ "own-password-form"
    assert Ash.get!(Accounts.User, user.id, authorize?: false).must_change_password
  end

  test "a user without the flag is not redirected", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/school")
  end

  test "expired temporary password is refused", %{scope: scope} do
    {user, _pw} = phone_teacher(scope)

    Ash.Seed.update!(user, %{temporary_password_expires_at: DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second)})
    user = Ash.get!(Accounts.User, user.id, authorize?: false)

    conn =
      build_conn()
      |> init_test_session(%{})
      |> TeacherAssistantWeb.AuthController.success({:phone, :sign_in}, user, "unused-token")

    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expir"
  end
end
```

If `Ash.Seed.update!/2` is not available in this Ash version, use `Ecto.Adapters.SQL.query!(TeacherAssistant.Repo, "UPDATE users SET temporary_password_expires_at = now() - interval '1 day' WHERE id = $1", [Ecto.UUID.dump!(user.id)])`. Calling `success/4` directly requires `:fetch_flash`; if the call raises about the flash, pipe the conn through `Phoenix.ConnTest.bypass_through(conn, TeacherAssistantWeb.Router, [:browser]) |> get("/")` first.

- [ ] **Step 2: Run them, expect FAIL** (no route `/account/password`).

- [ ] **Step 3: Gate in `LiveUserAuth`**

Replace `on_mount(:live_user_required, …)` with:

```elixir
  def on_mount(:live_user_required, _params, session, socket) do
    socket = assign_scope(socket, session)
    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/sign-in")}

      # A temporary password must be replaced before anything else (spec
      # 2026-10-07); the change screen itself is the only exception.
      user.must_change_password and socket.view != TeacherAssistantWeb.Account.PasswordLive ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/account/password")}

      true ->
        socket =
          Phoenix.LiveView.attach_hook(socket, :current_path, :handle_params, fn _params,
                                                                                 uri,
                                                                                 socket ->
            {:cont, Phoenix.Component.assign(socket, :current_path, URI.parse(uri).path)}
          end)

        {:cont, socket}
    end
  end
```

- [ ] **Step 4: Controller plug**

```elixir
defmodule TeacherAssistantWeb.Plug.RequirePasswordChange do
  @moduledoc """
  Controller-side twin of the `LiveUserAuth` gate: a signed-in user who still
  holds a temporary password is sent to `/account/password`. Runs after
  `TeacherAssistantWeb.Plug.Scope` (which assigns `current_user`).
  """
  @behaviour Plug
  use TeacherAssistantWeb, :verified_routes

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{assigns: %{current_user: %{must_change_password: true}}} = conn, _opts) do
    conn
    |> Phoenix.Controller.redirect(to: ~p"/account/password")
    |> Plug.Conn.halt()
  end

  def call(conn, _opts), do: conn
end
```

In `router.ex`:

```elixir
  pipeline :school do
    plug TeacherAssistantWeb.Plug.Scope
    plug TeacherAssistantWeb.Plug.RequirePasswordChange
  end
```

and, next to the `:onboarding` live_session, add:

```elixir
    ash_authentication_live_session :account,
      session: [{TeacherAssistantWeb.LiveUserAuth, :session_context, []}],
      on_mount: [{TeacherAssistantWeb.LiveUserAuth, :live_user_required}] do
      live "/account/password", Account.PasswordLive
    end
```

(Put it inside the same `scope "/", TeacherAssistantWeb do pipe_through :browser` block that holds `:onboarding`.)

- [ ] **Step 5: The LiveView**

```elixir
defmodule TeacherAssistantWeb.Account.PasswordLive do
  @moduledoc "Forced first-sign-in password change for school-created accounts."
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Accounts.User

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :form, password_form(socket.assigns.current_user))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="own-password" class="mx-auto max-w-md space-y-6">
        <.page_header
          eyebrow={gettext("Votre compte")}
          title={gettext("Choisissez votre mot de passe")}
        />
        <p class="text-sm text-base-content/70">
          {gettext(
            "Votre établissement vous a donné un mot de passe temporaire. Choisissez-en un que vous seul·e connaissez (8 caractères au moins)."
          )}
        </p>

        <.form for={@form} id="own-password-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:password]} type="password" label={gettext("Nouveau mot de passe")} />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirmer le mot de passe")}
          />
          <button type="submit" class="btn btn-primary w-full" phx-disable-with={gettext("Enregistrement…")}>
            {gettext("Enregistrer")}
          </button>
        </.form>

        <.link href={~p"/sign-out"} class="link text-sm">{gettext("Se déconnecter")}</.link>
      </section>
    </Layouts.app>
    """
  end

  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Mot de passe enregistré."))
         |> push_navigate(to: ~p"/school")}

      {:error, form} ->
        {:noreply, assign(socket, :form, form)}
    end
  end

  defp password_form(%User{} = user) do
    user
    |> AshPhoenix.Form.for_update(:set_own_password, as: "form", actor: user)
    |> to_form()
  end
end
```

Check `/sign-out` exists as a GET in this app (`sign_out_route` in the router renders a page at `/sign-out`); if sign-out needs a different link in `Layouts`, copy that one.

The test asserts `assert_redirect(view, ~p"/school")` — `push_navigate` to another live_session is reported as a redirect by LiveViewTest; if it fails, change the assertion to `assert_redirect(view)` and check the path from its return value.

- [ ] **Step 6: Expiry in `AuthController.success/4`**

```elixir
  def success(conn, activity, user, _token) do
    if TeacherAssistant.Accounts.temporary_password_expired?(user) do
      # The temporary password was correct but is past its 7 days: no session.
      _ = TeacherAssistant.Accounts.revoke_all_sessions(user)

      conn
      |> put_flash(
        :error,
        gettext("Mot de passe temporaire expiré — demandez-en un nouveau à l'établissement.")
      )
      |> redirect(to: ~p"/sign-in")
    else
      sign_in(conn, activity, user)
    end
  end

  defp sign_in(conn, activity, user) do
    return_to = get_session(conn, :return_to) || ~p"/school"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> gettext("Your email address has now been confirmed")
        {:password, :reset} -> gettext("Your password has successfully been reset")
        _ -> gettext("You are now signed in")
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end
```

Also in `failure/3`, change the generic message to cover both identifiers: `gettext("Identifiant ou mot de passe incorrect")` (keep the msgid of the other branch unchanged).

- [ ] **Step 7: Run the tests**

Run: `mix test test/teacher_assistant_web/live/account/password_live_test.exs test/teacher_assistant_web/live/auth_smoke_test.exs`
Expected: PASS. Then `mix test --max-failures 10` — PASS (users created by fixtures have `must_change_password: false`).

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant_web/live/account/password_live.ex lib/teacher_assistant_web/plug/require_password_change.ex lib/teacher_assistant_web/live_user_auth.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/controllers/auth_controller.ex test/teacher_assistant_web/live/account/password_live_test.exs
git commit -m "feat: force a password change after a temporary password; refuse expired ones

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Sign-in page with a phone form

**Files:**
- Create: `lib/teacher_assistant_web/live/auth/sign_in_live.ex`, `lib/teacher_assistant_web/phone_auth_overrides.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (`sign_in_route` gets `live_view:`), `lib/teacher_assistant_web/components/layouts.ex` (`:sign_in` sub-copy)
- Test: `test/teacher_assistant_web/live/sign_in_phone_test.exs`

**Interfaces:**
- Consumes: strategies `:password` and `:phone` (Task 2).
- Produces: `/sign-in` shows the phone form first, « ou », then the email form; `/register` and `/reset` show only the email strategy (unchanged look).

Why a custom LiveView: AshAuthentication.Phoenix's `SignIn` component renders every strategy with one shared `identity_input_label` override and sorts strategies by name, so the phone form would be labelled « Adresse e-mail » and appear second. `sign_in_route` accepts `live_view:`; our LiveView embeds the library's `Components.Password` once per strategy, so credential handling stays in the library.

- [ ] **Step 1: Write the failing test**

```elixir
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

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    # Signed in, then sent on; the gate (Task 5) will catch the next page.
    assert redirected_to(conn) =~ "/"
    assert get_session(conn, "user_token") || get_session(conn, :user_token)
  end
end
```

The `#phone-sign-in form` selector relies on the wrapper id set in Step 3. If the sign-in form inside the Password component is not the only `form` there (the component also renders hidden register/reset forms for resettable strategies — the phone strategy has neither), narrow it with the form's own id: run `{:ok, _v, html} = live(conn, ~p"/sign-in"); IO.puts(html)` once in IEx/test and copy the id of the `<form>` containing `user[phone]`. Session key: check what `store_in_session/2` writes (`"user_token"` for subject `user`); adapt the last assertion to that key.

- [ ] **Step 2: Run it, expect FAIL** (no phone label / ordering).

- [ ] **Step 3: Overrides for the phone form and the LiveView**

`lib/teacher_assistant_web/phone_auth_overrides.ex`:

```elixir
defmodule TeacherAssistantWeb.PhoneAuthOverrides do
  @moduledoc """
  Overrides applied only to the phone strategy's form on `/sign-in`
  (placed before `TeacherAssistantWeb.AuthOverrides`, so these keys win).
  """
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.Components

  override Components.Password.Input do
    set :identity_input_label, "Numéro de téléphone"
    set :identity_input_placeholder, "6XX XX XX XX"
  end
end
```

`lib/teacher_assistant_web/live/auth/sign_in_live.ex`:

```elixir
defmodule TeacherAssistantWeb.Auth.SignInLive do
  @moduledoc """
  Sign in / register / reset pages. Same session contract as
  `AshAuthentication.Phoenix.SignInLive` (it is mounted by `sign_in_route`),
  but renders the library's `Password` component per strategy instead of the
  all-strategies `SignIn` component: the phone form first with its own label,
  then the email form. Register and reset only exist for the email strategy.
  """
  use TeacherAssistantWeb, :live_view

  alias AshAuthentication.Info
  alias AshAuthentication.Phoenix.Components
  alias TeacherAssistant.Accounts.User

  def mount(_params, session, socket) do
    overrides = Map.get(session, "overrides", [AshAuthentication.Phoenix.Overrides.Default])

    {:ok,
     socket
     |> assign(:overrides, overrides)
     |> assign(:phone_overrides, [TeacherAssistantWeb.PhoneAuthOverrides | overrides])
     |> assign(:path, session["path"] || "/")
     |> assign(:reset_path, session["reset_path"])
     |> assign(:register_path, session["register_path"])
     |> assign(:current_tenant, session["tenant"])
     |> assign(:context, session["context"] || %{})
     |> assign(:auth_routes_prefix, session["auth_routes_prefix"])
     |> assign(:gettext_fn, session["gettext_fn"])
     |> assign(:phone_strategy, Info.strategy!(User, :phone))
     |> assign(:email_strategy, Info.strategy!(User, :password))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="w-full space-y-6">
      <div :if={@live_action == :sign_in} id="phone-sign-in">
        <.live_component
          module={Components.Password}
          id="phone-strategy"
          strategy={@phone_strategy}
          live_action={:sign_in}
          path={@path}
          auth_routes_prefix={@auth_routes_prefix}
          reset_path={nil}
          register_path={nil}
          overrides={@phone_overrides}
          current_tenant={@current_tenant}
          context={@context}
          gettext_fn={@gettext_fn}
        />
      </div>

      <div :if={@live_action == :sign_in} class="divider text-xs text-base-content/60">
        {gettext("ou avec votre adresse e-mail")}
      </div>

      <div id="email-sign-in">
        <.live_component
          module={Components.Password}
          id="email-strategy"
          strategy={@email_strategy}
          live_action={@live_action}
          path={@path}
          auth_routes_prefix={@auth_routes_prefix}
          reset_path={@reset_path}
          register_path={@register_path}
          overrides={@overrides}
          current_tenant={@current_tenant}
          context={@context}
          gettext_fn={@gettext_fn}
        />
      </div>
    </div>
    """
  end
end
```

`gettext` here is the app's; the divider must be translated. If the library's `Password` component requires any other assign (compile/runtime error names it), copy it from `AshAuthentication.Phoenix.Components.SignIn.strategies/1` (`deps/ash_authentication_phoenix/lib/ash_authentication_phoenix/components/sign_in.ex:160-183`).

In `router.ex`, add `live_view: TeacherAssistantWeb.Auth.SignInLive,` to the `sign_in_route` options (keep every other option).

In `layouts.ex` (the `:sign_in` copy, ~line 622), change `sub:` to `"Entrez le numéro de téléphone ou l'adresse fournis par votre établissement."`.

- [ ] **Step 4: Run the tests**

Run: `mix test test/teacher_assistant_web/live/sign_in_phone_test.exs test/teacher_assistant_web/live/auth_smoke_test.exs`
Expected: PASS. The smoke test's magic-link assertion (`hidden`) still holds because the hidden markup also comes from the Password component overrides; if the smoke test checked magic-link markup specifically, update that assertion to reflect that magic link is no longer rendered on `/sign-in` (it was already visually hidden; its routes stay).

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant_web/live/auth/sign_in_live.ex lib/teacher_assistant_web/phone_auth_overrides.ex lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/components/layouts.ex test/teacher_assistant_web/live/sign_in_phone_test.exs test/teacher_assistant_web/live/auth_smoke_test.exs
git commit -m "feat: sign in with a phone number

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Members page — create, show once, reset; display names

**Files:**
- Modify: `lib/teacher_assistant_web/live/school/members_live.ex`, `assets/js/app.js`
- Modify (display): `lib/teacher_assistant/assessment.ex:481`, `lib/teacher_assistant_web/components/layouts.ex:67,295`, `lib/teacher_assistant_web/live/school/correction_review_live.ex:146`, `lib/teacher_assistant_web/live/school/assignments_live.ex:125,139`, `lib/teacher_assistant_web/live/school/class_live.ex:263,427,470`, `lib/teacher_assistant_web/live/school/sanctions_live.ex:154`, `lib/teacher_assistant_web/live/school/bulletins_live.ex:201`, `lib/teacher_assistant_web/controllers/timetable_print_controller.ex:42`, `lib/teacher_assistant_web/live/admin/schools_live.ex:39`, `lib/teacher_assistant_web/controllers/school_invitation_controller.ex:16`
- Test: `test/teacher_assistant_web/live/school/members_live_test.exs`

**Interfaces:**
- Consumes: `Accounts.add_member_by_phone/2`, `Accounts.reset_member_password/2`, `Accounts.can_reset_member_password?/2` (Task 4); `User.display_name/1`, `User.contact/1` (Task 2).

- [ ] **Step 1: Write the failing tests**

Append to `members_live_test.exs`:

```elixir
  describe "phone accounts" do
    test "head creates an account and sees the temporary password once", %{conn: conn, scope: scope} do
      {:ok, view, _html} = live(conn, ~p"/school/members")

      view
      |> form("#create-account-form", %{
        "account" => %{"name" => "Awa Nji", "phone" => "6 77 12 34 56", "roles" => ["teacher"]}
      })
      |> render_submit()

      assert has_element?(view, "#temporary-password-dialog")
      assert view |> element("#temporary-password") |> render() =~ ~r/[a-z]{4}-[a-z]{4}-\d{4}/
      assert has_element?(view, "#members-table", "Awa Nji")
      assert has_element?(view, "#members-table", "6 77 12 34 56")

      view |> element("#close-temporary-password") |> render_click()
      refute has_element?(view, "#temporary-password-dialog")
      assert Enum.any?(Accounts.list_members(scope), &(&1.user.name == "Awa Nji"))
    end

    test "invalid phone shows a field error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/school/members")

      html =
        view
        |> form("#create-account-form", %{"account" => %{"name" => "X", "phone" => "12"}})
        |> render_submit()

      assert html =~ "numéro de téléphone"
      refute has_element?(view, "#temporary-password-dialog")
    end

    test "an existing account is linked without a password", %{conn: conn} do
      %{scope: other} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()
      {:ok, _} = Accounts.add_member_by_phone(other, %{name: "Awa Nji", phone: "677123456", roles: [:teacher]})

      {:ok, view, _html} = live(conn, ~p"/school/members")

      html =
        view
        |> form("#create-account-form", %{"account" => %{"name" => "Autre", "phone" => "677123456"}})
        |> render_submit()

      assert html =~ "Awa Nji"
      refute has_element?(view, "#temporary-password-dialog")
    end

    test "reset button only for accounts this school created", %{conn: conn, scope: scope} do
      {:ok, %{user: own}} = Accounts.add_member_by_phone(scope, %{name: "Own", phone: "677000001", roles: [:teacher]})
      %{scope: other} = TeacherAssistant.TeacherFixtures.setup_complete_school_fixture()
      {:ok, %{user: linked}} = Accounts.add_member_by_phone(other, %{name: "Linked", phone: "677000002", roles: [:teacher]})
      {:ok, _} = Accounts.add_member_by_phone(scope, %{name: "Linked", phone: "677000002", roles: [:teacher]})

      {:ok, view, _html} = live(conn, ~p"/school/members")
      own_m = Enum.find(Accounts.list_members(scope), &(&1.user_id == own.id))
      linked_m = Enum.find(Accounts.list_members(scope), &(&1.user_id == linked.id))

      assert has_element?(view, "#reset-password-#{own_m.id}")
      refute has_element?(view, "#reset-password-#{linked_m.id}")

      view |> element("#reset-password-#{own_m.id}") |> render_click()
      assert has_element?(view, "#temporary-password-dialog")
    end
  end
```

`register_and_log_in_user` already provides `scope` (the head's) and puts the school in the session, so `/school/members` opens directly.

- [ ] **Step 2: Run them, expect FAIL** (`#create-account-form` missing).

- [ ] **Step 3: Members LiveView**

In `mount/3`, add assigns: `|> assign(:account_form, account_form())` and `|> assign(:temporary_password, nil)`.

In `reload_members/1`, also assign the resettable set (computed here, never in render):

```elixir
  defp reload_members(socket) do
    scope = socket.assigns.scope
    members = Accounts.list_members(scope)

    resettable =
      if socket.assigns.can_manage_staff?,
        do: for(m <- members, Accounts.can_reset_member_password?(scope, m.user), into: MapSet.new(), do: m.id),
        else: MapSet.new()

    socket
    |> assign(:members, members)
    |> assign(:resettable_member_ids, resettable)
    |> assign(:invitations, Accounts.list_pending_invitations(scope))
  end
```

Member name cell (replace lines ~44–47):

```heex
                  <span class="block font-medium">{User.display_name(m.user)}</span>
                  <span
                    :if={m.user.name && User.contact(m.user)}
                    class="block text-xs text-base-content/60"
                  >
                    {User.contact(m.user)}
                  </span>
```

Add `alias TeacherAssistant.Accounts.User` at the top.

In the actions cell for each row (inside the existing `:if={@can_manage_staff?}` cell, next to the existing deactivate control), add:

```heex
                  <button
                    :if={MapSet.member?(@resettable_member_ids, m.id)}
                    id={"reset-password-#{m.id}"}
                    type="button"
                    class="btn btn-ghost btn-xs"
                    phx-click="reset_password"
                    phx-value-id={m.id}
                    data-confirm={gettext("Donner un nouveau mot de passe temporaire ? La personne sera déconnectée partout.")}
                  >
                    {gettext("Réinitialiser le mot de passe")}
                  </button>
```

Next to the invite form (same `:if={@can_manage_staff?}` container), add the create form:

```heex
          <.form
            for={@account_form}
            id="create-account-form"
            phx-submit="create_account"
            class="ta-leaf space-y-3 p-4"
          >
            <h3 class="font-semibold">{gettext("Créer un compte avec un numéro de téléphone")}</h3>
            <p class="text-sm text-base-content/70">
              {gettext("Pour les personnes sans adresse e-mail. Vous recevrez un mot de passe temporaire à leur transmettre.")}
            </p>
            <.input field={@account_form[:name]} label={gettext("Nom et prénom")} required />
            <.input
              field={@account_form[:phone]}
              type="tel"
              label={gettext("Numéro de téléphone")}
              placeholder="6XX XX XX XX"
              required
            />
            <div class="flex flex-wrap gap-2">
              <label :for={role <- SchoolRole.values()} class="label cursor-pointer gap-1">
                <input
                  type="checkbox"
                  name="account[roles][]"
                  value={role}
                  checked={role == :teacher}
                  class="checkbox checkbox-sm"
                />
                <span>{SchoolRole.label(role)}</span>
              </label>
            </div>
            <button type="submit" class="btn btn-primary btn-sm" phx-disable-with={gettext("Création…")}>
              {gettext("Créer le compte")}
            </button>
          </.form>
```

Copy the role checkbox markup from the existing invite form (lines ~136–147) if `SchoolRole.label/1` is named differently there; also copy its membership-status `<.input type="select">` and name it `account[membership_status]`.

Dialog, at the end of the section:

```heex
        <dialog
          :if={@temporary_password}
          id="temporary-password-dialog"
          class="modal modal-open"
          aria-labelledby="temporary-password-title"
        >
          <div class="modal-box space-y-4">
            <h3 id="temporary-password-title" class="text-lg font-semibold">
              {gettext("Mot de passe temporaire")}
            </h3>
            <p class="text-sm">
              {gettext("Transmettez-le à %{name} avec son numéro. Il ne sera plus affiché. Valable 7 jours ; un nouveau mot de passe sera demandé à la première connexion.",
                name: @temporary_password.name
              )}
            </p>
            <div class="flex items-center gap-2">
              <code id="temporary-password" class="rounded bg-base-200 px-3 py-2 font-mono text-lg">{@temporary_password.value}</code>
              <button
                type="button"
                class="btn btn-sm"
                phx-click={JS.dispatch("phx:copy", to: "#temporary-password")}
              >
                <.icon name="hero-clipboard-document" class="size-4" /> {gettext("Copier")}
              </button>
            </div>
            <div class="modal-action">
              <button id="close-temporary-password" type="button" class="btn btn-primary" phx-click="close_temporary_password">
                {gettext("C'est noté")}
              </button>
            </div>
          </div>
        </dialog>
```

`JS` is available in LiveViews generated with `use TeacherAssistantWeb, :live_view` (Phoenix 1.8 imports `Phoenix.LiveView.JS` alias); if not, add `alias Phoenix.LiveView.JS`.

Event handlers:

```elixir
  def handle_event("create_account", %{"account" => params}, socket) do
    scope = socket.assigns.scope

    attrs = %{
      name: params["name"],
      phone: params["phone"],
      roles: parse_roles(params["roles"]),
      membership_status: parse_membership_status(params["membership_status"])
    }

    case Accounts.add_member_by_phone(scope, attrs) do
      {:ok, %{user: user, temporary_password: nil}} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Compte existant ajouté : %{name}", name: User.display_name(user)))
         |> assign(:account_form, account_form())
         |> reload_members()}

      {:ok, %{user: user, temporary_password: password}} ->
        {:noreply,
         socket
         |> assign(:temporary_password, %{name: User.display_name(user), value: password})
         |> assign(:account_form, account_form())
         |> reload_members()}

      {:error, :invalid_phone} ->
        {:noreply,
         assign(
           socket,
           :account_form,
           account_form(params, phone: {gettext("Ce numéro de téléphone n'est pas valide."), []})
         )}

      {:error, :already_member} ->
        {:noreply, put_flash(socket, :error, gettext("Déjà membre de l'établissement."))}

      {:error, :forbidden} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Impossible de créer le compte."))}
    end
  end

  def handle_event("reset_password", %{"id" => id}, socket) do
    scope = socket.assigns.scope

    with %{} = membership <- find_membership(scope, id),
         {:ok, password} <- Accounts.reset_member_password(scope, membership) do
      {:noreply,
       assign(socket, :temporary_password, %{
         name: User.display_name(membership.user),
         value: password
       })}
    else
      {:error, %Ash.Error.Forbidden{}} -> {:noreply, Authz.put_not_allowed(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Impossible de réinitialiser le mot de passe."))}
    end
  end

  def handle_event("close_temporary_password", _params, socket) do
    {:noreply, assign(socket, :temporary_password, nil)}
  end

  defp account_form(params \\ %{}, errors \\ []) do
    to_form(params, as: "account", errors: errors)
  end
```

`find_membership/2` and `parse_membership_status/1` already exist in this module; confirm `find_membership` returns the membership with `:user` loaded (it comes from `list_members`); if not, `Ash.load!(membership, :user, scope: scope)` before `display_name`.

`assets/js/app.js` — add once, near other `window.addEventListener` calls:

```js
// Members page: copy the temporary password shown once to the clipboard.
window.addEventListener("phx:copy", (event) => {
  if (navigator.clipboard) navigator.clipboard.writeText(event.target.textContent.trim())
})
```

- [ ] **Step 4: Replace the `name || email` call sites**

Each of these becomes `User.display_name(<user>)` (add `alias TeacherAssistant.Accounts.User` where missing; in modules that already alias another `User`, call `TeacherAssistant.Accounts.User.display_name/1`):

- `lib/teacher_assistant/assessment.ex:481` — `defp user_name(user), do: User.display_name(user)`
- `lib/teacher_assistant_web/components/layouts.ex:67` — `String.upcase(String.slice(User.display_name(current_user), 0, 1))`
- `lib/teacher_assistant_web/components/layouts.ex:295` — show `User.contact(@current_user) || User.display_name(@current_user)` in place of `@current_user.email`
- `correction_review_live.ex:146`, `bulletins_live.ex:201`, `sanctions_live.ex:154`, `assignments_live.ex:125,139`, `class_live.ex:263,427,470`, `timetable_print_controller.ex:42` — `User.display_name(...)` (for `assignments_live.ex:139` keep the `String.downcase/1` around it)
- `admin/schools_live.ex:39` — `{User.contact(p.owner_user)}`
- `school_invitation_controller.ex:16` — `current_user.email && to_string(current_user.email) == to_string(invitation.email)` so an email-less user never matches an invitation

Run `grep -rnE "\.email\b" lib/teacher_assistant_web lib/teacher_assistant/assessment.ex` afterwards; the only remaining `user.email` reads should be in email senders, invitation logic and the forms that edit emails.

- [ ] **Step 5: Run the tests**

Run: `mix test test/teacher_assistant_web/live/school/ test/teacher_assistant_web/live/admin test/teacher_assistant_web/controllers`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/teacher_assistant_web/live/school/members_live.ex assets/js/app.js lib/teacher_assistant/assessment.ex lib/teacher_assistant_web/components/layouts.ex lib/teacher_assistant_web/live/school/correction_review_live.ex lib/teacher_assistant_web/live/school/assignments_live.ex lib/teacher_assistant_web/live/school/class_live.ex lib/teacher_assistant_web/live/school/sanctions_live.ex lib/teacher_assistant_web/live/school/bulletins_live.ex lib/teacher_assistant_web/controllers/timetable_print_controller.ex lib/teacher_assistant_web/live/admin/schools_live.ex lib/teacher_assistant_web/controllers/school_invitation_controller.ex test/teacher_assistant_web/live/school/members_live_test.exs
git commit -m "feat: create phone accounts and reset passwords from the Members page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Translations, final migration, precommit

**Files:**
- Modify: `priv/gettext/default.pot`, `priv/gettext/errors.pot` (if present), `priv/gettext/{fr,en}/LC_MESSAGES/{default,errors}.po`
- Possibly: `priv/repo/migrations/*` (codegen squash)

- [ ] **Step 1: Extract and merge**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Fill every new entry, no fuzzy left**

In `en/LC_MESSAGES/default.po` give each new msgid an English msgstr; in `fr/LC_MESSAGES/default.po` set msgstr to the French msgid. Remove every `#, fuzzy` flag on entries you filled (fuzzy entries render the wrong text — see memory "Gettext renders fuzzy text"). Also add the Ash error `"is not a valid phone number"` to `errors.po` (FR: « n'est pas un numéro de téléphone valide », EN: same as msgid).

Check: `grep -n "fuzzy" priv/gettext/*/LC_MESSAGES/*.po` → nothing new; `mix test test/teacher_assistant_web/gettext_fuzzy_test.exs` → PASS.

- [ ] **Step 3: Consolidate dev migrations**

Run: `mix ash.codegen phone_accounts`
Expected: the `_dev` migration(s) from Task 2 are replaced by one named migration. Then `mix ash.setup` and `MIX_ENV=test mix ecto.reset` if the test DB complains.

- [ ] **Step 4: Full check**

Run: `mix compile --warnings-as-errors` (the precommit alias misspells this flag, so run it yourself) → no warnings.
Run: `mix precommit` → all tests pass. Its `format` step rewrites files; stage what it changed.

- [ ] **Step 5: Commit**

```bash
git add priv/gettext priv/repo/migrations priv/resource_snapshots <files reformatted by precommit>
git commit -m "chore: translations and migration for phone accounts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Manual check in the browser (dev seed)**

`mix phx.server`, sign in as `demo@example.com` / `password1234`, open `/school/members`, create an account for `677 00 00 01`, copy the password, sign out, sign in on `/sign-in` with `6 77 00 00 01` and that password, confirm you land on « Choisissez votre mot de passe », set one, and reach `/school`. Check the page at phone width (375 px).
