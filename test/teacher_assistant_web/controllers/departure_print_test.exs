defmodule TeacherAssistantWeb.DeparturePrintTest do
  @moduledoc "A departed student on paper (A7)."
  use TeacherAssistantWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias TeacherAssistant.{Enrollment, MarksFixtures, Organization}

  setup :register_and_log_in_user

  setup %{scope: scope, year: year} do
    MarksFixtures.start_sequences!(scope, year)
    [term | _] = Organization.list_terms(scope, year)
    {:ok, cg} = Enrollment.create_class_group(scope, year, %{label: "6e P", level: "6ème"})

    {:ok, %{enrollment: e}} =
      Enrollment.enroll_new(scope, cg, %{full_name: "Awa Partie", sex: :f})

    {:ok, _} = Enrollment.enroll_new(scope, cg, %{full_name: "Bilal Reste", sex: :m})
    today = TeacherAssistant.Academics.Reference.today()
    {:ok, e} = Enrollment.leave(scope, e, %{departure_reason: :transfer, left_on: today})
    %{cg: cg, e: e, term: term, today: today}
  end

  test "the trimester bulletin prints « Parti(e) le » under the name", ctx do
    html =
      ctx.conn
      |> get(
        ~p"/school/classes/#{ctx.cg.id}/students/#{ctx.e.id}/bulletin/print?period=trim:#{ctx.term.id}"
      )
      |> html_response(200)

    assert html =~ "Awa Partie"
    assert html =~ "Parti(e) le #{Calendar.strftime(ctx.today, "%d/%m/%Y")}"
  end

  test "the departed student's bulletin page still opens for the trimester", ctx do
    {:ok, _view, html} =
      live(
        ctx.conn,
        ~p"/school/classes/#{ctx.cg.id}/students/#{ctx.e.id}/bulletin?period=trim:#{ctx.term.id}"
      )

    assert html =~ "Awa Partie"
  end

  test "today's class list no longer lists her", ctx do
    html =
      ctx.conn |> get(~p"/school/classes/#{ctx.cg.id}/class-list/print") |> html_response(200)

    assert html =~ "Bilal Reste"
    refute html =~ "Awa Partie"
  end
end
