# KLM1 — Students and guardians Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parents and guardians on the student (shared by siblings, one main contact), optional date and place of
birth, a student profile page, and a school-wide student list.

**Architecture:** Two new tenant-scoped resources in the Enrollment domain — `Guardian` and the join
`StudentGuardian` (with a `primary_contact` flag guarded by a partial unique index) — whose multi-step rules
(first link becomes primary, one primary per student, orphan guardian deleted) live in actions and change
modules. `Student` gains `birth_date`/`birth_place`. Two new LiveViews, `StudentsLive` (`/school/students`) and
`StudentLive` (`/school/students/:id`), read through plain `Enrollment` domain functions taking a `%Scope{}`, as
the rest of the domain does. The paste import and the bulletin gain the new fields.

**Tech Stack:** Phoenix 1.8 LiveView, Ash 3.33 (attribute multitenancy, policies), AshPostgres, AshPhoenix.Form,
Gettext (French msgids).

**Spec:** `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` §"KLM1 — Students and guardians (spec)".

## Global Constraints

- Worktree `.claude/worktrees/klm1`, branch `klm1-students-guardians`, `MIX_TEST_PARTITION=3` for every
  `mix test`. Stage explicit paths only (other sessions share the checkout); never `git commit -a`.
- Never write migrations by hand: `mix ash.codegen --dev` while iterating, then one named
  `mix ash.codegen klm1_students_guardians` in Task 6. `mix ash.codegen --check` must be clean at the end.
- Enums are `Ash.Type.Enum` modules, never bare `:atom` attributes.
- Every Ash call carries `scope:`; inside a change/hook use `authorize?: false` only for the internal
  bookkeeping reads/writes named in this plan (they run after the action's own policy passed).
- `relationship` enum values: `:pere | :mere | :tuteur | :autre`. `language` enum values: `:fr | :en`, default
  `:fr`.
- Phone key: digits only; a leading `237` or `00237` is dropped when 9 digits remain; fewer than 8 digits is
  invalid (« numéro de téléphone invalide »).
- At most one `primary_contact` link per student; the first link of a student becomes primary; unlinking the
  primary promotes none; a guardian with no link left is deleted.
- Guardian and link reads: admins, `:conduct` (SG), the form master or a teacher of a class the student is
  enrolled in. Writes: admins and `:conduct`.
- Student list and profile editing: admins and `:conduct`. Profile reading: those plus the student's form
  masters and teachers.
- Strings through gettext; after `mix gettext.extract --merge`, fill every new `msgstr` in `priv/gettext/en` and
  fix every new fuzzy entry in both locales.
- `mix precommit` before the last commit (note: it rewrites files with `mix format`; re-stage them).

## Review Focus

1. Making a second guardian the main contact when one already is — the old one is unset in the same
   transaction; never two primaries, and the partial unique index still rejects a direct second insert (tests
   in Task 2).
2. The same parent typed as « +237 6 77 12 34 56 » for one child and « 677123456 » for a sibling — found by the
   phone lookup and linked, not duplicated, in the profile and in the import (tests in Task 2 and Task 5).
3. Unlinking a guardian shared by two siblings — the guardian survives for the other child; unlinking the
   last link deletes the guardian (test in Task 2).
4. A teacher who has no class with the student, opening `/school/students/:id` or reading the student's
   guardians — redirected, and no guardian row is readable through Ash (tests in Task 1 and Task 4).
5. A pasted import row with an impossible birth date (« 31/02/2010 ») or a short phone — the student is still
   imported; the bad date is dropped and the bad guardian is reported, not silently created (test in Task 5).

---

### Task 0: Worktree

- [ ] **Step 1: Create the worktree and check the baseline**

```bash
cd /Users/franckstfiler/Documents/projects/teacher-assistant
git worktree add .claude/worktrees/klm1 -b klm1-students-guardians main
cd .claude/worktrees/klm1 && mix deps.get
MIX_TEST_PARTITION=3 mix ecto.create && MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/class_live_test.exs
```

Expected: 0 failures.

---

### Task 1: Data — birth fields, Guardian, StudentGuardian, policies

**Files:**
- Create: `lib/teacher_assistant/academics/guardian_relationship.ex`
- Create: `lib/teacher_assistant/academics/contact_language.ex`
- Create: `lib/teacher_assistant/academics/guardian.ex`
- Create: `lib/teacher_assistant/academics/guardian/phone.ex`
- Create: `lib/teacher_assistant/academics/guardian/changes/phone_key.ex`
- Create: `lib/teacher_assistant/academics/student_guardian.ex`
- Create: `lib/teacher_assistant/academics/student_guardian/changes/primary_if_first.ex`
- Create: `lib/teacher_assistant/academics/student_guardian/changes/unset_other_primaries.ex`
- Create: `lib/teacher_assistant/academics/student_guardian/changes/delete_orphan_guardian.ex`
- Modify: `lib/teacher_assistant/academics/student.ex` (attributes, accepts, update policy, relationships)
- Modify: `lib/teacher_assistant/academics/class_group.ex` (relationships: `has_many :teaching_contexts`)
- Modify: `lib/teacher_assistant/enrollment.ex` (`resources` block)
- Test: `test/teacher_assistant/academics/guardian_test.exs`

**Interfaces:**
- Produces: `Academics.Guardian` (actions `:read`, `:create`, `:update`, `:destroy`, `:by_phone_key`
  (argument `phone_key`)); `Academics.StudentGuardian` (actions `:read`, `:for_student` (argument
  `student_id`, loads `:guardian`, primary first), `:link` (accepts `student_id`, `guardian_id`),
  `:make_primary`, `:unlink`, `:destroy`); `Academics.Guardian.Phone.key/1 :: String.t() | nil`;
  `Student` attributes `birth_date :: Date | nil`, `birth_place :: String | nil`, relationships
  `guardian_links` (has_many `StudentGuardian`), `primary_guardian_link` (has_one, `primary_contact == true`);
  `ClassGroup.teaching_contexts`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.GuardianTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.Academics.{Guardian, StudentGuardian}
  alias TeacherAssistant.Academics.Guardian.Phone
  alias TeacherAssistant.{Enrollment, Organization}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Nkolo", sex: :f})
    %{scope: scope, cg: cg, awa: awa}
  end

  defp create_guardian(scope, attrs) do
    Guardian
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(%{full_name: "Jean Nkolo", relationship: :pere, phone: "677 12 34 56"}, attrs),
      scope: scope
    )
    |> Ash.create()
  end

  describe "Phone.key/1" do
    test "keeps digits and drops the Cameroon prefix" do
      assert Phone.key("+237 6 77 12 34 56") == "677123456"
      assert Phone.key("00237677123456") == "677123456"
      assert Phone.key("677-12-34-56") == "677123456"
      assert Phone.key("237") == "237"
      assert Phone.key(nil) == nil
    end
  end

  test "a guardian stores a phone key and refuses a short number", %{scope: scope} do
    assert {:ok, g} = create_guardian(scope, %{phone: "+237 677 12 34 56"})
    assert g.phone_key == "677123456"
    assert g.language == :fr

    assert {:error, %Ash.Error.Invalid{}} = create_guardian(scope, %{phone: "12 34"})
  end

  test "the student gains an optional date and place of birth", %{scope: scope, awa: awa} do
    {:ok, awa} =
      Enrollment.update_student(awa, %{birth_date: ~D[2013-04-02], birth_place: "Yaoundé"},
        scope: scope
      )

    assert awa.birth_date == ~D[2013-04-02]
    assert awa.birth_place == "Yaoundé"

    assert {:error, %Ash.Error.Invalid{}} =
             Enrollment.update_student(awa, %{birth_date: ~D[2099-01-01]}, scope: scope)
  end

  test "the first link becomes the main contact; the partial index forbids a second", %{
    scope: scope,
    awa: awa
  } do
    {:ok, g1} = create_guardian(scope, %{})
    {:ok, g2} = create_guardian(scope, %{full_name: "Marie Nkolo", relationship: :mere, phone: "699 00 00 01"})

    link = fn g ->
      StudentGuardian
      |> Ash.Changeset.for_create(:link, %{student_id: awa.id, guardian_id: g.id}, scope: scope)
      |> Ash.create()
    end

    assert {:ok, %{primary_contact: true}} = link.(g1)
    assert {:ok, %{primary_contact: false}} = link.(g2)
    assert {:error, _} = link.(g1)

    assert {:error, _} =
             StudentGuardian
             |> Ash.Changeset.for_create(:create, %{
               student_id: awa.id,
               guardian_id: g2.id,
               primary_contact: true
             })
             |> Ash.create(scope: scope, authorize?: false)
  end

  test "a plain teacher with no class of the student cannot read or write guardians", %{
    scope: scope,
    awa: awa
  } do
    {:ok, g} = create_guardian(scope, %{})

    {:ok, _} =
      StudentGuardian
      |> Ash.Changeset.for_create(:link, %{student_id: awa.id, guardian_id: g.id}, scope: scope)
      |> Ash.create()

    stranger = member_scope_fixture(scope, %{roles: [:teacher]})

    assert Ash.read!(Guardian, scope: stranger) == []
    assert Ash.read!(StudentGuardian, scope: stranger) == []
    assert_forbidden(create_guardian(stranger, %{phone: "699 11 22 33"}))
  end

  test "the student's form master reads them; the SG writes them", %{scope: scope, cg: cg, awa: awa} do
    {:ok, g} = create_guardian(scope, %{})

    {:ok, _} =
      StudentGuardian
      |> Ash.Changeset.for_create(:link, %{student_id: awa.id, guardian_id: g.id}, scope: scope)
      |> Ash.create()

    master = member_scope_fixture(scope, %{roles: [:teacher]})
    {:ok, _} = Enrollment.set_form_master(scope, cg, master.current_user.id)
    assert [%{id: id}] = Ash.read!(Guardian, scope: master)
    assert id == g.id

    sg = member_scope_fixture(scope, %{roles: [:discipline_master]})
    assert {:ok, _} = create_guardian(sg, %{phone: "699 11 22 33"})
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/guardian_test.exs`
Expected: FAIL — `TeacherAssistant.Academics.Guardian` is not available.

- [ ] **Step 3: Enums and the phone key**

```elixir
# lib/teacher_assistant/academics/guardian_relationship.ex
defmodule TeacherAssistant.Academics.GuardianRelationship do
  @moduledoc "Spec KLM1: how a guardian is related to the student."
  use Ash.Type.Enum, values: [:pere, :mere, :tuteur, :autre]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:pere), do: gettext("Père")
  def label(:mere), do: gettext("Mère")
  def label(:tuteur), do: gettext("Tuteur")
  def label(:autre), do: gettext("Autre")
end
```

```elixir
# lib/teacher_assistant/academics/contact_language.ex
defmodule TeacherAssistant.Academics.ContactLanguage do
  @moduledoc "Spec KLM1: the language a guardian is written to in."
  use Ash.Type.Enum, values: [:fr, :en]
  use Gettext, backend: TeacherAssistantWeb.Gettext

  def label(:fr), do: gettext("Français")
  def label(:en), do: gettext("Anglais")
end
```

```elixir
# lib/teacher_assistant/academics/guardian/phone.ex
defmodule TeacherAssistant.Academics.Guardian.Phone do
  @moduledoc "Spec KLM1: the comparable form of a phone number (duplicate lookup)."

  @doc "Digits only; a leading 237 or 00237 is dropped when 9 digits remain."
  def key(nil), do: nil

  def key(phone) when is_binary(phone) do
    case String.replace(phone, ~r/\D/, "") do
      "00237" <> rest when byte_size(rest) == 9 -> rest
      "237" <> rest when byte_size(rest) == 9 -> rest
      digits -> digits
    end
  end

  @doc "Whether `phone` is long enough to be a real number."
  def valid?(phone), do: String.length(key(phone) || "") >= 8
end
```

```elixir
# lib/teacher_assistant/academics/guardian/changes/phone_key.ex
defmodule TeacherAssistant.Academics.Guardian.Changes.PhoneKey do
  @moduledoc "Keeps `phone_key` in step with `phone`; refuses a number too short to be real."
  use Ash.Resource.Change

  alias TeacherAssistant.Academics.Guardian.Phone

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :phone) do
      {:ok, phone} when is_binary(phone) ->
        if Phone.valid?(phone) do
          Ash.Changeset.force_change_attribute(changeset, :phone_key, Phone.key(phone))
        else
          Ash.Changeset.add_error(changeset,
            field: :phone,
            message: "numéro de téléphone invalide"
          )
        end

      _ ->
        changeset
    end
  end

  # Only reads values set on the changeset itself, so it is safe in an atomic update.
  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
```

- [ ] **Step 4: The Guardian resource**

```elixir
# lib/teacher_assistant/academics/guardian.ex
defmodule TeacherAssistant.Academics.Guardian do
  @moduledoc """
  Spec KLM1 (M2): a parent or guardian of one or more students of the school.
  Shared by siblings through `StudentGuardian`; no login.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.Guardian.Changes.PhoneKey

  postgres do
    table "guardians"
    repo TeacherAssistant.Repo

    custom_indexes do
      # Composite-FK target, as on every tenant resource.
      index [:id], unique: true
      index [:workspace_id, :phone_key]
    end

    references do
      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:full_name, :relationship, :phone, :phone_2, :email, :language]
      change PhoneKey
    end

    update :update do
      primary? true
      accept [:full_name, :relationship, :phone, :phone_2, :email, :language]
      change PhoneKey
    end

    read :by_phone_key do
      argument :phone_key, :string, allow_nil?: false
      filter expr(phone_key == ^arg(:phone_key))
      prepare build(sort: [full_name: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(exists(student_links.student.enrollments, class_group.form_master_user_id == ^actor(:id)))

      authorize_if expr(
                     exists(
                       student_links.student.enrollments.class_group.teaching_contexts,
                       teacher_user_id == ^actor(:id)
                     )
                   )
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :full_name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 120]

    attribute :relationship, TeacherAssistant.Academics.GuardianRelationship,
      allow_nil?: false,
      public?: true

    attribute :phone, :string, allow_nil?: false, public?: true, constraints: [max_length: 30]
    attribute :phone_key, :string, allow_nil?: false
    attribute :phone_2, :string, public?: true, constraints: [max_length: 30]
    attribute :email, :ci_string, public?: true

    attribute :language, TeacherAssistant.Academics.ContactLanguage,
      allow_nil?: false,
      default: :fr,
      public?: true

    timestamps()
  end

  relationships do
    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end

    has_many :student_links, TeacherAssistant.Academics.StudentGuardian
  end
end
```

- [ ] **Step 5: The StudentGuardian join and its changes**

```elixir
# lib/teacher_assistant/academics/student_guardian.ex
defmodule TeacherAssistant.Academics.StudentGuardian do
  @moduledoc """
  Spec KLM1 (M2): a guardian of a student. At most one link per student is the
  main contact (`primary_contact`), enforced by a partial unique index; the
  first link becomes primary; unlinking the last link of a guardian deletes it.
  """
  use Ash.Resource,
    otp_app: :teacher_assistant,
    domain: TeacherAssistant.Enrollment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias TeacherAssistant.Accounts.Checks
  alias TeacherAssistant.Academics.StudentGuardian.Changes

  postgres do
    table "student_guardians"
    repo TeacherAssistant.Repo

    custom_indexes do
      index [:id], unique: true

      index [:workspace_id, :student_id],
        unique: true,
        where: "primary_contact",
        name: "student_guardians_one_primary_index",
        message: "a student has only one main contact"
    end

    references do
      reference :student,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :guardian,
        on_delete: :delete,
        match_with: [workspace_id: :workspace_id],
        match_type: :full,
        index?: true

      reference :workspace, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy, create: [:student_id, :guardian_id, :primary_contact]]

    read :for_student do
      argument :student_id, :uuid, allow_nil?: false
      filter expr(student_id == ^arg(:student_id))
      prepare build(load: [:guardian], sort: [primary_contact: :desc, inserted_at: :asc])
    end

    create :link do
      accept [:student_id, :guardian_id]
      change Changes.PrimaryIfFirst
    end

    update :make_primary do
      require_atomic? false
      change Changes.UnsetOtherPrimaries
      change set_attribute(:primary_contact, true)
    end

    # Internal: used by `make_primary` to clear the previous main contact.
    update :unset_primary do
      change set_attribute(:primary_contact, false)
    end

    destroy :unlink do
      require_atomic? false
      change Changes.DeleteOrphanGuardian
    end
  end

  policies do
    policy action_type(:read) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(exists(student.enrollments, class_group.form_master_user_id == ^actor(:id)))

      authorize_if expr(
                     exists(
                       student.enrollments.class_group.teaching_contexts,
                       teacher_user_id == ^actor(:id)
                     )
                   )
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
    end
  end

  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :primary_contact, :boolean, allow_nil?: false, default: false, public?: true
    timestamps()
  end

  relationships do
    belongs_to :student, TeacherAssistant.Academics.Student do
      source_attribute :student_id
      allow_nil? false
      public? true
    end

    belongs_to :guardian, TeacherAssistant.Academics.Guardian do
      source_attribute :guardian_id
      allow_nil? false
      public? true
    end

    belongs_to :workspace, TeacherAssistant.Academics.Workspace do
      source_attribute :workspace_id
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_link, [:student_id, :guardian_id]
  end
end
```

```elixir
# lib/teacher_assistant/academics/student_guardian/changes/primary_if_first.ex
defmodule TeacherAssistant.Academics.StudentGuardian.Changes.PrimaryIfFirst do
  @moduledoc "A student's first guardian link becomes the main contact."
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.StudentGuardian

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      student_id = Ash.Changeset.get_attribute(changeset, :student_id)

      # Bookkeeping read after the action's own policy passed.
      has_primary? =
        StudentGuardian
        |> Ash.Query.filter(student_id == ^student_id and primary_contact == true)
        |> Ash.Query.set_tenant(changeset.tenant)
        |> Ash.exists?(authorize?: false)

      Ash.Changeset.force_change_attribute(changeset, :primary_contact, not has_primary?)
    end)
  end
end
```

```elixir
# lib/teacher_assistant/academics/student_guardian/changes/unset_other_primaries.ex
defmodule TeacherAssistant.Academics.StudentGuardian.Changes.UnsetOtherPrimaries do
  @moduledoc "Before a link becomes the main contact, clears the student's previous one."
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.StudentGuardian

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{id: id, student_id: student_id} = changeset.data

      StudentGuardian
      |> Ash.Query.filter(student_id == ^student_id and primary_contact == true and id != ^id)
      |> Ash.Query.set_tenant(changeset.tenant)
      |> Ash.read!(authorize?: false)
      |> Enum.each(fn link ->
        link
        |> Ash.Changeset.for_update(:unset_primary, %{},
          tenant: changeset.tenant,
          authorize?: false
        )
        |> Ash.update!()
      end)

      changeset
    end)
  end
end
```

```elixir
# lib/teacher_assistant/academics/student_guardian/changes/delete_orphan_guardian.ex
defmodule TeacherAssistant.Academics.StudentGuardian.Changes.DeleteOrphanGuardian do
  @moduledoc "After the last link of a guardian is removed, the guardian is deleted."
  use Ash.Resource.Change

  require Ash.Query

  alias TeacherAssistant.Academics.{Guardian, StudentGuardian}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, link ->
      guardian_id = link.guardian_id

      orphan? =
        not (StudentGuardian
             |> Ash.Query.filter(guardian_id == ^guardian_id)
             |> Ash.Query.set_tenant(changeset.tenant)
             |> Ash.exists?(authorize?: false))

      if orphan? do
        Guardian
        |> Ash.get!(guardian_id, tenant: changeset.tenant, authorize?: false)
        |> Ash.destroy!(tenant: changeset.tenant, authorize?: false)
      end

      {:ok, link}
    end)
  end
end
```

- [ ] **Step 6: Student, ClassGroup and the domain's resource list**

In `lib/teacher_assistant/academics/student.ex`:

```elixir
  actions do
    defaults [
      :read,
      :destroy,
      create: [:full_name, :sex, :matricule, :birth_date, :birth_place],
      update: [:full_name, :sex, :matricule, :birth_date, :birth_place]
    ]
    # … the three existing reads stay as they are …
  end

  validations do
    validate compare(:birth_date, less_than_or_equal_to: &Date.utc_today/0),
      where: [present(:birth_date)],
      message: "la date de naissance ne peut pas être dans le futur"
  end
```

Update policy — add the SG:

```elixir
    policy action_type(:update) do
      forbid_unless {Checks.SchoolRole, any_of: :member}
      authorize_if {Checks.SchoolRole, any_of: :admin}
      authorize_if {Checks.SchoolRole, any_of: :conduct}
      authorize_if expr(exists(enrollments, class_group.form_master_user_id == ^actor(:id)))
    end
```

Attributes and relationships:

```elixir
    attribute :birth_date, :date, allow_nil?: true, public?: true
    attribute :birth_place, :string, allow_nil?: true, public?: true, constraints: [max_length: 120]
```

```elixir
    has_many :guardian_links, TeacherAssistant.Academics.StudentGuardian

    has_one :primary_guardian_link, TeacherAssistant.Academics.StudentGuardian do
      filter expr(primary_contact == true)
    end
```

In `lib/teacher_assistant/academics/class_group.ex` relationships:

```elixir
    has_many :teaching_contexts, TeacherAssistant.Academics.TeachingContext
```

In `lib/teacher_assistant/enrollment.ex` `resources do`:

```elixir
    resource TeacherAssistant.Academics.Guardian
    resource TeacherAssistant.Academics.StudentGuardian
```

- [ ] **Step 7: Generate the dev migration and run the tests**

```bash
mix ash.codegen --dev
MIX_TEST_PARTITION=3 mix ash.migrate
MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/guardian_test.exs
```

Expected: the dev migration creates `guardians`, `student_guardians` (with
`student_guardians_one_primary_index … WHERE primary_contact`) and adds `birth_date`, `birth_place` to
`students`; all tests PASS. If `compare/2` refuses a function value, replace it by a custom validation module
`Student.Validations.BirthDateNotFuture` (`validate/3` returning `{:error, field: :birth_date, message: …}` when
`Date.compare(value, Date.utc_today()) == :gt`, and `atomic/3` returning `:ok` when unchanged).

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/academics/guardian_relationship.ex lib/teacher_assistant/academics/contact_language.ex \
  lib/teacher_assistant/academics/guardian.ex lib/teacher_assistant/academics/guardian \
  lib/teacher_assistant/academics/student_guardian.ex lib/teacher_assistant/academics/student_guardian \
  lib/teacher_assistant/academics/student.ex lib/teacher_assistant/academics/class_group.ex \
  lib/teacher_assistant/enrollment.ex priv/repo/migrations priv/resource_snapshots \
  test/teacher_assistant/academics/guardian_test.exs
git commit -m "feat: guardians and birth details on students"
```

---

### Task 2: Guardian functions — add with phone lookup, main contact, unlink

**Files:**
- Modify: `lib/teacher_assistant/enrollment.ex` (new section `# --- Guardians`)
- Test: `test/teacher_assistant/enrollment_guardians_test.exs`

**Interfaces:**
- Consumes: Task 1 resources and actions.
- Produces (all take `%Scope{}` first):
  - `Enrollment.can_manage_register?(scope) :: boolean` — admin or `:conduct`.
  - `Enrollment.list_guardian_links(scope, %Student{}) :: [%StudentGuardian{guardian: %Guardian{}}]`, primary
    first.
  - `Enrollment.find_guardians_by_phone(scope, phone) :: [%Guardian{}]` (`[]` when the number is invalid).
  - `Enrollment.add_guardian(scope, %Student{}, attrs) :: {:ok, %Guardian{}} | {:error, term}` — creates and
    links in one transaction.
  - `Enrollment.link_guardian(scope, %Student{}, %Guardian{}) :: {:ok, %StudentGuardian{}} | {:error, :already_linked | term}`.
  - `Enrollment.update_guardian(scope, %Guardian{}, attrs) :: {:ok, %Guardian{}} | {:error, term}`.
  - `Enrollment.make_primary_guardian(scope, %StudentGuardian{}) :: {:ok, %StudentGuardian{}} | {:error, term}`.
  - `Enrollment.unlink_guardian(scope, %StudentGuardian{}) :: :ok | {:error, term}`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.EnrollmentGuardiansTest do
  use TeacherAssistant.DataCase, async: true

  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Organization}

  setup do
    %{scope: scope} = setup_complete_school_fixture()
    year = Organization.current_academic_year(scope)
    [cg | _] = Enrollment.list_class_groups(scope, year)
    {:ok, awa} = Enrollment.add_student(scope, cg, %{full_name: "Awa Nkolo", sex: :f})
    {:ok, paul} = Enrollment.add_student(scope, cg, %{full_name: "Paul Nkolo", sex: :m})
    %{scope: scope, awa: awa, paul: paul}
  end

  @father %{full_name: "Jean Nkolo", relationship: :pere, phone: "+237 6 77 12 34 56"}

  test "a sibling's parent is found by phone whatever the formatting", %{
    scope: scope,
    awa: awa,
    paul: paul
  } do
    {:ok, jean} = Enrollment.add_guardian(scope, awa, @father)

    assert [%{id: id}] = Enrollment.find_guardians_by_phone(scope, "677123456")
    assert id == jean.id
    assert Enrollment.find_guardians_by_phone(scope, "12") == []

    assert {:ok, link} = Enrollment.link_guardian(scope, paul, jean)
    assert link.primary_contact
    assert {:error, :already_linked} = Enrollment.link_guardian(scope, paul, jean)
  end

  test "making another guardian the main contact unsets the previous one", %{scope: scope, awa: awa} do
    {:ok, _} = Enrollment.add_guardian(scope, awa, @father)

    {:ok, _} =
      Enrollment.add_guardian(scope, awa, %{
        full_name: "Marie Nkolo",
        relationship: :mere,
        phone: "699 00 00 01"
      })

    [first, second] = Enrollment.list_guardian_links(scope, awa)
    assert first.primary_contact and first.guardian.full_name == "Jean Nkolo"
    refute second.primary_contact

    assert {:ok, _} = Enrollment.make_primary_guardian(scope, second)

    assert [%{guardian: %{full_name: "Marie Nkolo"}, primary_contact: true}, %{primary_contact: false}] =
             Enrollment.list_guardian_links(scope, awa)
  end

  test "unlinking keeps a guardian shared by a sibling and deletes an orphan", %{
    scope: scope,
    awa: awa,
    paul: paul
  } do
    {:ok, jean} = Enrollment.add_guardian(scope, awa, @father)
    {:ok, _} = Enrollment.link_guardian(scope, paul, jean)

    [awa_link] = Enrollment.list_guardian_links(scope, awa)
    assert :ok = Enrollment.unlink_guardian(scope, awa_link)
    assert Enrollment.list_guardian_links(scope, awa) == []
    assert [%{guardian: %{id: id}}] = Enrollment.list_guardian_links(scope, paul)
    assert id == jean.id

    [paul_link] = Enrollment.list_guardian_links(scope, paul)
    assert :ok = Enrollment.unlink_guardian(scope, paul_link)
    assert Enrollment.find_guardians_by_phone(scope, "677123456") == []
  end

  test "a refused or invalid add leaves nothing behind", %{scope: scope, awa: awa} do
    assert {:error, _} = Enrollment.add_guardian(scope, awa, %{@father | phone: "12"})
    assert Enrollment.list_guardian_links(scope, awa) == []

    teacher = member_scope_fixture(scope, %{roles: [:teacher]})
    assert_forbidden(Enrollment.add_guardian(teacher, awa, @father))
    assert Enrollment.find_guardians_by_phone(scope, "677123456") == []
  end

  test "can_manage_register? is true for admins and the SG only", %{scope: scope} do
    assert Enrollment.can_manage_register?(scope)
    assert Enrollment.can_manage_register?(member_scope_fixture(scope, %{roles: [:discipline_master]}))
    refute Enrollment.can_manage_register?(member_scope_fixture(scope, %{roles: [:teacher]}))
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/enrollment_guardians_test.exs`
Expected: FAIL — `Enrollment.add_guardian/3 is undefined`.

- [ ] **Step 3: Implement the functions**

Add the aliases `Guardian`, `StudentGuardian` to the existing `alias TeacherAssistant.Academics.{…}` line, then
append after the `# --- Student` section:

```elixir
  # --- Guardians (spec KLM1) ---------------------------------------------------

  @doc "Whether the scope edits the school register: students' identity and guardians (admin or SG)."
  def can_manage_register?(%Scope{current_user: %{} = user, current_workspace: %{id: ws_id}}),
    do: Checks.SchoolRole.holds?(user, ws_id, :admin) or Checks.SchoolRole.holds?(user, ws_id, :conduct)

  def can_manage_register?(_scope), do: false

  @doc "The student's guardian links with their guardian, main contact first."
  def list_guardian_links(%Scope{} = scope, %Student{id: id}) do
    StudentGuardian
    |> Ash.Query.for_read(:for_student, %{student_id: id}, scope: scope)
    |> Ash.read!()
  end

  @doc "The school's guardians whose phone matches `phone` once normalised; `[]` for an invalid number."
  def find_guardians_by_phone(%Scope{} = scope, phone) do
    if Guardian.Phone.valid?(phone) do
      Guardian
      |> Ash.Query.for_read(:by_phone_key, %{phone_key: Guardian.Phone.key(phone)}, scope: scope)
      |> Ash.read!()
    else
      []
    end
  end

  @doc "Creates a guardian and links it to `student` in one transaction."
  def add_guardian(%Scope{} = scope, %Student{} = student, attrs) do
    Ash.transact([Guardian, StudentGuardian], fn ->
      with {:ok, guardian} <-
             Guardian |> Ash.Changeset.for_create(:create, attrs, scope: scope) |> Ash.create(),
           {:ok, _link} <- link_guardian(scope, student, guardian) do
        guardian
      else
        {:error, error} -> Ash.DataLayer.rollback(Guardian, error)
      end
    end)
  end

  @doc "Links an existing guardian to `student`; the student's first link becomes the main contact."
  def link_guardian(%Scope{} = scope, %Student{id: student_id}, %Guardian{id: guardian_id}) do
    StudentGuardian
    |> Ash.Changeset.for_create(:link, %{student_id: student_id, guardian_id: guardian_id},
      scope: scope
    )
    |> Ash.create()
    |> case do
      {:ok, link} ->
        {:ok, link}

      {:error, error} ->
        if identity_error?(error, "unique_link"), do: {:error, :already_linked}, else: {:error, error}
    end
  end

  def update_guardian(%Scope{} = scope, %Guardian{} = guardian, attrs) do
    guardian
    |> Ash.Changeset.for_update(:update, attrs, scope: scope)
    |> Ash.update()
  end

  def make_primary_guardian(%Scope{} = scope, %StudentGuardian{} = link) do
    link
    |> Ash.Changeset.for_update(:make_primary, %{}, scope: scope)
    |> Ash.update()
  end

  def unlink_guardian(%Scope{} = scope, %StudentGuardian{} = link) do
    link
    |> Ash.Changeset.for_destroy(:unlink, %{}, scope: scope)
    |> Ash.destroy()
  end

  defp identity_error?(%Ash.Error.Invalid{errors: errors}, name),
    do: Enum.any?(errors, &identity_error?(&1, name))

  defp identity_error?(%Ash.Error.Changes.InvalidAttribute{private_vars: vars}, name) do
    constraint = vars[:constraint]
    is_binary(constraint) and String.contains?(constraint, name)
  end

  defp identity_error?(_error, _name), do: false
```

Note: `Ash.transact/2` returns `{:ok, guardian}` on success and `{:error, error}` after `rollback/2`; a
forbidden create comes back as `{:error, %Ash.Error.Forbidden{}}`, which `assert_forbidden/1` accepts.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/enrollment_guardians_test.exs test/teacher_assistant/academics/guardian_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/teacher_assistant/enrollment.ex test/teacher_assistant/enrollment_guardians_test.exs
git commit -m "feat: add, link, main contact and unlink guardians"
```

---

### Task 3: School-wide student list

**Files:**
- Modify: `lib/teacher_assistant/academics/enrollment.ex` (read `:school_list`, calculations)
- Modify: `lib/teacher_assistant/enrollment.ex` (`list_school_students/3`)
- Create: `lib/teacher_assistant_web/live/school/students_live.ex`
- Modify: `lib/teacher_assistant_web/router.ex` (two routes, `:school_workspace` live session)
- Modify: `lib/teacher_assistant_web/spaces.ex` (`students/0` item in Proviseur, Censeur, Surveillant)
- Test: `test/teacher_assistant_web/live/school/students_live_test.exs`

**Interfaces:**
- Consumes: `Enrollment.can_manage_register?/1`; `Student.primary_guardian_link`.
- Produces: `Enrollment.list_school_students(scope, %AcademicYear{}, opts) :: %Ash.Page.Offset{results: [%Enrollment{student: %Student{primary_guardian_link: …}, class_group: %ClassGroup{}}], count: integer}`
  with `opts` `query: String.t() | nil`, `class_group_id: uuid | nil`, `offset: non_neg_integer`; route
  `/school/students` (`School.StudentsLive`) and `/school/students/:id` (`School.StudentLive`, Task 4).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.StudentsLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée E"})

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    {:ok, sixth} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, fifth} = Enrollment.create_class_group(scope, year, %{label: "5e A", level: "5ème"})

    {:ok, awa} =
      Enrollment.add_student(scope, fifth, %{full_name: "Awa Nkolo", sex: :f, matricule: "M-001"})

    {:ok, _} = Enrollment.add_student(scope, sixth, %{full_name: "Zoé Abena", sex: :f})
    {:ok, _} = Enrollment.add_guardian(scope, awa, %{full_name: "Jean Nkolo", relationship: :pere, phone: "677123456"})

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, scope: scope, school: school, sixth: sixth, awa: awa}
  end

  test "lists the year's students in class order with their main contact", %{conn: conn, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students")

    rows = view |> element("#student-rows") |> render()
    assert rows =~ "Zoé Abena"
    assert rows =~ "Awa Nkolo"
    # 6e before 5e (school ladder order).
    assert :binary.match(rows, "Zoé Abena") < :binary.match(rows, "Awa Nkolo")
    assert rows =~ "Jean Nkolo"
    assert rows =~ "tel:677123456"
    assert has_element?(view, ~s|a[href="/school/students/#{awa.id}"]|)
  end

  test "searches by name or matricule and filters by class", %{conn: conn, sixth: sixth} do
    {:ok, view, _html} = live(conn, ~p"/school/students?q=M-001")
    assert render(view) =~ "Awa Nkolo"
    refute render(view) =~ "Zoé Abena"

    {:ok, view, _html} = live(conn, ~p"/school/students?q=abe")
    assert render(view) =~ "Zoé Abena"
    refute render(view) =~ "Awa Nkolo"

    {:ok, view, _html} = live(conn, ~p"/school/students?class=#{sixth.id}")
    assert render(view) =~ "Zoé Abena"
    refute render(view) =~ "Awa Nkolo"
  end

  test "a plain teacher is sent back to the school home", %{school: school, scope: scope} do
    teacher = member_scope_fixture(scope, %{roles: [:teacher]})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, teacher.current_user.id)
      |> Plug.Conn.put_session(:workspace_id, school.id)

    assert {:error, {:live_redirect, %{to: "/school"}}} = live(conn, ~p"/school/students")
  end
end
```

Note: if `live/2` returns `{:error, {:redirect, …}}` because `require_school_setup` intercepts first, complete
the school with `complete_school_setup!(scope)` in `setup` (as other school LiveView tests do) and keep the
assertion on the final destination `/school`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/students_live_test.exs`
Expected: FAIL — no route `/school/students`.

- [ ] **Step 3: The `:school_list` read on Enrollment**

In `lib/teacher_assistant/academics/enrollment.ex` `actions do`:

```elixir
    # Spec KLM1 (L3): the school-wide student list, class order then name, paginated.
    read :school_list do
      argument :academic_year_id, :uuid, allow_nil?: false
      argument :class_group_id, :uuid
      # Lower-cased by the caller.
      argument :query, :string

      pagination offset?: true, countable: true, required?: false, default_limit: 50

      filter expr(academic_year_id == ^arg(:academic_year_id))
      filter expr(is_nil(^arg(:class_group_id)) or class_group_id == ^arg(:class_group_id))

      filter expr(
               is_nil(^arg(:query)) or
                 contains(string_downcase(student.full_name), ^arg(:query)) or
                 string_downcase(student.matricule) == ^arg(:query)
             )

      prepare build(
                load: [:class_group, student: [primary_guardian_link: :guardian]],
                sort: [class_rank: :asc, class_label: :asc, student_name: :asc]
              )
    end
```

And a `calculations do` block (new):

```elixir
  calculations do
    calculate :class_rank, :integer, expr(class_group.level_rank)
    calculate :class_label, :string, expr(class_group.label)
    calculate :student_name, :string, expr(string_downcase(student.full_name))
  end
```

- [ ] **Step 4: `list_school_students/3`**

In `lib/teacher_assistant/enrollment.ex`, after `list_roster/2`:

```elixir
  @doc """
  Spec KLM1 (L3): one page (50) of `year`'s enrollments, class order then name,
  with the student's main contact. `opts`: `query` (name fragment or exact
  matricule), `class_group_id`, `offset`.
  """
  def list_school_students(%Scope{} = scope, %AcademicYear{id: year_id}, opts \\ []) do
    query =
      case opts[:query] |> to_string() |> String.trim() do
        "" -> nil
        q -> String.downcase(q)
      end

    Enrollment
    |> Ash.Query.for_read(
      :school_list,
      %{academic_year_id: year_id, class_group_id: opts[:class_group_id], query: query},
      scope: scope
    )
    |> Ash.read!(page: [limit: 50, offset: opts[:offset] || 0, count: true])
  end
```

- [ ] **Step 5: Routes and menu items**

In `router.ex`, inside `ash_authentication_live_session :school_workspace`, after the `/school/absences` line:

```elixir
      live "/school/students", School.StudentsLive, :index
      live "/school/students/:id", School.StudentLive, :show
```

In `spaces.ex`, add `students()` right after `classes()` in the Proviseur « Pilotage », Censeur « Suivi
pédagogique » and Surveillant « Vie scolaire » sections, and the item helper next to `classes/0`:

```elixir
  defp students,
    do: item("students", gettext("Élèves"), "hero-identification", ~p"/school/students")
```

(`StudentLive` does not exist until Task 4: create a placeholder module now so the router compiles —

```elixir
defmodule TeacherAssistantWeb.School.StudentLive do
  use TeacherAssistantWeb, :live_view
  def mount(_params, _session, socket), do: {:ok, push_navigate(socket, to: ~p"/school/students")}
  def render(assigns), do: ~H""
end
```

in `lib/teacher_assistant_web/live/school/student_live.ex`; Task 4 replaces it.)

- [ ] **Step 6: `StudentsLive`**

```elixir
defmodule TeacherAssistantWeb.School.StudentsLive do
  @moduledoc """
  Censeur / SG → Élèves (spec KLM1, L3): the active year's students, searchable
  by name or matricule, filterable by class, with the main contact's phone.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.Enrollment
  alias TeacherAssistant.Academics.GuardianRelationship

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if scope.current_academic_year && Enrollment.can_manage_register?(scope) do
      {:ok,
       assign(socket,
         classes: Enrollment.list_class_groups(scope, scope.current_academic_year)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("La liste des élèves est réservée à l'administration."))
       |> push_navigate(to: ~p"/school")}
    end
  end

  def handle_params(params, _uri, socket) do
    q = params["q"] || ""
    class_id = Enum.find_value(socket.assigns.classes, &(&1.id == params["class"] && &1.id))
    offset = params |> Map.get("page", "1") |> parse_page() |> then(&((&1 - 1) * 50))

    page =
      Enrollment.list_school_students(
        socket.assigns.current_scope,
        socket.assigns.current_scope.current_academic_year,
        query: q,
        class_group_id: class_id,
        offset: offset
      )

    {:noreply, assign(socket, q: q, class_id: class_id, page: page, offset: offset)}
  end

  def handle_event("filter", %{"q" => q, "class" => class}, socket) do
    params = %{"q" => q, "class" => class} |> Enum.reject(fn {_k, v} -> v == "" end) |> Map.new()
    {:noreply, push_patch(socket, to: ~p"/school/students?#{params}")}
  end

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp page_link(assigns, page) do
    params =
      %{"q" => assigns.q, "class" => assigns.class_id, "page" => page}
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    ~p"/school/students?#{params}"
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        current_page: div(assigns.offset, 50) + 1,
        last_page: max(div((assigns.page.count || 0) + 49, 50), 1)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="students" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("École")} title={gettext("Élèves")}>
          <:actions>
            <.side_chip id="students-count">
              {ngettext("%{count} élève", "%{count} élèves", @page.count || 0)}
            </.side_chip>
          </:actions>
        </.page_header>

        <.form for={%{}} id="students-filter" phx-change="filter" phx-submit="filter" class="flex flex-wrap gap-2">
          <input
            type="search"
            name="q"
            value={@q}
            placeholder={gettext("Nom ou matricule")}
            phx-debounce="300"
            class="input input-sm w-full sm:w-72"
          />
          <select name="class" class="select select-sm">
            <option value="">{gettext("Toutes les classes")}</option>
            <option :for={c <- @classes} value={c.id} selected={c.id == @class_id}>{c.label}</option>
          </select>
        </.form>

        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>{gettext("Élève")}</th>
                <th>{gettext("Matricule")}</th>
                <th>{gettext("Classe")}</th>
                <th>{gettext("Sexe")}</th>
                <th>{gettext("Contact principal")}</th>
              </tr>
            </thead>
            <tbody id="student-rows">
              <tr :for={e <- @page.results} id={"student-#{e.student.id}"} class="hover:bg-base-200/60">
                <td>
                  <.link navigate={~p"/school/students/#{e.student.id}"} class="font-semibold hover:text-primary">
                    {e.student.full_name}
                  </.link>
                </td>
                <td class="font-mono text-xs">{e.student.matricule || "—"}</td>
                <td>{e.class_group.label}</td>
                <td>{TeacherAssistant.Academics.Sex.label(e.student.sex)}</td>
                <td>
                  <%= case e.student.primary_guardian_link do %>
                    <% %{guardian: g} -> %>
                      <span>{g.full_name}</span>
                      <span class="text-base-content/60">· {GuardianRelationship.label(g.relationship)}</span>
                      <a href={"tel:#{g.phone_key}"} class="link link-primary ml-1 font-mono text-xs">{g.phone}</a>
                    <% _ -> %>
                      <span class="text-base-content/50">—</span>
                  <% end %>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@page.results == []} id="students-empty" class="p-4 text-sm text-base-content/60">
            {gettext("Aucun élève ne correspond.")}
          </p>
        </div>

        <nav :if={@last_page > 1} class="join self-center">
          <.link
            :for={p <- 1..@last_page}
            patch={page_link(assigns, p)}
            class={["join-item btn btn-sm", p == @current_page && "btn-active"]}
          >
            {p}
          </.link>
        </nav>
      </section>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 7: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/students_live_test.exs test/teacher_assistant_web/spaces_test.exs`
Expected: PASS. If a Spaces test pins the exact item list of a space, add `"nav-school-students"` where the
spec now puts it.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/academics/enrollment.ex lib/teacher_assistant/enrollment.ex \
  lib/teacher_assistant_web/live/school/students_live.ex lib/teacher_assistant_web/live/school/student_live.ex \
  lib/teacher_assistant_web/router.ex lib/teacher_assistant_web/spaces.ex \
  test/teacher_assistant_web/live/school/students_live_test.exs test/teacher_assistant_web/spaces_test.exs \
  priv/resource_snapshots
git commit -m "feat: school-wide student list"
```

---

### Task 4: Student profile page

**Files:**
- Modify: `lib/teacher_assistant/academics/enrollment.ex` (read `:for_student`)
- Modify: `lib/teacher_assistant/enrollment.ex` (`student_access/2`, `student_history/2`)
- Modify: `lib/teacher_assistant/councils.ex` (`annual_decisions/2`)
- Replace: `lib/teacher_assistant_web/live/school/student_live.ex`
- Modify: `lib/teacher_assistant_web/live/school/class_live.ex:114` (roster name links to the profile)
- Test: `test/teacher_assistant_web/live/school/student_live_test.exs`

**Interfaces:**
- Consumes: Task 2 functions; `Attendance.student_conduct(scope, enrollment, {:annual, year})`
  (`%{justified_hours, unjustified_hours, retards}`), `Discipline.discipline_summary(scope, enrollment,
  {:annual, year})` (`%{sanctions, consignes_count, note_de_conduite}`), `Discipline.note_de_conduite(scope,
  enrollment, {:sequence, seq})`, `Organization.list_sequences(scope, year)`.
- Produces: `Enrollment.student_access(scope, %Student{}) :: :manage | :read | :none`;
  `Enrollment.student_history(scope, %Student{}) :: [%Enrollment{class_group: _, academic_year: _}]`, newest
  year first; `Councils.annual_decisions(scope, student_id) :: %{class_group_id => PassageDecision.t()}`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistantWeb.School.StudentLiveTest do
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import TeacherAssistant.TeacherFixtures

  alias TeacherAssistant.{Enrollment, Organization}

  setup :register_and_log_in_user

  setup %{conn: conn, actor: head} do
    {:ok, school} =
      Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{name: "Lycée F"})

    scope = school_scope(head, school)

    {:ok, year} =
      Organization.create_academic_year(scope, %{
        name: "2025-2026",
        start_date: ~D[2025-09-08],
        end_date: ~D[2026-07-31],
        active: true
      })

    :ok = Organization.build_default_calendar(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e A", level: "6ème"})
    {:ok, other} = Enrollment.create_class_group(scope, year, %{label: "6e B", level: "6ème"})

    {:ok, awa} =
      Enrollment.add_student(scope, cg, %{
        full_name: "Awa Nkolo",
        sex: :f,
        birth_date: ~D[2013-04-02],
        birth_place: "Yaoundé"
      })

    conn = Plug.Conn.put_session(conn, :workspace_id, school.id)
    %{conn: conn, scope: scope, school: school, cg: cg, other: other, awa: awa}
  end

  defp conn_for(school, user) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.put_session(:workspace_id, school.id)
  end

  test "shows identity, history and this year's discipline", %{conn: conn, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

    identity = view |> element("#student-identity") |> render()
    assert identity =~ "Awa Nkolo"
    assert identity =~ "02/04/2013"
    assert identity =~ "Yaoundé"

    assert view |> element("#student-history") |> render() =~ "6e A"
    assert view |> element("#student-this-year") |> render() =~ "0"
  end

  test "the admin adds a guardian, links a sibling's parent, changes the main contact", %{
    conn: conn,
    scope: scope,
    cg: cg,
    awa: awa
  } do
    {:ok, paul} = Enrollment.add_student(scope, cg, %{full_name: "Paul Nkolo", sex: :m})
    {:ok, _} = Enrollment.add_guardian(scope, paul, %{full_name: "Jean Nkolo", relationship: :pere, phone: "677123456"})

    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")

    # Typing the sibling's number offers the existing parent instead of a new record.
    view |> form("#guardian-form", guardian: %{phone: "+237 677 12 34 56"}) |> render_change()
    assert has_element?(view, "#guardian-match", "Jean Nkolo")
    view |> element("#guardian-match button") |> render_click()
    assert view |> element("#guardian-list") |> render() =~ "Contact principal"

    view
    |> form("#guardian-form",
      guardian: %{full_name: "Marie Nkolo", relationship: "mere", phone: "699000001", language: "fr"}
    )
    |> render_submit()

    [_, marie] = Enrollment.list_guardian_links(scope, awa)
    view |> element("#make-primary-#{marie.id}") |> render_click()

    assert [%{guardian: %{full_name: "Marie Nkolo"}, primary_contact: true} | _] =
             Enrollment.list_guardian_links(scope, awa)
  end

  test "the admin edits the identity", %{conn: conn, scope: scope, awa: awa} do
    {:ok, view, _html} = live(conn, ~p"/school/students/#{awa.id}")
    view |> element("#edit-identity") |> render_click()

    view
    |> form("#identity-form", student: %{birth_place: "Douala"})
    |> render_submit()

    {:ok, awa} = Enrollment.fetch_owned_student(scope, awa.id)
    assert awa.birth_place == "Douala"
  end

  test "the student's teacher reads the profile without edit buttons", %{
    school: school,
    scope: scope,
    cg: cg,
    awa: awa
  } do
    %{teacher: teacher} = school_teacher_fixture(scope, %{class_group: cg})
    {:ok, view, _html} = live(conn_for(school, teacher), ~p"/school/students/#{awa.id}")

    assert render(view) =~ "Awa Nkolo"
    refute has_element?(view, "#edit-identity")
    refute has_element?(view, "#guardian-form")
  end

  test "a teacher of another class is sent back", %{school: school, scope: scope, other: other, awa: awa} do
    %{teacher: teacher} = school_teacher_fixture(scope, %{class_group: other})

    assert {:error, {:live_redirect, %{to: "/school"}}} =
             live(conn_for(school, teacher), ~p"/school/students/#{awa.id}")
  end

  test "an unknown or foreign student id is sent back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/school/students"}}} =
             live(conn, ~p"/school/students/#{Ash.UUID.generate()}")
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/student_live_test.exs`
Expected: FAIL — the placeholder redirects every visit.

- [ ] **Step 3: Domain functions**

`lib/teacher_assistant/academics/enrollment.ex`, `actions do`:

```elixir
    read :for_student do
      argument :student_id, :uuid, allow_nil?: false
      filter expr(student_id == ^arg(:student_id))
      prepare build(load: [:class_group, :academic_year])
    end
```

`lib/teacher_assistant/enrollment.ex`, after the guardian section:

```elixir
  @doc """
  Spec KLM1 (M3): `:manage` for admins and the SG, `:read` for a form master or
  teacher of a class the student is enrolled in this year, else `:none`.
  """
  def student_access(%Scope{} = scope, %Student{} = student) do
    cond do
      can_manage_register?(scope) -> :manage
      teaches_or_masters?(scope, student) -> :read
      true -> :none
    end
  end

  defp teaches_or_masters?(%Scope{current_user: %{id: uid}, current_academic_year: %{id: year_id}} = scope, student) do
    Enrollment
    |> Ash.Query.for_read(:for_student, %{student_id: student.id}, scope: scope)
    |> Ash.Query.filter(
      academic_year_id == ^year_id and
        (class_group.form_master_user_id == ^uid or
           exists(class_group.teaching_contexts, teacher_user_id == ^uid))
    )
    |> Ash.exists?()
  end

  defp teaches_or_masters?(_scope, _student), do: false

  @doc "Spec KLM1 (M3): the student's enrollments with class and year, newest year first."
  def student_history(%Scope{} = scope, %Student{id: id}) do
    Enrollment
    |> Ash.Query.for_read(:for_student, %{student_id: id}, scope: scope)
    |> Ash.read!()
    |> Enum.sort_by(& &1.academic_year.start_date, {:desc, Date})
  end
```

`lib/teacher_assistant/councils.ex` (add near `passage_inputs/3`; alias `CouncilDecision` if not already):

```elixir
  @doc "Spec KLM1 (M3): the student's end-of-year passage decisions, by class group."
  def annual_decisions(%Scope{} = scope, student_id) do
    CouncilDecision
    |> Ash.Query.filter(
      student_id == ^student_id and class_council.period_key == "annee" and
        not is_nil(passage_decision)
    )
    |> Ash.Query.load(:class_council)
    |> Ash.read!(scope: scope)
    |> Map.new(&{&1.class_council.class_group_id, &1.passage_decision})
  end
```

- [ ] **Step 4: The profile LiveView**

Replace `lib/teacher_assistant_web/live/school/student_live.ex`:

```elixir
defmodule TeacherAssistantWeb.School.StudentLive do
  @moduledoc """
  Student profile (spec KLM1, M3): identity, parents and guardians, class
  history with passage decisions and bulletins, this year's attendance and
  discipline. Editing for admins and the SG; reading for the student's
  form masters and teachers.
  """
  use TeacherAssistantWeb, :live_view

  alias TeacherAssistant.{Attendance, Councils, Discipline, Enrollment, Organization}
  alias TeacherAssistant.Academics.{ContactLanguage, Guardian, GuardianRelationship, PassageDecision, Sex}
  alias TeacherAssistantWeb.Authz

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    with {:ok, student} <- Enrollment.fetch_owned_student(scope, id),
         access when access != :none <- Enrollment.student_access(scope, student) do
      {:ok,
       socket
       |> assign(student: student, access: access, editing: false, match: [])
       |> assign_guardian_form(%{})
       |> load()}
    else
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Élève introuvable."))
         |> push_navigate(to: ~p"/school/students")}

      :none ->
        {:ok, socket |> Authz.put_not_allowed() |> push_navigate(to: ~p"/school")}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    student = socket.assigns.student
    year = scope.current_academic_year
    history = Enrollment.student_history(scope, student)
    current = year && Enum.find(history, &(&1.academic_year_id == year.id))

    assign(socket,
      links: Enrollment.list_guardian_links(scope, student),
      history: history,
      decisions: Councils.annual_decisions(scope, student.id),
      this_year: current && this_year(scope, current, year)
    )
  end

  defp this_year(scope, enrollment, year) do
    %{
      enrollment: enrollment,
      attendance: Attendance.student_conduct(scope, enrollment, {:annual, year}),
      discipline: Discipline.discipline_summary(scope, enrollment, {:annual, year}),
      conduct:
        scope
        |> Organization.list_sequences(year)
        |> Enum.map(&{&1, Discipline.note_de_conduite(scope, enrollment, {:sequence, &1})})
    }
  end

  defp assign_guardian_form(socket, params) do
    assign(socket, guardian_form: to_form(params, as: "guardian"))
  end

  # --- Identity ---

  def handle_event("edit_identity", _params, socket) when socket.assigns.access == :manage do
    form =
      AshPhoenix.Form.for_update(socket.assigns.student, :update,
        as: "student",
        scope: socket.assigns.current_scope
      )

    {:noreply, assign(socket, editing: true, identity_form: to_form(form))}
  end

  def handle_event("cancel_identity", _params, socket), do: {:noreply, assign(socket, editing: false)}

  def handle_event("save_identity", %{"student" => params}, socket)
      when socket.assigns.access == :manage do
    case AshPhoenix.Form.submit(socket.assigns.identity_form.source, params: params) do
      {:ok, student} ->
        {:noreply, socket |> assign(student: student, editing: false) |> put_flash(:info, gettext("Identité enregistrée."))}

      {:error, form} ->
        if Authz.forbidden_form?(form),
          do: {:noreply, Authz.put_not_allowed(socket)},
          else: {:noreply, assign(socket, identity_form: to_form(form))}
    end
  end

  # --- Guardians ---

  def handle_event("guardian_change", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage do
    linked = MapSet.new(socket.assigns.links, & &1.guardian_id)

    match =
      socket.assigns.current_scope
      |> Enrollment.find_guardians_by_phone(params["phone"] || "")
      |> Enum.reject(&MapSet.member?(linked, &1.id))

    {:noreply, socket |> assign(match: match) |> assign_guardian_form(params)}
  end

  def handle_event("add_guardian", %{"guardian" => params}, socket)
      when socket.assigns.access == :manage do
    attrs = Map.take(params, ~w(full_name relationship phone phone_2 email language))

    case Enrollment.add_guardian(socket.assigns.current_scope, socket.assigns.student, attrs) do
      {:ok, _guardian} ->
        {:noreply, socket |> assign(match: []) |> assign_guardian_form(%{}) |> load()}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, Authz.put_not_allowed(socket)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  def handle_event("link_guardian", %{"id" => id}, socket) when socket.assigns.access == :manage do
    with %Guardian{} = guardian <- Enum.find(socket.assigns.match, &(&1.id == id)),
         {:ok, _} <- Enrollment.link_guardian(socket.assigns.current_scope, socket.assigns.student, guardian) do
      {:noreply, socket |> assign(match: []) |> assign_guardian_form(%{}) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Impossible de lier ce parent."))}
    end
  end

  def handle_event("make_primary", %{"id" => id}, socket) when socket.assigns.access == :manage do
    run_on_link(socket, id, &Enrollment.make_primary_guardian/2)
  end

  def handle_event("unlink", %{"id" => id}, socket) when socket.assigns.access == :manage do
    run_on_link(socket, id, &Enrollment.unlink_guardian/2)
  end

  # Any write event from a read-only visitor.
  def handle_event(_event, _params, socket), do: {:noreply, Authz.put_not_allowed(socket)}

  defp run_on_link(socket, id, fun) do
    with %{} = link <- Enum.find(socket.assigns.links, &(&1.id == id)),
         result when result == :ok or elem(result, 0) == :ok <- fun.(socket.assigns.current_scope, link) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Action impossible."))}
    end
  end

  defp error_message(%Ash.Error.Invalid{errors: errors}),
    do: Enum.map_join(errors, " ", &Exception.message/1)

  defp error_message(_error), do: gettext("Impossible d'enregistrer le parent.")

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <section id="student" class="flex flex-col gap-5">
        <.page_header eyebrow={gettext("Élève")} title={@student.full_name}>
          <:actions>
            <.link :if={@access == :manage} navigate={~p"/school/students"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="size-4" /> {gettext("Élèves")}
            </.link>
          </:actions>
        </.page_header>

        <div class="grid gap-4 lg:grid-cols-2">
          <article id="student-identity" class="ta-panel flex flex-col gap-3">
            <header class="flex items-center justify-between">
              <h2 class="ta-eyebrow">{gettext("Identité")}</h2>
              <button
                :if={@access == :manage and not @editing}
                id="edit-identity"
                phx-click="edit_identity"
                class="btn btn-ghost btn-xs"
              >
                <.icon name="hero-pencil-square" class="size-4" /> {gettext("Modifier")}
              </button>
            </header>

            <.form :if={@editing} for={@identity_form} id="identity-form" phx-submit="save_identity" class="grid gap-2 sm:grid-cols-2">
              <.input field={@identity_form[:full_name]} label={gettext("Nom et prénoms")} />
              <.input
                field={@identity_form[:sex]}
                type="select"
                label={gettext("Sexe")}
                options={Enum.map(Sex.values(), &{Sex.label(&1), &1})}
              />
              <.input field={@identity_form[:matricule]} label={gettext("Matricule")} />
              <.input field={@identity_form[:birth_date]} type="date" label={gettext("Date de naissance")} />
              <.input field={@identity_form[:birth_place]} label={gettext("Lieu de naissance")} />
              <div class="flex items-end gap-2">
                <button class="btn btn-primary btn-sm">{gettext("Enregistrer")}</button>
                <button type="button" phx-click="cancel_identity" class="btn btn-ghost btn-sm">{gettext("Annuler")}</button>
              </div>
            </.form>

            <dl :if={not @editing} class="grid grid-cols-2 gap-2 text-sm">
              <div><dt class="ta-eyebrow">{gettext("Sexe")}</dt><dd>{Sex.label(@student.sex)}</dd></div>
              <div><dt class="ta-eyebrow">{gettext("Matricule")}</dt><dd>{@student.matricule || "—"}</dd></div>
              <div><dt class="ta-eyebrow">{gettext("Date de naissance")}</dt><dd>{format_date(@student.birth_date)}</dd></div>
              <div><dt class="ta-eyebrow">{gettext("Lieu de naissance")}</dt><dd>{@student.birth_place || "—"}</dd></div>
            </dl>
          </article>

          <article id="student-guardians" class="ta-panel flex flex-col gap-3">
            <h2 class="ta-eyebrow">{gettext("Parents et tuteurs")}</h2>
            <p :if={@links != [] and not Enum.any?(@links, & &1.primary_contact)} class="text-sm text-warning">
              {gettext("Aucun contact principal")}
            </p>
            <ul id="guardian-list" class="flex flex-col divide-y divide-base-300">
              <li :for={l <- @links} id={"guardian-#{l.id}"} class="flex flex-wrap items-center gap-2 py-2">
                <span class="font-semibold">{l.guardian.full_name}</span>
                <span class="text-base-content/60">{GuardianRelationship.label(l.guardian.relationship)}</span>
                <span :if={l.primary_contact} class="badge badge-primary badge-sm">{gettext("Contact principal")}</span>
                <a href={"tel:#{l.guardian.phone_key}"} class="link link-primary font-mono text-xs">{l.guardian.phone}</a>
                <span :if={l.guardian.phone_2} class="font-mono text-xs">{l.guardian.phone_2}</span>
                <span :if={l.guardian.email} class="text-xs">{l.guardian.email}</span>
                <span class="text-xs text-base-content/60">{ContactLanguage.label(l.guardian.language)}</span>
                <span :if={@access == :manage} class="ml-auto flex gap-1">
                  <button
                    :if={not l.primary_contact}
                    id={"make-primary-#{l.id}"}
                    phx-click="make_primary"
                    phx-value-id={l.id}
                    class="btn btn-ghost btn-xs"
                  >
                    {gettext("Contact principal")}
                  </button>
                  <button
                    id={"unlink-#{l.id}"}
                    phx-click="unlink"
                    phx-value-id={l.id}
                    data-confirm={gettext("Retirer ce parent de la fiche de l'élève ?")}
                    class="btn btn-ghost btn-xs text-error"
                  >
                    {gettext("Retirer")}
                  </button>
                </span>
              </li>
            </ul>
            <p :if={@links == []} class="text-sm text-base-content/60">{gettext("Aucun parent enregistré.")}</p>

            <.form
              :if={@access == :manage}
              for={@guardian_form}
              id="guardian-form"
              phx-change="guardian_change"
              phx-submit="add_guardian"
              class="grid gap-2 sm:grid-cols-2"
            >
              <.input field={@guardian_form[:phone]} label={gettext("Téléphone")} phx-debounce="300" />
              <.input field={@guardian_form[:full_name]} label={gettext("Nom et prénoms")} />
              <.input
                field={@guardian_form[:relationship]}
                type="select"
                label={gettext("Lien")}
                options={Enum.map(GuardianRelationship.values(), &{GuardianRelationship.label(&1), &1})}
              />
              <.input field={@guardian_form[:phone_2]} label={gettext("Second téléphone")} />
              <.input field={@guardian_form[:email]} type="email" label={gettext("E-mail")} />
              <.input
                field={@guardian_form[:language]}
                type="select"
                label={gettext("Langue")}
                options={Enum.map(ContactLanguage.values(), &{ContactLanguage.label(&1), &1})}
              />
              <div :if={@match != []} id="guardian-match" class="sm:col-span-2 flex flex-col gap-1 rounded-box bg-base-200 p-2 text-sm">
                <span :for={g <- @match} class="flex items-center gap-2">
                  {gettext("Déjà enregistré :")} <strong>{g.full_name}</strong>
                  <button type="button" phx-click="link_guardian" phx-value-id={g.id} class="btn btn-primary btn-xs">
                    {gettext("Lier %{name}", name: g.full_name)}
                  </button>
                </span>
              </div>
              <button class="btn btn-primary btn-sm sm:col-span-2">{gettext("Ajouter le parent")}</button>
            </.form>
          </article>
        </div>

        <article id="student-history" class="ta-panel flex flex-col gap-2">
          <h2 class="ta-eyebrow">{gettext("Scolarité")}</h2>
          <table class="table table-sm">
            <tbody>
              <tr :for={e <- @history}>
                <td>{e.academic_year.name}</td>
                <td>{e.class_group.label}</td>
                <td><span :if={e.repeater} class="badge badge-ghost badge-sm">{gettext("Redoublant")}</span></td>
                <td>
                  <span :if={d = @decisions[e.class_group_id]}>{PassageDecision.label(d)}</span>
                </td>
                <td class="text-right">
                  <.link navigate={~p"/school/classes/#{e.class_group_id}/students/#{e.id}/bulletin"} class="link link-primary text-sm">
                    {gettext("Bulletin")}
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </article>

        <article :if={@this_year} id="student-this-year" class="ta-panel flex flex-col gap-3">
          <h2 class="ta-eyebrow">{gettext("Cette année")}</h2>
          <dl class="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
            <div><dt class="ta-eyebrow">{gettext("Absences non justifiées")}</dt><dd>{@this_year.attendance.unjustified_hours} h</dd></div>
            <div><dt class="ta-eyebrow">{gettext("Absences justifiées")}</dt><dd>{@this_year.attendance.justified_hours} h</dd></div>
            <div><dt class="ta-eyebrow">{gettext("Retards")}</dt><dd>{@this_year.attendance.retards}</dd></div>
            <div><dt class="ta-eyebrow">{gettext("Consignes")}</dt><dd>{@this_year.discipline.consignes_count}</dd></div>
          </dl>
          <ul class="text-sm">
            <li :for={s <- @this_year.discipline.sanctions}>
              {format_date(s.date)} · {TeacherAssistant.Academics.SanctionType.label(s.type)}
              <span :if={s.reason} class="text-base-content/60">— {s.reason}</span>
            </li>
          </ul>
          <p class="text-sm">
            {gettext("Conduite")} :
            <span :for={{seq, value} <- @this_year.conduct} class="mr-3">
              {gettext("Séq. %{n}", n: seq.number)} <strong>{value || "—"}</strong>
            </span>
          </p>
          <p class="flex gap-3 text-sm">
            <.link navigate={~p"/school/classes/#{@this_year.enrollment.class_group_id}/register"} class="link link-primary">
              {gettext("Registre d'appel")}
            </.link>
            <.link navigate={~p"/school/classes/#{@this_year.enrollment.class_group_id}/discipline"} class="link link-primary">
              {gettext("Discipline")}
            </.link>
          </p>
        </article>
      </section>
    </Layouts.app>
    """
  end
end
```

`PassageDecision.label/1` and `SanctionType.label/1` already exist; a séquence is shown by its `number`. A
teacher's `handle_event` for any write event hits the catch-all clause and only flashes.

- [ ] **Step 5: Roster links**

In `class_live.ex` line 114, replace `<td>{row.student.full_name}</td>` with:

```elixir
                <td>
                  <.link navigate={~p"/school/students/#{row.student.id}"} class="hover:text-primary">
                    {row.student.full_name}
                  </.link>
                </td>
```

- [ ] **Step 6: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant_web/live/school/student_live_test.exs test/teacher_assistant_web/live/school/class_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/teacher_assistant/academics/enrollment.ex lib/teacher_assistant/enrollment.ex lib/teacher_assistant/councils.ex \
  lib/teacher_assistant_web/live/school/student_live.ex lib/teacher_assistant_web/live/school/class_live.ex \
  test/teacher_assistant_web/live/school/student_live_test.exs
git commit -m "feat: student profile with guardians, history and this year"
```

---

### Task 5: Import columns and « Né(e) le … à … » on the bulletin

**Files:**
- Create: `lib/teacher_assistant/academics/roster_line.ex` (pure parser, moved out of the LiveView)
- Modify: `lib/teacher_assistant_web/live/school/enroll_import_live.ex` (use the parser, show the new columns
  and guardian outcomes, new help text)
- Modify: `lib/teacher_assistant/enrollment.ex` (`import_rows/3` attaches the guardian)
- Modify: `lib/teacher_assistant/academics/bulletin_element.ex` (`:birth`)
- Modify: `lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex` (cartouche row)
- Modify: `lib/teacher_assistant_web/live/school/bulletin_live.ex` (identity block)
- Test: `test/teacher_assistant/academics/roster_line_test.exs`
- Test: `test/teacher_assistant_web/live/school/enroll_import_live_test.exs` (add cases)
- Test: `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` (add a case)

**Interfaces:**
- Consumes: `Enrollment.find_guardians_by_phone/2`, `add_guardian/3`, `link_guardian/3`.
- Produces: `Academics.RosterLine.parse(raw :: String.t()) :: [row]`, where `row` is
  `%{full_name, sex, matricule, repeater: false, birth_date: Date.t() | nil, birth_place: String.t() | nil,
  guardian: %{full_name: String.t(), phone: String.t()} | nil}`; `import_rows/3` result gains
  `guardian_issues: [%{full_name: student_name, reason: :invalid_phone | term}]`; `BulletinElement` value
  `:birth`.

Line format (semicolon-separated, every column after the name optional):
`nom;sexe (m/f);matricule;date de naissance (JJ/MM/AAAA);lieu de naissance;nom du parent;téléphone du parent`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule TeacherAssistant.Academics.RosterLineTest do
  use ExUnit.Case, async: true

  alias TeacherAssistant.Academics.RosterLine

  test "reads the seven columns, all but the name optional" do
    [full, short] =
      RosterLine.parse("""
      Awa Nkolo;f;M-001;02/04/2013;Yaoundé;Jean Nkolo;677 12 34 56
      Paul Mbarga;m
      """)

    assert full == %{
             full_name: "Awa Nkolo",
             sex: :f,
             matricule: "M-001",
             repeater: false,
             birth_date: ~D[2013-04-02],
             birth_place: "Yaoundé",
             guardian: %{full_name: "Jean Nkolo", phone: "677 12 34 56"}
           }

    assert %{full_name: "Paul Mbarga", sex: :m, birth_date: nil, guardian: nil} = short
  end

  test "an impossible date is dropped, the row is kept" do
    assert [%{full_name: "Awa", birth_date: nil}] = RosterLine.parse("Awa;f;;31/02/2010")
    assert [%{birth_date: nil}] = RosterLine.parse("Awa;f;;2010")
  end

  test "a phone without a name still makes a guardian named after the student's family" do
    assert [%{guardian: %{full_name: "Parent de Awa Nkolo", phone: "677123456"}}] =
             RosterLine.parse("Awa Nkolo;f;;;;;677123456")
  end
end
```

Add to `enroll_import_live_test.exs` (reuse its existing setup names — read the file first; it builds a
school, a class `cg` and a logged-in head):

```elixir
  test "imports birth details and links a sibling's parent by phone", %{conn: conn, scope: scope, cg: cg} do
    {:ok, paul} = Enrollment.add_student(scope, cg, %{full_name: "Paul Nkolo", sex: :m})
    {:ok, jean} = Enrollment.add_guardian(scope, paul, %{full_name: "Jean Nkolo", relationship: :pere, phone: "677123456"})

    {:ok, view, _html} = live(conn, ~p"/school/classes/#{cg.id}/import")

    view
    |> form("#import-form", raw: "Awa Nkolo;f;M-9;02/04/2013;Yaoundé;Jean Nkolo;+237 677 12 34 56\nZoé;f;;;;Papa Zoé;12")
    |> render_submit()

    view |> element("#confirm-import") |> render_click()

    awa = Enrollment.list_students(scope, cg) |> Enum.find(&(&1.full_name == "Awa Nkolo"))
    assert awa.birth_date == ~D[2013-04-02]
    assert [%{guardian: %{id: id}, primary_contact: true}] = Enrollment.list_guardian_links(scope, awa)
    assert id == jean.id

    zoe = Enrollment.list_students(scope, cg) |> Enum.find(&(&1.full_name == "Zoé"))
    assert Enrollment.list_guardian_links(scope, zoe) == []
    assert render(view) =~ "Zoé"
    assert has_element?(view, "#guardian-issues")
  end
```

(Use the form id, textarea name and confirm button id the page already has — read
`enroll_import_live.ex:30-110` and adapt the three selectors if they differ.)

Add to the bulletin print controller test:

```elixir
  test "prints date and place of birth when known", %{conn: conn, scope: scope, awa: awa, cg: cg, enrollment: e} do
    {:ok, _} = Enrollment.update_student(awa, %{birth_date: ~D[2013-04-02], birth_place: "Yaoundé"}, scope: scope)
    html = conn |> get(~p"/school/classes/#{cg.id}/students/#{e.id}/bulletin/print") |> html_response(200)
    assert html =~ "02/04/2013"
    assert html =~ "Yaoundé"
  end
```

(Put it in the existing `test/teacher_assistant_web/controllers/bulletin_print_controller_test.exs` and reuse
its setup and print path; rename the bound variables to match.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/roster_line_test.exs`
Expected: FAIL — `RosterLine` is not available.

- [ ] **Step 3: The parser**

```elixir
defmodule TeacherAssistant.Academics.RosterLine do
  @moduledoc """
  Spec KLM1: one pasted roster line per student,
  `nom;sexe;matricule;date de naissance;lieu de naissance;nom du parent;téléphone du parent`
  — every column after the name optional. Pure.
  """

  def parse(raw) do
    raw
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&(&1.full_name == ""))
  end

  defp parse_line(line) do
    [name, sex, matricule, birth_date, birth_place, parent_name, parent_phone] =
      line |> String.split(";") |> Enum.map(&String.trim/1) |> pad(7)

    %{
      full_name: name,
      sex: if(String.downcase(sex) == "m", do: :m, else: :f),
      matricule: blank_to_nil(matricule),
      repeater: false,
      birth_date: parse_date(birth_date),
      birth_place: blank_to_nil(birth_place),
      guardian: guardian(name, parent_name, parent_phone)
    }
  end

  defp pad(fields, n), do: Enum.take(fields ++ List.duplicate("", n), n)

  defp parse_date(value) do
    with [d, m, y] <- String.split(value, "/"),
         {d, ""} <- Integer.parse(d),
         {m, ""} <- Integer.parse(m),
         {y, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(y, m, d) do
      date
    else
      _ -> nil
    end
  end

  defp guardian(_student, _name, ""), do: nil
  defp guardian(student, "", phone), do: %{full_name: "Parent de #{student}", phone: phone}
  defp guardian(_student, name, phone), do: %{full_name: name, phone: phone}

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
```

- [ ] **Step 4: Import attaches the guardian**

In `enrollment.ex` `import_rows/3`: pass the birth fields to `enroll_new/3`
(`Map.take(row, [:full_name, :sex, :matricule, :repeater, :birth_date, :birth_place])`), make the
`:create` branch keep the created student (`{:ok, %{student: student}}`), use the re-enrolled `student` in the
`{:reenroll, student}` branch, and after each successful row call:

```elixir
  # Spec KLM1: the row's parent, matched by phone or created, becomes a guardian.
  defp attach_guardian(acc, _scope, _student, %{guardian: nil}), do: acc
  defp attach_guardian(acc, _scope, _student, row) when not is_map_key(row, :guardian), do: acc

  defp attach_guardian(acc, scope, student, %{guardian: %{full_name: name, phone: phone}}) do
    result =
      case find_guardians_by_phone(scope, phone) do
        [guardian | _] ->
          link_guardian(scope, student, guardian)

        [] ->
          add_guardian(scope, student, %{full_name: name, relationship: :autre, phone: phone})
      end

    case result do
      {:ok, _} -> acc
      {:error, :already_linked} -> acc
      {:error, reason} -> %{acc | guardian_issues: acc.guardian_issues ++ [%{full_name: student.full_name, reason: reason}]}
    end
  end
```

The accumulator starts as `%{created: 0, reenrolled: 0, conflicts: [], guardian_issues: []}`. A guardian
failure never undoes the student's enrollment (same best-effort rule as the rest of the import).

- [ ] **Step 5: The import page**

In `enroll_import_live.ex`: replace `parse_rows/1`, `parse_sex/1` and `blank_to_nil/1` by
`TeacherAssistant.Academics.RosterLine.parse/1`; change the help text to

```elixir
gettext("Une ligne par élève : nom;sexe (m/f);matricule;date de naissance (JJ/MM/AAAA);lieu de naissance;nom du parent;téléphone du parent. Seul le nom est obligatoire.")
```

show in the preview row, when present, the birth date (`Calendar.strftime(row.birth_date, "%d/%m/%Y")`) and
« Parent : <nom> »; and in the done stage a block

```heex
<div :if={@result.guardian_issues != []} id="guardian-issues" class="alert alert-warning text-sm">
  <span>{gettext("Parents non enregistrés (numéro invalide) :")}</span>
  <span :for={i <- @result.guardian_issues}>{i.full_name}</span>
</div>
```

- [ ] **Step 6: Bulletin element and identity**

`bulletin_element.ex`: add `:birth` to `values` (after `:effectif`) and

```elixir
  def label(:birth), do: gettext("Date et lieu de naissance")
```

(`defaults/0` is `values() -- [:qr_code]`, so it is on by default for schools that never saved a choice.)

`bulletin_print_html/show.html.heex`, after the « Classe / Sexe » row of the cartouche:

```heex
        <tr :if={show?(@template, :birth) and (b.student.birth_date || b.student.birth_place)}>
          <td class="k">{tr(@lang, fn -> gettext("Né(e) le") end)}</td>
          <td>{b.student.birth_date && Calendar.strftime(b.student.birth_date, "%d/%m/%Y")}</td>
          <td class="k">{tr(@lang, fn -> gettext("à") end)}</td>
          <td>{b.student.birth_place}</td>
        </tr>
```

`bulletin_live.ex` identity `<dl>`, after Matricule:

```heex
          <div :if={@student.birth_date || @student.birth_place}>
            <dt class="ta-eyebrow">{gettext("Né(e) le")}</dt>
            <dd>
              {@student.birth_date && Calendar.strftime(@student.birth_date, "%d/%m/%Y")}
              <span :if={@student.birth_place}>{gettext("à")} {@student.birth_place}</span>
            </dd>
          </div>
```

Check that the printed bulletin's student struct carries the new attributes (they are plain attributes, so any
load of `Student` includes them); if the bulletin template LiveView test pins the element list, add `:birth`.

- [ ] **Step 7: Run the tests**

Run: `MIX_TEST_PARTITION=3 mix test test/teacher_assistant/academics/roster_line_test.exs test/teacher_assistant_web/live/school/enroll_import_live_test.exs test/teacher_assistant_web/live/school/bulletin_template_live_test.exs test/teacher_assistant_web/controllers test/teacher_assistant_web/live/school/bulletin_live_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/teacher_assistant/academics/roster_line.ex lib/teacher_assistant_web/live/school/enroll_import_live.ex \
  lib/teacher_assistant/enrollment.ex lib/teacher_assistant/academics/bulletin_element.ex \
  lib/teacher_assistant_web/controllers/bulletin_print_html/show.html.heex lib/teacher_assistant_web/live/school/bulletin_live.ex \
  test/teacher_assistant/academics/roster_line_test.exs test/teacher_assistant_web/live/school/enroll_import_live_test.exs \
  test/teacher_assistant_web/controllers
git commit -m "feat: import birth details and parents; birth line on the bulletin"
```

---

### Task 6: Named migration, translations, status, full checks

**Files:**
- Modify: `priv/repo/migrations/*` (dev migrations squashed into one named migration)
- Modify: `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po`, `priv/gettext/fr/LC_MESSAGES/default.po`
- Modify: `docs/superpowers/specs/2026-09-27-mockups-roadmap.md` (KLM1 status line)
- Modify: `priv/repo/demo_school_seeds.exs` (a few guardians and birth dates for visual checks)

- [ ] **Step 1: Named migration**

```bash
mix ash.codegen klm1_students_guardians
MIX_TEST_PARTITION=3 mix ash.migrate
mix ash.codegen --check
```

Expected: the `--dev` migrations are replaced by one `*_klm1_students_guardians.exs`; `--check` reports no
pending changes. Read the migration: two tables, the partial unique index `WHERE primary_contact`, the composite
references with `match: :full`, two nullable `students` columns.

- [ ] **Step 2: Translations**

```bash
mix gettext.extract --merge
grep -n "^msgstr \"\"$" -B2 priv/gettext/en/LC_MESSAGES/default.po | head -80
grep -c "#, fuzzy" priv/gettext/en/LC_MESSAGES/default.po priv/gettext/fr/LC_MESSAGES/default.po
```

Fill every new English `msgstr` (« Parents et tuteurs » → "Parents and guardians", « Contact principal » →
"Main contact", « Élèves » → "Students", « Né(e) le » → "Born on", « à » → "in", « Lier %{name} » → "Link
%{name}", …); for every new `#, fuzzy` entry, correct the `msgstr` and remove the flag. French `msgstr` stay
empty (msgids are French).

- [ ] **Step 3: Demo data**

In `priv/repo/demo_school_seeds.exs`, after students are created, give about a third of them a birth date and
place and a guardian (`Enrollment.add_guardian/3`), with two siblings sharing one parent (link the second with
`Enrollment.link_guardian/3`). Run `mix run priv/repo/demo_school_seeds.exs` on the dev database to check it.

- [ ] **Step 4: Roadmap status**

Under `## KLM1 — Students and guardians (spec)` add:

```markdown
Status: implemented 2026-10-02 (branch `klm1-students-guardians`, plan
`docs/superpowers/plans/2026-10-02-klm1-students-guardians.md`); no visual check done.
```

and note in the KLM1 section that the import is the existing semicolon paste (positional columns), not a CSV
with named headers.

- [ ] **Step 5: Full checks**

```bash
MIX_TEST_PARTITION=3 mix precommit
```

Expected: compile without warnings, format clean, all tests pass. `precommit` reformats files in place: run
`git status` and stage what it rewrote.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations priv/resource_snapshots priv/gettext priv/repo/demo_school_seeds.exs \
  docs/superpowers/specs/2026-09-27-mockups-roadmap.md
git add -u lib test
git commit -m "chore: KLM1 migration, translations, demo data and status"
```
