defmodule TeacherAssistant.Fees do
  @moduledoc "Fees: tranche schedule CRUD, payments, adjustment, balances (P2.10)."

  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.ClassGroup
  # `TeacherAssistant.Academics.Enrollment` is the resource struct (used for
  # the `enrollment_id/1` pattern match below); the domain
  # `TeacherAssistant.Enrollment` is always referenced fully qualified so the
  # two never collide under one bare `Enrollment` alias.
  alias TeacherAssistant.Academics.Enrollment
  alias TeacherAssistant.Academics.FeeAdjustment
  alias TeacherAssistant.Academics.FeeBalance
  alias TeacherAssistant.Academics.FeeTranche
  alias TeacherAssistant.Academics.Payment

  resources do
    resource FeeTranche do
      define :list_tranches_for_class_group_id,
        action: :for_class_group,
        args: [:class_group_id]

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

      define :delete_payment, action: :destroy
    end
  end

  authorization do
    authorize :when_requested
  end

  @valid_methods MapSet.new([:cash, :mobile_money, :bank_transfer, :other])

  # --- Tranches --------------------------------------------------------------

  @doc """
  Lists `FeeTranche`s for `class_group`, ordered by `position` ascending.
  """
  def list_tranches(%ClassGroup{id: cg_id}), do: list_tranches_for_class_group_id!(cg_id)

  @doc """
  Adds a fee tranche to `class_group`. `attrs` carries `label`, `amount`
  (integer FCFA), optional `due_date`. Rejects a negative `amount` with
  `{:error, :invalid_amount}`. `workspace_id` is taken from the class
  group; `position` is set to the next index (count of existing tranches).
  """
  def add_tranche(%ClassGroup{} = class_group, attrs) do
    amount = attrs[:amount] || attrs["amount"]

    with :ok <- validate_amount(amount) do
      position = length(list_tranches(class_group))

      FeeTranche
      |> Ash.Changeset.for_create(:create, %{
        label: attrs[:label] || attrs["label"],
        amount: amount,
        due_date: attrs[:due_date] || attrs["due_date"],
        position: position,
        workspace_id: class_group.workspace_id,
        class_group_id: class_group.id
      })
      |> Ash.create()
      |> case do
        {:ok, tranche} -> {:ok, tranche}
        {:error, _error} -> {:error, :tranche_failed}
      end
    end
  end

  @doc """
  Updates `tranche` with `attrs`. Rejects a negative `amount` (when
  present) with `{:error, :invalid_amount}`. Sanitizes any Ash write
  failure to `{:error, :tranche_failed}`.
  """
  def update_tranche(%FeeTranche{} = tranche, attrs) do
    amount = attrs[:amount] || attrs["amount"]

    with :ok <- validate_amount(amount) do
      update_attrs =
        Map.take(attrs, [:label, "label", :amount, "amount", :due_date, "due_date"])

      tranche
      |> Ash.Changeset.for_update(:update, update_attrs)
      |> Ash.update()
      |> case do
        {:ok, tranche} -> {:ok, tranche}
        {:error, _error} -> {:error, :tranche_failed}
      end
    end
  end

  defp validate_amount(nil), do: :ok
  defp validate_amount(amount) when is_integer(amount) and amount >= 0, do: :ok
  defp validate_amount(_amount), do: {:error, :invalid_amount}

  # --- Payments ----------------------------------------------------------

  @doc """
  Records a payment for `enrollment` (struct or bare id). `attrs` carries
  `amount` (integer FCFA), `paid_on`, `method` (atom), optional `reference`,
  optional `note`. Rejects `amount <= 0` with `{:error, :invalid_amount}`
  and a `method` outside the enum whitelist with `{:error, :invalid_method}`.
  `workspace_id` is taken from the enrollment.
  """
  def record_payment(enrollment, attrs, recorded_by_user_id) do
    amount = attrs[:amount] || attrs["amount"]
    method = attrs[:method] || attrs["method"]

    with :ok <- validate_positive_amount(amount),
         :ok <- validate_method(method),
         {:ok, %Enrollment{} = e} <- fetch_enrollment(enrollment) do
      Payment
      |> Ash.Changeset.for_create(:create, %{
        amount: amount,
        paid_on: attrs[:paid_on] || attrs["paid_on"],
        method: method,
        reference: attrs[:reference] || attrs["reference"],
        note: attrs[:note] || attrs["note"],
        recorded_by_user_id: recorded_by_user_id,
        workspace_id: e.workspace_id,
        enrollment_id: e.id
      })
      |> Ash.create()
      |> case do
        {:ok, payment} -> {:ok, payment}
        {:error, _error} -> {:error, :payment_failed}
      end
    end
  end

  defp validate_positive_amount(amount) when is_integer(amount) and amount > 0, do: :ok
  defp validate_positive_amount(_amount), do: {:error, :invalid_amount}

  defp validate_method(method) do
    if MapSet.member?(@valid_methods, method), do: :ok, else: {:error, :invalid_method}
  end

  @doc """
  Lists `Payment`s for `enrollment` (struct or bare id), newest first
  (`paid_on` desc, then `inserted_at` desc).
  """
  def list_payments(enrollment) do
    id = enrollment_id(enrollment)
    list_payments_for_enrollment_id!(id)
  end

  # --- Adjustments ---------------------------------------------------------

  @doc """
  Upserts the fee adjustment for `enrollment` (struct or bare id) to `attrs`
  (`amount`, `reason`), recorded by `recorded_by_user_id`. Rejects a
  negative `amount` with `{:error, :invalid_amount}`. `workspace_id` is
  taken from the enrollment.
  """
  def set_adjustment(enrollment, attrs, recorded_by_user_id) do
    amount = attrs[:amount] || attrs["amount"]

    with :ok <- validate_amount(amount),
         {:ok, %Enrollment{} = e} <- fetch_enrollment(enrollment) do
      FeeAdjustment
      |> Ash.Changeset.for_create(:set, %{
        amount: amount,
        reason: attrs[:reason] || attrs["reason"],
        recorded_by_user_id: recorded_by_user_id,
        workspace_id: e.workspace_id,
        enrollment_id: e.id
      })
      |> Ash.create()
      |> case do
        {:ok, adjustment} -> {:ok, adjustment}
        {:error, _error} -> {:error, :adjustment_failed}
      end
    end
  end

  @doc "Deletes the fee adjustment for `enrollment` (struct or bare id), if any."
  def clear_adjustment(enrollment) do
    id = enrollment_id(enrollment)
    adjustments = list_adjustments_for_enrollment_id!(id)

    try do
      Enum.each(adjustments, &Ash.destroy!/1)
      {:ok, length(adjustments)}
    rescue
      _ -> {:error, :adjustment_failed}
    end
  end

  # --- Balances --------------------------------------------------------------

  @doc """
  Returns the `FeeBalance.compute/4` map for `enrollment` (struct or bare
  id) as of `on_date`: tranches from the enrollment's class group, that
  student's payments, and that student's adjustment amount (0 when none).
  """
  def student_balance(enrollment, on_date \\ Date.utc_today()) do
    {:ok, %Enrollment{} = e} = fetch_enrollment(enrollment)

    tranches = list_tranches(%ClassGroup{id: e.class_group_id})
    payments = list_payments(e)
    adjustment_amount = adjustment_amount_for(e.id)

    FeeBalance.compute(tranches, payments, adjustment_amount, on_date)
  end

  defp adjustment_amount_for(enrollment_id) do
    case list_adjustments_for_enrollment_id!(enrollment_id) do
      [adjustment | _] -> adjustment.amount
      [] -> 0
    end
  end

  @doc """
  Returns `%{enrollment_id => balance_map}` for the whole roster of
  `class_group` as of `on_date`, batching reads to avoid N+1. Entry-less
  enrollments get the schedule's full due / status with 0 paid, 0
  adjustment.
  """
  def class_balances(%ClassGroup{} = class_group, on_date \\ Date.utc_today()) do
    roster = TeacherAssistant.Enrollment.list_roster(class_group)
    enrollment_ids = Enum.map(roster, & &1.enrollment.id)

    tranches = list_tranches(class_group)

    payments_by_enrollment =
      if enrollment_ids == [] do
        %{}
      else
        enrollment_ids
        |> list_payments_for_enrollment_ids!()
        |> Enum.group_by(& &1.enrollment_id)
      end

    adjustments_by_enrollment =
      if enrollment_ids == [] do
        %{}
      else
        enrollment_ids
        |> list_adjustments_for_enrollment_ids!()
        |> Map.new(&{&1.enrollment_id, &1.amount})
      end

    Map.new(roster, fn %{enrollment: enrollment} ->
      payments = Map.get(payments_by_enrollment, enrollment.id, [])
      adjustment_amount = Map.get(adjustments_by_enrollment, enrollment.id, 0)

      balance = FeeBalance.compute(tranches, payments, adjustment_amount, on_date)

      {enrollment.id, balance}
    end)
  end

  defp enrollment_id(%Enrollment{id: id}), do: id
  defp enrollment_id(id) when is_binary(id), do: id

  defp fetch_enrollment(%Enrollment{} = e), do: {:ok, e}

  defp fetch_enrollment(id) when is_binary(id) do
    case Ash.get(Enrollment, id) do
      {:ok, e} -> {:ok, e}
      {:error, _error} -> {:error, :not_found}
    end
  end
end
