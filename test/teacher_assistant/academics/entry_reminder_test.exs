defmodule TeacherAssistant.Academics.EntryReminderTest do
  use TeacherAssistant.DataCase, async: true

  alias TeacherAssistant.{Assessment, Curriculum, Enrollment, Notifications, Organization}
  alias TeacherAssistant.TeacherFixtures
  alias TeacherAssistant.Academics.Reference

  setup do
    %{scope: head, year: year} = TeacherFixtures.setup_complete_school_fixture()
    [seq | _] = Organization.list_sequences(head, year)
    {:ok, cg} = Enrollment.create_class_group(head, year, %{label: "3e Z", level: "3ème"})
    {:ok, s1} = Enrollment.add_student(head, cg, %{full_name: "Awa", sex: :f})
    {:ok, _} = Enrollment.add_student(head, cg, %{full_name: "Bob", sex: :m})

    maths = TeacherFixtures.member_scope_fixture(head)
    english = TeacherFixtures.member_scope_fixture(head)
    censeur = TeacherFixtures.member_scope_fixture(head, %{roles: [:vice_principal]})

    {:ok, tc_maths} = Curriculum.assign_teacher(head, cg, maths.current_user, %{subject: "Maths"})

    {:ok, tc_en} =
      Curriculum.assign_teacher(head, cg, english.current_user, %{subject: "Anglais"})

    # Maths 50 %, Anglais 0 % (nothing entered).
    {:ok, a} = Assessment.create_assessment(head, tc_maths, seq, %{label: "Interro 1"})
    :ok = Assessment.upsert_marks(head, a, [%{student_id: s1.id, score: Decimal.new(10)}])

    %{
      head: head,
      year: year,
      seq: seq,
      maths: maths,
      english: english,
      censeur: censeur,
      tc_maths: tc_maths,
      tc_en: tc_en
    }
  end

  test "« Relancer » notifies the course's teacher and logs the day", ctx do
    assert {:ok, r} = Assessment.remind_entry(ctx.head, ctx.seq, ctx.tc_en.id)
    assert r.sent_on == Reference.today()
    assert r.sent_by_user_id == ctx.head.current_user.id

    assert %{unread: 1, latest: [n]} = Notifications.bell(ctx.english)
    assert n.kind == :entry_reminder
    assert n.link == "/school/courses"

    assert n.params == %{
             "subject" => "Anglais",
             "class" => "3e Z",
             "sequence" => to_string(ctx.seq.number)
           }

    assert Assessment.reminder_dates(ctx.head, ctx.seq) == %{ctx.tc_en.id => Reference.today()}
  end

  test "a second reminder the same day is refused quietly, whoever sends it", ctx do
    {:ok, _} = Assessment.remind_entry(ctx.head, ctx.seq, ctx.tc_en.id)

    assert {:error, :already_reminded} =
             Assessment.remind_entry(ctx.censeur, ctx.seq, ctx.tc_en.id)

    assert {:error, :already_reminded} = Assessment.remind_entry(ctx.head, ctx.seq, ctx.tc_en.id)
    assert %{unread: 1} = Notifications.bell(ctx.english)
  end

  test "a teacher cannot remind", ctx do
    assert {:error, %Ash.Error.Forbidden{}} =
             Assessment.remind_entry(ctx.maths, ctx.seq, ctx.tc_en.id)

    assert %{unread: 0} = Notifications.bell(ctx.english)
  end

  test "« Relancer tous les retards » reminds every lagging course, once", ctx do
    assert {:ok, 2} = Assessment.remind_late(ctx.head, ctx.year, ctx.seq)
    assert %{unread: 1} = Notifications.bell(ctx.english)
    # Maths is at 50 %: lagging too.
    assert %{unread: 1} = Notifications.bell(ctx.maths)

    assert {:ok, 0} = Assessment.remind_late(ctx.censeur, ctx.year, ctx.seq)
    assert %{unread: 1} = Notifications.bell(ctx.english)
  end

  test "remind_teacher reminds each of the teacher's lagging courses once a day", ctx do
    teacher_id = ctx.english.current_user.id
    assert {:ok, 1} = Assessment.remind_teacher(ctx.head, ctx.year, ctx.seq, teacher_id)
    assert %{unread: 1} = Notifications.bell(ctx.english)
    assert %{unread: 0} = Notifications.bell(ctx.maths)
    assert {:ok, 0} = Assessment.remind_teacher(ctx.head, ctx.year, ctx.seq, teacher_id)
  end
end
