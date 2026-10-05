# A demo school with a lived-in school year, for looking at the screens in dev:
# staff in every role, 7 classes, a 5-day timetable, two weeks of roll calls up to
# now, S1 marks at varied completion, and sanctions.
#
#     mix run priv/repo/demo_school_seeds.exs
#
# Independent of priv/repo/seeds.exs. Every account's password is "password1234":
#   proviseur@demo.test  head            censeur@demo.test  vice principal (teaches Maths)
#   sg@demo.test         discipline      prof@demo.test     Maths teacher
#   fr@, ang@, phy@, svt@, hg@, ecm@, eps@demo.test — the other teachers
#
# Runs once: if proviseur@demo.test exists it stops. To rebuild, in psql:
#   delete from workspaces where name = 'Lycée Bilingue d''Etoug-Ebé';
#   delete from users where email like '%@demo.test';
unless Mix.env() == :dev, do: raise("demo_school_seeds.exs is for the dev environment only")

require Ash.Query

alias TeacherAssistant.{
  Accounts,
  Assessment,
  Attendance,
  Curriculum,
  Discipline,
  Enrollment,
  Organization,
  Timetabling
}

pw = "password1234"

user = fn email, name ->
  case Accounts.create_user(%{email: email, name: name, password: pw, password_confirmation: pw},
         context: %{private: %{ash_authentication?: true}}
       ) do
    {:ok, u} -> u
    {:error, e} -> raise "user #{email}: #{inspect(e)}"
  end
end

scope_of = fn u, ws ->
  {:ok, s} = Accounts.Workspaces.scope_for(u, ws.id)
  s
end

if Accounts.User
   |> Ash.Query.filter(email == "proviseur@demo.test")
   |> Ash.exists?(authorize?: false) do
  IO.puts("The demo school already exists (proviseur@demo.test) — nothing to do.")
  System.halt(0)
end

head = user.("proviseur@demo.test", "Jean-Marie Abena")

{:ok, ws} =
  Organization.create_school(%TeacherAssistant.Scope{current_user: head}, %{
    name: "Lycée Bilingue d'Etoug-Ebé"
  })

hs = scope_of.(head, ws)

# An operator verifies the school (the only role allowed to): an existing one, else a demo one.
operator =
  Accounts.User |> Ash.Query.filter(role == :admin) |> Ash.read_first!(authorize?: false) ||
    (fn ->
       # bootstrap: the demo operator
       {:ok, admin} =
         Accounts.promote_to_admin(user.("operator@demo.test", "Opérateur"), authorize?: false)

       admin
     end).()

{:ok, profile} = Accounts.fetch_school_profile(hs)
{:ok, _} = Accounts.verify_school(profile, operator.id, actor: operator)

member = fn email, name, roles ->
  u = user.(email, name)

  {:ok, _} =
    Accounts.SchoolMembership
    |> Ash.Changeset.for_create(:create, %{user_id: u.id, roles: roles, active: true}, scope: hs)
    |> Ash.create()

  u
end

censeur = member.("censeur@demo.test", "Marie Ngo Bassa", [:vice_principal])
sg = member.("sg@demo.test", "Paul Essomba", [:discipline_master])
prof = member.("prof@demo.test", "Hélène Mvondo", [:teacher])

teachers = %{
  "Français" => member.("fr@demo.test", "Albert Nkoulou", [:teacher]),
  "Anglais" => member.("ang@demo.test", "Grace Tabi", [:teacher]),
  "Physique" => member.("phy@demo.test", "Didier Fotso", [:teacher]),
  "SVT" => member.("svt@demo.test", "Brigitte Owona", [:teacher]),
  "Histoire-Géographie" => member.("hg@demo.test", "Samuel Ekotto", [:teacher]),
  "ECM" => member.("ecm@demo.test", "Pauline Atangana", [:teacher]),
  "EPS" => member.("eps@demo.test", "Roger Mbida", [:teacher])
}

hs = scope_of.(head, ws)

# The school year containing today: first Monday of September to 30 June.
first_year =
  (fn d -> if d.month >= 8, do: d.year, else: d.year - 1 end).(
    TeacherAssistant.Academics.Reference.today()
  )

sept_1 = Date.new!(first_year, 9, 1)
year_start = Date.add(sept_1, rem(8 - Date.day_of_week(sept_1), 7))

{:ok, year} =
  Organization.create_academic_year(hs, %{
    name: "#{first_year}-#{first_year + 1}",
    start_date: year_start,
    end_date: Date.new!(first_year + 1, 6, 30),
    active: true
  })

:ok = Organization.build_default_calendar(hs, year)
hs = scope_of.(head, ws)

classes =
  for {label, level} <- [
        {"6e A", "6ème"},
        {"5e A", "5ème"},
        {"4e B", "4ème"},
        {"3e A", "3ème"},
        {"2nde A", "2nde"},
        {"1re D", "1ère"},
        {"Tle D", "Terminale"}
      ] do
    {:ok, cg} = Enrollment.create_class_group(hs, year, %{label: label, level: level})
    cg
  end

first = ~w(Yannick Brice Diane Paul Hervé Joëlle Serge Ulrich Estelle Carine Fabrice Nadège)
last = ~w(Fouda Kouam Zambo Ekani Nkoulou Owona Mbarga Tsafack Belinga Ndzie Abega Manga)

roster =
  for {cg, r} <- Enum.with_index(classes), into: %{} do
    for i <- 0..11 do
      name = "#{Enum.at(last, rem(i + r * 5, 12))} #{Enum.at(first, rem(i + r, 12))}"
      # KLM1: about a third of the students get a birth date and place.
      birth =
        if rem(i, 3) == 0,
          do: %{birth_date: Date.new!(2014 - r, rem(i, 12) + 1, 10 + i), birth_place: Enum.at(~w(Yaoundé Douala Bafoussam Garoua), rem(i, 4))},
          else: %{}

      {:ok, _} =
        Enrollment.add_student(
          hs,
          cg,
          Map.merge(%{full_name: name, sex: Enum.random([:f, :m])}, birth)
        )
    end

    {cg.id, Enrollment.list_roster(hs, cg)}
  end

# KLM1: guardians for every other student of each class; the first two students
# of 6e A share the same father (siblings).
for {cg, _r} <- Enum.with_index(classes) do
  roster[cg.id]
  |> Enum.with_index()
  |> Enum.filter(fn {_, i} -> rem(i, 2) == 0 end)
  |> Enum.each(fn {%{student: s}, i} ->
    family = s.full_name |> String.split() |> hd()

    {:ok, _} =
      Enrollment.add_guardian(hs, s, %{
        full_name: "#{family} #{Enum.at(~w(Jean Marie Paul Rose), rem(i, 4))}",
        relationship: Enum.at([:pere, :mere, :tuteur, :mere], rem(i, 4)),
        phone: "6#{String.pad_leading(to_string(:erlang.phash2({cg.id, i}, 100_000_000)), 8, "0")}"
      })
  end)
end

[%{student: elder}, %{student: younger} | _] = roster[hd(classes).id]
[%{guardian: shared} | _] = Enrollment.list_guardian_links(hs, elder)
{:ok, _} = Enrollment.link_guardian(hs, younger, shared)

subjects = [
  "Mathématiques",
  "Français",
  "Anglais",
  "Physique",
  "SVT",
  "Histoire-Géographie",
  "ECM",
  "EPS"
]

censeur_classes = ["4e B", "3e A", "2nde A"]

courses =
  for cg <- classes, subj <- subjects, into: %{} do
    t =
      cond do
        subj == "Mathématiques" and cg.label in censeur_classes -> censeur
        subj == "Mathématiques" -> prof
        true -> teachers[subj]
      end

    {:ok, tc} = Curriculum.assign_teacher(hs, cg, t, %{subject: subj})
    {{cg.id, subj}, {tc, t}}
  end

periods =
  hs
  |> Attendance.list_periods()
  |> Enum.filter(&(&1.kind == :lesson))
  |> Enum.sort_by(& &1.position)

days = [:monday, :tuesday, :wednesday, :thursday, :friday]

# Timetable: class r at period p on day d gets subject (r + p + d) mod 8 — never the same teacher twice per cell.
placed =
  for {d, di} <- Enum.with_index(days),
      {cg, r} <- Enum.with_index(classes),
      {p, pi} <- Enum.with_index(periods),
      rem(r * 2 + pi + di * 3, 9) != 8,
      reduce: [] do
    acc ->
      subj = Enum.at(subjects, rem(r + pi + di, 8))
      {tc, t} = courses[{cg.id, subj}]

      case Timetabling.place_slot(hs, cg, %{day: d, period_id: p.id, teaching_context_id: tc.id}) do
        {:ok, _} ->
          [{d, di, cg, r, p, pi, tc, t} | acc]

        other ->
          IO.inspect({cg.label, d, p.label, subj, other}, label: "slot skipped")
          acc
      end
  end

today = TeacherAssistant.Academics.Reference.today()
now = TeacherAssistant.Academics.Reference.now()
monday = Date.add(today, 1 - Date.day_of_week(today))

# Roll calls: every slot from last Monday up to now, except a few deliberate misses.
repeat_absent = %{"Tle D" => 3, "4e B" => 0}
start = Date.add(monday, -7)

for date <- Date.range(start, today),
    Date.day_of_week(date) <= 5,
    {d, di, cg, r, p, pi, tc, t} <- placed,
    Date.day_of_week(date) == di + 1,
    NaiveDateTime.compare(NaiveDateTime.new!(date, p.end_time), now) != :gt do
  missed? =
    rem(r * 5 + pi * 3 + date.day, 11) == 0 or
      (t.id == prof.id and date == Date.add(today, -1) and pi == 0)

  unless missed? do
    roster = roster[cg.id]
    rep = repeat_absent[cg.label]

    marks =
      roster
      |> Enum.with_index()
      |> Enum.map(fn {%{enrollment: e}, i} ->
        status =
          cond do
            rep == i and Date.diff(today, date) <= 3 -> :absent
            rem(i * 7 + pi * 3 + date.day + r, 61) == 0 -> :absent
            rem(i * 5 + pi + date.day, 41) == 0 -> :late
            true -> :present
          end

        {e.id, status}
      end)

    {:ok, _} = Attendance.record_period(scope_of.(t, ws), cg, p, tc, date, marks)
  end
end

sgs = scope_of.(sg, ws)

# Justify a couple of past days.
[%{enrollment: e1} | _] = roster[Enum.at(classes, 0).id]
Attendance.justify_day(sgs, e1, Date.add(today, -1), :maladie)

# Marks: S1, two assessments per course, completion varying per course.
[s1 | _] = Organization.list_sequences(hs, year)

for {cg, r} <- Enum.with_index(classes), {subj, c} <- Enum.with_index(subjects) do
  {tc, t} = courses[{cg.id, subj}]
  ts = scope_of.(t, ws)
  mode = rem(r * 3 + c * 5, 7)

  # 0: nothing entered, 1..2: one assessment partly, 3..6: complete
  if mode != 0 do
    {:ok, a1} = Assessment.create_assessment(ts, tc, s1, %{label: "Interro 1"})
    {:ok, a2} = Assessment.create_assessment(ts, tc, s1, %{label: "Devoir 1"})
    students = roster[cg.id] |> Enum.map(& &1.student)

    entries = fn list ->
      Enum.with_index(list, fn st, i ->
        if rem(i + r + c, 13) == 0,
          do: %{student_id: st.id, status: :absent},
          else: %{student_id: st.id, score: Decimal.new(rem(i * 7 + r * 3 + c * 11, 15) + 5)}
      end)
    end

    :ok =
      Assessment.upsert_marks(
        ts,
        a1,
        entries.(if mode <= 2, do: Enum.take(students, 7), else: students)
      )

    if mode > 2, do: :ok = Assessment.upsert_marks(ts, a2, entries.(students))
  end
end

# Sanctions.
pick = fn label, i ->
  Enum.at(roster[Enum.find(classes, &(&1.label == label)).id], i).enrollment
end

{:ok, _} =
  Discipline.add_sanction(sgs, pick.("4e B", 6), %{
    type: :consigne,
    date: today,
    reason: "Bavardages répétés"
  })

{:ok, _} =
  Discipline.add_sanction(sgs, pick.("3e A", 7), %{
    type: :avertissement,
    date: today,
    reason: "Retards répétés"
  })

{:ok, s3} =
  Discipline.add_sanction(sgs, pick.("Tle D", 3), %{
    type: :avertissement,
    date: Date.add(today, -3),
    reason: "Absences répétées"
  })

{:ok, s4} =
  Discipline.add_sanction(sgs, pick.("2nde A", 4), %{
    type: :blame,
    date: Date.add(today, -6),
    reason: "Insolence"
  })

{:ok, _} = Discipline.mark_parents_notified(sgs, s3)
{:ok, _} = Discipline.mark_parents_notified(sgs, s4)
IO.puts("Demo school ready: #{ws.name}. Sign in as proviseur@demo.test / password1234.")
