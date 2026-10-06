defmodule TeacherAssistant.Academics.YearOpenTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Enrollment, Organization, TeacherFixtures}
  alias TeacherAssistant.Academics.Term

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    %{head: head, year: year}
  end

  defp closed_error?({:error, error}), do: Exception.message(error) =~ "est clôturée"
  defp closed_error?(_), do: false

  test "a year starts open; closing it leaves it inactive and closed", ctx do
    assert ctx.year.status == :open
    %{closed: closed, next: next} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert closed.status == :closed
    refute closed.active
    assert Organization.current_academic_year(ctx.head).id == next.id
  end

  test "a closed year is never activated, changed or deleted", ctx do
    %{closed: closed} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert {:error, error} = Organization.activate_academic_year(ctx.head, closed)
    assert Exception.message(error) =~ "L'année Année de référence est clôturée."

    assert closed_error?(
             closed
             |> Ash.Changeset.for_update(:update, %{name: "Autre"}, scope: ctx.head)
             |> Ash.update()
           )

    assert closed_error?(Ash.destroy(closed, scope: ctx.head))
  end

  test "nothing is added to a closed year", ctx do
    %{closed: closed} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert closed_error?(
             Enrollment.create_class_group(ctx.head, closed, %{label: "6ème Y", level: "6ème"})
           )

    assert closed_error?(
             Term
             |> Ash.Changeset.for_create(:create, %{position: 9, academic_year_id: closed.id},
               scope: ctx.head
             )
             |> Ash.create()
           )
  end

  test "an existing class of a closed year is neither renamed nor deleted", ctx do
    [cg | _] = Enrollment.list_class_groups(ctx.head, ctx.year)
    TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert closed_error?(
             cg
             |> Ash.Changeset.for_update(:update, %{label: "Renommée"}, scope: ctx.head)
             |> Ash.update()
           )

    assert closed_error?(Ash.destroy(cg, scope: ctx.head))
  end

  test "the open year is not affected", ctx do
    %{next: next} = TeacherFixtures.close_year!(ctx.head, ctx.year)

    assert {:ok, _} =
             Enrollment.create_class_group(ctx.head, next, %{label: "6ème Y", level: "6ème"})
  end
end
