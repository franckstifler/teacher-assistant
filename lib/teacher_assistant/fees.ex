defmodule TeacherAssistant.Fees do
  @moduledoc "Fees (Fees 1): fee types, class amounts, tranches, payments with receipts, balances."

  use Ash.Domain, otp_app: :teacher_assistant

  alias TeacherAssistant.Academics.ClassGroup
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
    resource TeacherAssistant.Academics.FeeType
    resource TeacherAssistant.Academics.ClassFee
    resource TeacherAssistant.Academics.PaymentAllocation
    resource TeacherAssistant.Academics.StudentArrear

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
end
