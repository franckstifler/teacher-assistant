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

  @doc "« Frais exigibles » then « PTA », for a year that has no fee type yet."
  def create_default_fee_types(%Scope{} = scope, %AcademicYear{} = year) do
    case list_fee_types(scope, year) do
      [] ->
        Ash.transact([FeeType], fn ->
          with {:ok, _} <- create_fee_type(scope, year, %{name: "Frais exigibles"}),
               {:ok, _} <- create_fee_type(scope, year, %{name: "PTA"}) do
            :ok
          end
        end)

      _types ->
        {:ok, :ok}
    end
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
    classes =
      scope
      |> TeacherAssistant.Enrollment.list_class_groups(year)
      |> Enum.filter(&(&1.level == cg.level and &1.serie == cg.serie))

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
    tranche
    |> Ash.Changeset.for_update(:update, Map.take(attrs, [:label, :due_date, :percent]),
      scope: scope
    )
    |> Ash.update()
  end

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

  @doc "Carries the arrears of the given (this-year) enrollments; returns how many were carried."
  def carry_arrears(%Scope{} = scope, %AcademicYear{} = year, enrollment_ids) do
    ids = MapSet.new(enrollment_ids)

    picked =
      scope
      |> arrears_candidates(year)
      |> Enum.filter(&(&1.enrollment && MapSet.member?(ids, &1.enrollment.id)))

    Ash.transact([FeeType, StudentArrear], fn ->
      if picked != [], do: ensure_arrears_type!(scope, year)

      for c <- picked do
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
        |> Ash.create!()
      end

      length(picked)
    end)
  end

  defp ensure_arrears_type!(scope, year) do
    case Enum.find(list_fee_types(scope, year), &(&1.kind == :arrears)) do
      %FeeType{} = type ->
        type

      nil ->
        FeeType
        |> Ash.Changeset.for_create(
          :create,
          %{academic_year_id: year.id, name: @arrears_name, position: 0, kind: :arrears},
          scope: scope
        )
        |> Ash.create!()
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

  def clear_adjustment(%Scope{} = scope, %Enrollment{id: e_id}, %FeeType{id: type_id}) do
    FeeAdjustment
    |> Ash.Query.filter(enrollment_id == ^e_id and fee_type_id == ^type_id)
    |> Ash.read!(scope: scope)
    |> Enum.each(&Ash.destroy!(&1, scope: scope))
  end

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

  # --- Balances (shared by setup and payments) ------------------------------------------

  # `%{enrollment_id => FeeBalance.balance/5}` for `enrollments` of `year`, as of `on_date`.
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
