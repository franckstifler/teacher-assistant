defmodule TeacherAssistant.Fees do
  @moduledoc "Fees (Fees 1): fee types, class amounts, tranches, payments with receipts, balances."

  use Ash.Domain, otp_app: :teacher_assistant

  require Ash.Query

  alias TeacherAssistant.Organization
  alias TeacherAssistant.Academics.AcademicYear
  alias TeacherAssistant.Academics.ClassFee
  alias TeacherAssistant.Academics.ClassGroup
  alias TeacherAssistant.Academics.FeeType
  alias TeacherAssistant.Academics.PaymentAllocation
  alias TeacherAssistant.Academics.Reference
  alias TeacherAssistant.Academics.SchoolTemplates
  alias TeacherAssistant.Academics.StudentArrear
  # `TeacherAssistant.Academics.Enrollment` is the resource struct every
  # function below pattern-matches on; the domain `TeacherAssistant.Enrollment`
  # is always referenced fully qualified so the two never collide under one
  # bare `Enrollment` alias.
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.FeeAdjustment
  alias TeacherAssistant.Academics.FeeBalance
  alias TeacherAssistant.Academics.FeeTranche
  alias TeacherAssistant.Academics.Payment
  alias TeacherAssistant.Scope

  resources do
    resource FeeType
    resource ClassFee
    resource PaymentAllocation
    resource StudentArrear

    resource FeeTranche do
      define :delete_tranche, action: :destroy
    end

    resource FeeAdjustment do
      define :list_adjustments_for_enrollment_id,
        action: :for_enrollment,
        args: [:enrollment_id]

      define :list_adjustments_for_enrollment_ids,
        action: :for_enrollment_ids,
        args: [:enrollment_ids]
    end

    resource TeacherAssistant.Academics.FeeSendOut do
      define :list_send_outs_on, action: :on_date, args: [:enrollment_ids, :date]
    end

    resource TeacherAssistant.Academics.ReturnNote do
      define :list_notes_for_enrollment_ids, action: :for_enrollment_ids, args: [:enrollment_ids]
    end

    resource TeacherAssistant.Academics.FeeWarning do
      define :list_warnings_for_enrollment_ids,
        action: :for_enrollment_ids,
        args: [:enrollment_ids]
    end

    resource Payment do
      define :list_payments_for_enrollment_id, action: :for_enrollment, args: [:enrollment_id]

      define :list_payments_for_enrollment_ids,
        action: :for_enrollment_ids,
        args: [:enrollment_ids]
    end
  end

  authorization do
    authorize :by_default
  end

  @doc "Whether the scope may manage tranches, payments and adjustments (fees axis)."
  def can_manage_fees?(scope), do: Ash.can?({Payment, :create}, scope)

  # --- Fee types (Fees 1) -------------------------------------------------------

  @arrears_name "Reliquat année précédente"

  @doc "The year's fee types in payment order (the arrears type, when carried, first)."
  def list_fee_types(%Scope{} = scope, %AcademicYear{id: year_id}) do
    FeeType
    |> Ash.Query.for_read(:for_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.read!()
  end

  @doc "Adds a regular fee type at the end of the payment order."
  def create_fee_type(%Scope{} = scope, %AcademicYear{} = year, %{name: name}) do
    position =
      scope |> list_fee_types(year) |> Enum.map(& &1.position) |> Enum.max(fn -> 0 end)

    FeeType
    |> Ash.Changeset.for_create(
      :create,
      %{academic_year_id: year.id, name: name, position: position + 1},
      scope: scope
    )
    |> Ash.create()
  end

  @public_defaults ["Frais exigibles", "PTA"]

  @doc """
  The fee types offered when a school sets its fees up (UX refonte 2026-11-03), by its
  sector: `defaults` ticked at first, `suggestions` one tap away. A public school
  charges no « scolarité »: its preset stays « Frais exigibles » + « PTA ».
  """
  def fee_type_presets(:public),
    do: %{defaults: @public_defaults, suggestions: ["Frais d'examen", "Tenue"]}

  def fee_type_presets(_sector),
    do: %{
      defaults: ["Inscription", "Scolarité", "APEE"],
      suggestions: ["Frais d'examen", "Tenue"]
    }

  @doc "`names` in that order (« Frais exigibles » then « PTA » by default), for a year that has no fee type yet."
  def create_default_fee_types(
        %Scope{} = scope,
        %AcademicYear{} = year,
        names \\ @public_defaults
      ) do
    case list_fee_types(scope, year) do
      [] ->
        Ash.transact([FeeType], fn ->
          Enum.reduce_while(names, :ok, fn name, :ok ->
            case create_fee_type(scope, year, %{name: name}) do
              {:ok, _} -> {:cont, :ok}
              error -> {:halt, error}
            end
          end)
        end)

      _types ->
        {:ok, :ok}
    end
  end

  @doc """
  How far the fee setup has gone (the three steps types → amounts → tranches):
  active regular `types`, `classes` of the year and how many are `priced` (an amount
  above 0), `tranches`, and `done` — the steps completed in order (0..3).
  """
  def setup_status(%Scope{} = scope, %AcademicYear{} = year) do
    types = scope |> list_fee_types(year) |> Enum.filter(&(&1.kind == :regular and &1.active?))
    type_ids = MapSet.new(types, & &1.id)
    classes = TeacherAssistant.Enrollment.list_class_groups(scope, year)

    priced =
      scope
      |> class_fee_grid(year)
      |> Enum.filter(fn {{_cg, type_id}, amount} -> amount > 0 and type_id in type_ids end)
      |> Enum.map(fn {{cg, _}, _} -> cg end)
      |> Enum.uniq()
      |> length()

    tranches = length(list_tranches(scope, year))

    done =
      [length(types) > 0, priced > 0, tranches > 0]
      |> Enum.take_while(& &1)
      |> length()

    %{
      types: length(types),
      classes: length(classes),
      priced: priced,
      tranches: tranches,
      done: done
    }
  end

  def rename_fee_type(%Scope{} = scope, %FeeType{kind: :regular} = type, name),
    do: update_fee_type(scope, type, %{name: name})

  def rename_fee_type(_scope, _type, _name), do: {:error, :arrears}

  @doc "Swaps a regular type with its neighbour in the payment order; the arrears type never moves."
  def move_fee_type(%Scope{} = scope, %FeeType{kind: :regular} = type, direction)
      when direction in [:up, :down] do
    year = %AcademicYear{id: type.academic_year_id}
    regular = scope |> list_fee_types(year) |> Enum.filter(&(&1.kind == :regular))
    index = Enum.find_index(regular, &(&1.id == type.id))
    other_index = if direction == :up, do: index - 1, else: index + 1

    case other_index >= 0 && Enum.at(regular, other_index) do
      %FeeType{} = other ->
        Ash.transact([FeeType], fn ->
          with {:ok, _} <- update_fee_type(scope, type, %{position: other.position}),
               {:ok, _} <- update_fee_type(scope, other, %{position: type.position}) do
            :ok
          end
        end)
        |> ok()

      _ ->
        :ok
    end
  end

  def move_fee_type(_scope, _type, _direction), do: :ok

  @doc "Retires a type nothing uses this year (no class amount above 0, no payment); `{:error, :in_use}` otherwise."
  def deactivate_fee_type(%Scope{} = scope, %FeeType{} = type) do
    if fee_type_in_use?(scope, type),
      do: {:error, :in_use},
      else: update_fee_type(scope, type, %{active?: false})
  end

  def reactivate_fee_type(%Scope{} = scope, %FeeType{} = type),
    do: update_fee_type(scope, type, %{active?: true})

  defp fee_type_in_use?(scope, %FeeType{id: id}) do
    ClassFee |> Ash.Query.filter(fee_type_id == ^id and amount > 0) |> Ash.exists?(scope: scope) or
      PaymentAllocation |> Ash.Query.filter(fee_type_id == ^id) |> Ash.exists?(scope: scope)
  end

  defp update_fee_type(scope, type, attrs),
    do: type |> Ash.Changeset.for_update(:update, attrs, scope: scope) |> Ash.update()

  # --- Class amounts --------------------------------------------------------------

  @doc "The year's class amounts: `%{{class_group_id, fee_type_id} => amount}`."
  def class_fee_grid(%Scope{} = scope, %AcademicYear{id: year_id}) do
    ClassFee
    |> Ash.Query.filter(fee_type.academic_year_id == ^year_id)
    |> Ash.read!(scope: scope)
    |> Map.new(&{{&1.class_group_id, &1.fee_type_id}, &1.amount})
  end

  def set_class_fee(
        %Scope{} = scope,
        %ClassGroup{id: cg_id},
        %FeeType{kind: :regular, id: type_id},
        amount
      ) do
    ClassFee
    |> Ash.Changeset.for_create(
      :set,
      %{class_group_id: cg_id, fee_type_id: type_id, amount: amount},
      scope: scope
    )
    |> Ash.create()
  end

  def set_class_fee(_scope, _cg, _type, _amount), do: {:error, :arrears}

  @doc "Sets the amount for every class of the year with the same level and série as `cg`."
  def set_level_fee(
        %Scope{} = scope,
        %AcademicYear{} = year,
        %ClassGroup{} = cg,
        %FeeType{} = type,
        amount
      ) do
    scope
    |> TeacherAssistant.Enrollment.list_class_groups(year)
    |> Enum.filter(&(&1.level == cg.level and &1.serie == cg.serie))
    |> then(&set_classes_fee(scope, &1, type, amount))
  end

  @doc """
  Sets the amount for every class of the year at `level`, whatever its série (the
  « Montants par niveau » row); a class can be adjusted afterwards.
  """
  def set_level_fees(%Scope{} = scope, %AcademicYear{} = year, level, %FeeType{} = type, amount) do
    scope
    |> TeacherAssistant.Enrollment.list_class_groups(year)
    |> Enum.filter(&(&1.level == level))
    |> then(&set_classes_fee(scope, &1, type, amount))
  end

  defp set_classes_fee(scope, classes, type, amount) do
    Ash.transact([ClassFee], fn ->
      Enum.reduce_while(classes, :ok, fn c, :ok ->
        case set_class_fee(scope, c, type, amount) do
          {:ok, _} -> {:cont, :ok}
          {:error, error} -> {:halt, Ash.DataLayer.rollback([ClassFee], error)}
        end
      end)
    end)
    |> ok()
  end

  # --- Tranches -------------------------------------------------------------------

  @doc "The year's tranches, by due date."
  def list_tranches(%Scope{} = scope, %AcademicYear{id: year_id}) do
    FeeTranche
    |> Ash.Query.for_read(:for_year, %{academic_year_id: year_id}, scope: scope)
    |> Ash.read!()
  end

  def add_tranche(%Scope{} = scope, %AcademicYear{} = year, attrs) do
    with :ok <- check_rising(list_tranches(scope, year), attrs) do
      insert_tranche(scope, year, attrs)
    end
  end

  defp insert_tranche(scope, year, attrs) do
    FeeTranche
    |> Ash.Changeset.for_create(
      :create,
      attrs
      |> Map.take([:label, :due_date, :percent])
      |> Map.merge(%{academic_year_id: year.id, position: length(list_tranches(scope, year))}),
      scope: scope
    )
    |> Ash.create()
  end

  def update_tranche(%Scope{} = scope, %FeeTranche{} = tranche, attrs) do
    others =
      scope
      |> list_tranches(%AcademicYear{id: tranche.academic_year_id})
      |> Enum.reject(&(&1.id == tranche.id))

    proposed =
      Map.merge(Map.take(tranche, [:due_date, :percent]), Map.take(attrs, [:due_date, :percent]))

    with :ok <- check_rising(others, proposed) do
      tranche
      |> Ash.Changeset.for_update(:update, Map.take(attrs, [:label, :due_date, :percent]),
        scope: scope
      )
      |> Ash.update()
    end
  end

  # Rule 3: cumulative percents rise with the due dates (a later tranche asks for more).
  defp check_rising(tranches, %{due_date: %Date{}, percent: percent} = new)
       when is_integer(percent) do
    percents =
      [new | tranches]
      |> Enum.sort_by(& &1.due_date, Date)
      |> Enum.map(& &1.percent)

    if percents == Enum.sort(percents) and percents == Enum.dedup(percents),
      do: :ok,
      else: {:error, :not_rising}
  end

  defp check_rising(_tranches, _new), do: :ok

  def delete_tranche(%Scope{} = scope, %FeeTranche{} = tranche),
    do: Ash.destroy(tranche, scope: scope)

  # --- Copy the previous year -------------------------------------------------------

  @doc """
  Copies the latest earlier year's regular fee types, class amounts and tranches (dates
  one year later) into `year`, which must have no fee type yet. A class takes the
  amounts of last year's class with the same label, else the same level and série;
  `unmatched` lists this year's classes left without amounts.
  """
  def copy_previous_year(%Scope{} = scope, %AcademicYear{} = year) do
    with [] <- list_fee_types(scope, year),
         %AcademicYear{} = source <- previous_year_with_fees(scope, year) do
      old_classes = sorted_classes(scope, source)
      new_classes = sorted_classes(scope, year)
      grid = class_fee_grid(scope, source)

      matches =
        Map.new(new_classes, fn cg ->
          {cg.id,
           Enum.find(old_classes, &(&1.label == cg.label)) ||
             Enum.find(old_classes, &(&1.level == cg.level and &1.serie == cg.serie))}
        end)

      Ash.transact([FeeType, ClassFee, FeeTranche], fn ->
        for old_type <- list_fee_types(scope, source), old_type.kind == :regular do
          {:ok, type} =
            FeeType
            |> Ash.Changeset.for_create(
              :create,
              %{academic_year_id: year.id, name: old_type.name, position: old_type.position},
              scope: scope
            )
            |> Ash.create()

          for cg <- new_classes,
              %ClassGroup{} = old <- [matches[cg.id]],
              amount = grid[{old.id, old_type.id}],
              not is_nil(amount),
              do: {:ok, _} = set_class_fee(scope, cg, type, amount)
        end

        for t <- list_tranches(scope, source) do
          {:ok, _} =
            add_tranche(scope, year, %{
              label: t.label,
              percent: t.percent,
              due_date: Date.shift(t.due_date, year: 1)
            })
        end

        %{unmatched: for(cg <- new_classes, is_nil(matches[cg.id]), do: cg.label)}
      end)
    else
      [_ | _] -> {:error, :not_empty}
      nil -> {:error, :nothing_to_copy}
    end
  end

  defp previous_year_with_fees(scope, year) do
    scope
    |> Organization.list_academic_years()
    |> Enum.filter(&(&1.id != year.id and Date.compare(&1.start_date, year.start_date) == :lt))
    |> Enum.sort_by(& &1.start_date, {:desc, Date})
    |> Enum.find(&(list_fee_types(scope, &1) != []))
  end

  defp sorted_classes(scope, year),
    do:
      scope
      |> TeacherAssistant.Enrollment.list_class_groups(year)
      |> Enum.sort_by(&SchoolTemplates.class_sort_key/1)

  # --- Arrears ---------------------------------------------------------------------

  @doc """
  Students still owing at the end of the latest closed year, not carried yet, by name:
  `%{student, enrollment, amount}` where `enrollment` is their enrollment in `year`
  (nil when they were not re-enrolled: they cannot be carried).
  """
  def arrears_candidates(%Scope{} = scope, %AcademicYear{} = year) do
    case latest_closed_year(scope, year) do
      nil ->
        []

      closed ->
        old = enrollments_of(scope, closed)
        balances = balances(scope, closed, old, closed.end_date)
        current = scope |> enrollments_of(year) |> Map.new(&{&1.student_id, &1})

        carried =
          StudentArrear
          |> Ash.Query.filter(from_academic_year_id == ^closed.id)
          |> Ash.read!(scope: scope)
          |> MapSet.new(& &1.enrollment_id)

        for e <- old,
            %{left: left} = balances[e.id],
            left > 0,
            now <- [current[e.student_id]],
            is_nil(now) or not MapSet.member?(carried, now.id) do
          %{student: e.student, enrollment: now, amount: left, from_year: closed}
        end
        |> Enum.sort_by(&String.downcase(&1.student.full_name))
    end
  end

  @doc """
  Carries the arrears of the given (this-year) enrollments: `{:ok, count}`, or
  `{:error, error}` with nothing written. One carry at a time per year: a second one
  waits, then finds those arrears already carried.
  """
  def carry_arrears(%Scope{} = scope, %AcademicYear{} = year, enrollment_ids) do
    ids = MapSet.new(enrollment_ids)

    TeacherAssistant.Repo.transaction(fn ->
      TeacherAssistant.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
        "arrears:" <> year.id
      ])

      picked =
        scope
        |> arrears_candidates(year)
        |> Enum.filter(&(&1.enrollment && MapSet.member?(ids, &1.enrollment.id)))

      with {:ok, _type} <- ensure_arrears_type(scope, year, picked),
           :ok <- create_arrears(scope, picked) do
        length(picked)
      else
        {:error, error} -> TeacherAssistant.Repo.rollback(error)
      end
    end)
    |> case do
      {:ok, count} -> {:ok, count}
      # A refused create rolls the transaction back with its bare error.
      {:error, error} -> {:error, Ash.Error.to_error_class(error)}
    end
  end

  defp create_arrears(scope, picked) do
    Enum.reduce_while(picked, :ok, fn c, :ok ->
      StudentArrear
      |> Ash.Changeset.for_create(
        :create,
        %{
          enrollment_id: c.enrollment.id,
          from_academic_year_id: c.from_year.id,
          amount: c.amount
        },
        scope: scope
      )
      |> Ash.create()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp ensure_arrears_type(_scope, _year, []), do: {:ok, nil}

  defp ensure_arrears_type(scope, year, _picked) do
    case Enum.find(list_fee_types(scope, year), &(&1.kind == :arrears)) do
      %FeeType{} = type ->
        {:ok, type}

      nil ->
        FeeType
        |> Ash.Changeset.for_create(
          :create,
          %{academic_year_id: year.id, name: @arrears_name, position: 0, kind: :arrears},
          scope: scope
        )
        |> Ash.create()
    end
  end

  defp latest_closed_year(scope, year) do
    scope
    |> Organization.list_academic_years()
    |> Enum.filter(&(&1.status == :closed and &1.id != year.id))
    |> Enum.max_by(& &1.end_date, Date, fn -> nil end)
  end

  defp enrollments_of(scope, %AcademicYear{id: year_id}) do
    Enrollment
    |> Ash.Query.filter(academic_year_id == ^year_id)
    |> Ash.Query.load(:student)
    |> Ash.read!(scope: scope)
  end

  # --- Adjustments ------------------------------------------------------------------

  @doc """
  Sets the student's reduction on one fee type (a positive amount, at most what the
  type costs them); `{:error, :too_large}` beyond it.
  """
  def set_adjustment(%Scope{} = scope, %Enrollment{} = e, %FeeType{} = type, attrs) do
    amount = attrs[:amount] || attrs["amount"]
    base = base_due(scope, e, type)

    cond do
      not (is_integer(amount) and amount > 0) ->
        {:error, :invalid_amount}

      amount > base ->
        {:error, :too_large}

      true ->
        FeeAdjustment
        |> Ash.Changeset.for_create(
          :set,
          %{
            enrollment_id: e.id,
            fee_type_id: type.id,
            amount: amount,
            reason: attrs[:reason] || attrs["reason"],
            recorded_by_user_id: scope.current_user && scope.current_user.id
          },
          scope: scope
        )
        |> Ash.create()
    end
  end

  @doc "Removes the student's reduction on one fee type: `:ok`, or the refusal (closed year, rights)."
  def clear_adjustment(%Scope{} = scope, %Enrollment{id: e_id}, %FeeType{id: type_id}) do
    FeeAdjustment
    |> Ash.Query.filter(enrollment_id == ^e_id and fee_type_id == ^type_id)
    |> Ash.read!(scope: scope)
    |> Enum.reduce_while(:ok, fn adjustment, :ok ->
      case Ash.destroy(adjustment, scope: scope) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  @doc "The student's reductions, one per fee type."
  def list_adjustments(%Scope{} = scope, %Enrollment{id: id}),
    do: list_adjustments_for_enrollment_id!(id, scope: scope)

  # What the type costs the student before any reduction.
  defp base_due(scope, e, %FeeType{kind: :arrears}),
    do: scope |> arrears_by_enrollment([e.id]) |> Map.get(e.id, 0)

  defp base_due(scope, e, %FeeType{id: type_id}) do
    ClassFee
    |> Ash.Query.filter(class_group_id == ^e.class_group_id and fee_type_id == ^type_id)
    |> Ash.read!(scope: scope)
    |> Enum.map(& &1.amount)
    |> Enum.sum()
  end

  # --- Payments and receipts ----------------------------------------------------------

  @valid_methods [:cash, :mobile_money, :bank_transfer, :other]

  @doc """
  Records a payment and issues its receipt in one transaction: the next receipt number
  of the school's year, the split across fee types in payment order, and the frozen
  paid-to-date and left figures. `attrs`: `amount`, `paid_on`, `method`, `reference`
  (required for mobile money and bank transfer), `note`.
  """
  def record_payment(%Scope{} = scope, %Enrollment{} = e, attrs) do
    amount = attrs[:amount] || attrs["amount"]
    method = attrs[:method] || attrs["method"]
    reference = blank_to_nil(attrs[:reference] || attrs["reference"])

    with :ok <- check_payment(amount, method, reference),
         :ok <- check_can_record(scope),
         {:ok, year} <- Ash.get(AcademicYear, e.academic_year_id, scope: scope),
         :ok <- check_has_fee_types(scope, year) do
      Ash.transact([Payment, PaymentAllocation], fn ->
        TeacherAssistant.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
          "receipt:#{e.workspace_id}:#{year.id}"
        ])

        seq = next_seq(e.workspace_id, year.id)
        e = Ash.load!(e, [:student, :class_group], scope: scope)
        balance = balances(scope, year, [e], Reference.today())[e.id]
        ids = Enum.map(balance.by_type, & &1.type_id)
        due = Map.new(balance.by_type, &{&1.type_id, &1.due})
        paid = Map.new(balance.by_type, &{&1.type_id, &1.paid})

        with {:ok, payment} <-
               Payment
               |> Ash.Changeset.for_create(
                 :create,
                 %{
                   enrollment_id: e.id,
                   academic_year_id: year.id,
                   amount: amount,
                   paid_on: attrs[:paid_on] || attrs["paid_on"] || Reference.today(),
                   method: method,
                   reference: reference,
                   note: blank_to_nil(attrs[:note] || attrs["note"])
                 },
                 scope: scope
               )
               # Computed here, under the numbering lock — never action inputs.
               |> Ash.Changeset.force_change_attributes(%{
                 recorded_by_user_id: scope.current_user && scope.current_user.id,
                 seq: seq,
                 number:
                   "R#{year.start_date.year}-#{String.pad_leading(Integer.to_string(seq), 6, "0")}",
                 paid_to_date: balance.total_paid + amount,
                 left_after: balance.left - amount,
                 student_name: e.student.full_name,
                 class_label: e.class_group.label
               })
               |> Ash.create() do
          for {type_id, share} <- FeeBalance.allocate(amount, ids, due, paid) do
            PaymentAllocation
            |> Ash.Changeset.for_create(
              :create,
              %{payment_id: payment.id, fee_type_id: type_id, amount: share},
              scope: scope
            )
            |> Ash.Changeset.force_change_attributes(%{
              paid_to_date: paid[type_id] + share,
              left_after: due[type_id] - paid[type_id] - share
            })
            |> Ash.create!()
          end

          Ash.load!(payment, [allocations: :fee_type], scope: scope)
        else
          {:error, error} -> Ash.DataLayer.rollback([Payment], error)
        end
      end)
      |> tap(fn
        # Fees 2: a student sent home today who is now up to date may go back to class.
        {:ok, _payment} -> TeacherAssistant.FeeControl.lift_send_out_if_up_to_date(scope, e)
        _ -> :ok
      end)
    end
  end

  defp check_can_record(scope),
    do: if(can_manage_fees?(scope), do: :ok, else: {:error, Ash.Error.Forbidden.exception([])})

  defp check_has_fee_types(scope, year),
    do:
      if(Enum.any?(list_fee_types(scope, year), & &1.active?),
        do: :ok,
        else: {:error, :no_fee_types}
      )

  defp check_payment(amount, _method, _reference) when not (is_integer(amount) and amount > 0),
    do: {:error, :invalid_amount}

  defp check_payment(_amount, method, _reference) when method not in @valid_methods,
    do: {:error, :invalid_method}

  defp check_payment(_amount, method, nil) when method in [:mobile_money, :bank_transfer],
    do: {:error, :reference_required}

  defp check_payment(_amount, _method, _reference), do: :ok

  @doc false
  # Under the transaction's advisory lock: the year's next sequence number of a numbered
  # paper (receipts; Fees 2 return notes and warnings).
  def next_seq(resource \\ Payment, workspace_id, year_id) do
    resource
    |> Ash.Query.filter(academic_year_id == ^year_id)
    |> Ash.max!(:seq, authorize?: false, tenant: workspace_id)
    |> case do
      nil -> 1
      max -> max + 1
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  @doc "Cancels a receipt (with a reason); its money stops counting, later receipts keep their split."
  def cancel_payment(%Scope{} = scope, %Payment{} = payment, reason) do
    case blank_to_nil(reason) do
      nil ->
        {:error, :reason_required}

      reason ->
        payment
        |> Ash.Changeset.for_update(:cancel, %{reason: reason}, scope: scope)
        |> Ash.update()
    end
  end

  @doc "The student's payments, newest first, with their split."
  def list_payments(%Scope{} = scope, %Enrollment{id: id}),
    do: list_payments_for_enrollment_id!(id, scope: scope)

  def get_payment(%Scope{} = scope, id),
    do: Ash.get(Payment, id, scope: scope, load: [allocations: :fee_type])

  @doc "The year's latest receipts, with student and class."
  def recent_payments(%Scope{} = scope, %AcademicYear{id: year_id}, limit \\ 20) do
    Payment
    |> Ash.Query.filter(academic_year_id == ^year_id)
    |> Ash.Query.sort(seq: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load(enrollment: [:student, :class_group])
    |> Ash.read!(scope: scope)
  end

  @doc "Everything the printed receipt shows; `{:error, :not_found}` outside the scope's reach."
  def receipt(%Scope{} = scope, payment_id) do
    with {:ok, p} <-
           Ash.get(Payment, payment_id,
             scope: scope,
             load: [allocations: :fee_type, enrollment: [:student, :class_group]]
           ) do
      {:ok,
       %{
         payment: p,
         student: p.enrollment.student,
         class_group: p.enrollment.class_group,
         class_label: p.class_label,
         student_name: p.student_name,
         school: scope.current_workspace,
         allocations: allocation_rows(p),
         recorded_by_name: user_name(p.recorded_by_user_id),
         guardians: guardian_phones(scope, p.enrollment.student)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp guardian_phones(scope, student) do
    for link <- TeacherAssistant.Enrollment.list_guardian_links(scope, student),
        link.guardian.phone not in [nil, ""],
        do: %{name: link.guardian.full_name, phone: link.guardian.phone}
  end

  defp allocation_rows(p) do
    p.allocations
    |> Enum.sort_by(& &1.fee_type.position)
    |> Enum.map(
      &%{
        name: &1.fee_type.name,
        amount: &1.amount,
        paid_to_date: &1.paid_to_date,
        left_after: &1.left_after
      }
    )
  end

  @doc false
  defdelegate user_name(id), to: TeacherAssistant.Accounts

  @doc """
  The public check of a receipt (no actor): `{:valid | :cancelled, map}` with only what
  the receipt shows, or `:invalid`.
  """
  def verification(workspace_id, payment_id) do
    case Ash.get(Payment, payment_id,
           tenant: workspace_id,
           authorize?: false,
           load: [:workspace, allocations: :fee_type, enrollment: [:student, :class_group]]
         ) do
      {:ok, p} ->
        {p.status,
         %{
           school_name: p.workspace.name,
           number: p.number,
           paid_on: p.paid_on,
           amount: p.amount,
           method: p.method,
           student_name: p.student_name,
           class_label: p.class_label,
           allocations: Enum.map(allocation_rows(p), &Map.take(&1, [:name, :amount])),
           paid_to_date: p.paid_to_date,
           left_after: p.left_after,
           cancelled_on: p.cancelled_at && DateTime.to_date(p.cancelled_at)
         }}

      _ ->
        :invalid
    end
  rescue
    Ash.Error.Invalid -> :invalid
  end

  @doc "`[{workspace_id, payment_id}]` of every school's receipt with this number (typed check)."
  def find_by_number(number) when is_binary(number) do
    import Ecto.Query

    TeacherAssistant.Repo.all(
      from p in "payments",
        where: p.number == ^(number |> String.trim() |> String.upcase()),
        select: {type(p.workspace_id, Ecto.UUID), type(p.id, Ecto.UUID)}
    )
  end

  # --- Balances and recovery ------------------------------------------------------------

  @doc "The student's balance today (or `on_date`), each fee type with its name."
  def student_fees(%Scope{} = scope, %Enrollment{} = e, on_date \\ Reference.today()) do
    year = Ash.get!(AcademicYear, e.academic_year_id, scope: scope)
    names = scope |> list_fee_types(year) |> Map.new(&{&1.id, &1.name})
    balance = balances(scope, year, [e], on_date)[e.id]
    %{balance | by_type: Enum.map(balance.by_type, &Map.put(&1, :name, names[&1.type_id]))}
  end

  @doc "`%{enrollment_id => balance}` for the class's roster."
  def class_balances(%Scope{} = scope, %ClassGroup{} = cg, on_date \\ Reference.today()) do
    year = Ash.get!(AcademicYear, cg.academic_year_id, scope: scope)

    enrollments =
      scope |> TeacherAssistant.Enrollment.list_roster(cg) |> Enum.map(& &1.enrollment)

    balances(scope, year, enrollments, on_date)
  end

  @doc "Recovery figures for the school and per class (class order)."
  def recovery(%Scope{} = scope, %AcademicYear{} = year, on_date \\ Reference.today()) do
    enrollments = enrollments_of(scope, year)
    balances = balances(scope, year, enrollments, on_date)
    by_class = Enum.group_by(enrollments, & &1.class_group_id, &balances[&1.id])

    %{
      school: FeeBalance.recovery(Map.values(balances)),
      classes:
        Enum.map(
          sorted_classes(scope, year),
          &%{class_group: &1, recovery: FeeBalance.recovery(Map.get(by_class, &1.id, []))}
        )
    }
  end

  # --- Balances (shared by setup and payments) ------------------------------------------

  # `%{enrollment_id => FeeBalance.balance/5}` for `enrollments` of `year`, as of `on_date`.
  @doc false
  # Fees 2 (warnings) reuses the balance computation.
  def balances_for(scope, year, enrollments, on_date),
    do: balances(scope, year, enrollments, on_date)

  defp balances(scope, %AcademicYear{} = year, enrollments, on_date) do
    types = scope |> list_fee_types(year) |> Enum.filter(& &1.active?)
    type_ids = Enum.map(types, & &1.id)
    arrears_type_id = Enum.find_value(types, &(&1.kind == :arrears && &1.id))
    tranches = list_tranches(scope, year)
    grid = class_fee_grid(scope, year)
    ids = Enum.map(enrollments, & &1.id)
    paid = paid_by_enrollment(scope, ids)
    adjustments = adjustments_by_enrollment(scope, ids)
    arrears = arrears_by_enrollment(scope, ids)

    Map.new(enrollments, fn e ->
      class_amounts = Map.new(type_ids, &{&1, Map.get(grid, {e.class_group_id, &1}, 0)})

      due =
        FeeBalance.dues(
          type_ids,
          class_amounts,
          Map.get(arrears, e.id, 0),
          arrears_type_id,
          Map.get(adjustments, e.id, %{})
        )

      {e.id, FeeBalance.balance(type_ids, due, Map.get(paid, e.id, %{}), tranches, on_date)}
    end)
  end

  # Valid allocations: `%{enrollment_id => %{fee_type_id => paid}}`.
  defp paid_by_enrollment(_scope, []), do: %{}

  defp paid_by_enrollment(scope, ids) do
    PaymentAllocation
    |> Ash.Query.filter(payment.enrollment_id in ^ids and payment.status == :valid)
    |> Ash.Query.load(:payment)
    |> Ash.read!(scope: scope)
    |> Enum.reduce(%{}, fn a, acc ->
      Map.update(acc, a.payment.enrollment_id, %{a.fee_type_id => a.amount}, fn by_type ->
        Map.update(by_type, a.fee_type_id, a.amount, &(&1 + a.amount))
      end)
    end)
  end

  defp adjustments_by_enrollment(_scope, []), do: %{}

  defp adjustments_by_enrollment(scope, ids) do
    ids
    |> list_adjustments_for_enrollment_ids!(scope: scope)
    |> Enum.reduce(%{}, fn a, acc ->
      Map.update(
        acc,
        a.enrollment_id,
        %{a.fee_type_id => a.amount},
        &Map.put(&1, a.fee_type_id, a.amount)
      )
    end)
  end

  defp arrears_by_enrollment(_scope, []), do: %{}

  defp arrears_by_enrollment(scope, ids) do
    StudentArrear
    |> Ash.Query.filter(enrollment_id in ^ids)
    |> Ash.read!(scope: scope)
    |> Enum.reduce(%{}, fn a, acc ->
      Map.update(acc, a.enrollment_id, a.amount, &(&1 + a.amount))
    end)
  end

  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error
end
