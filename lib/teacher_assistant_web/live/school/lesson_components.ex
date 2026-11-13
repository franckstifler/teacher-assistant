defmodule TeacherAssistantWeb.School.LessonComponents do
  @moduledoc """
  A teacher's lessons on screen (UX refonte 2026-11-03), shared by Ma journée and
  Mon emploi du temps: the words of a `LessonGroups` group — « Anglais · Niveau 2 »,
  « 5 classes · 39 élèves », « mêmes classes · 2e heure » — and its roll-call tag.
  """
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.{CombinedCourse, LessonGroups}
  alias TeacherAssistant.Accounts.User

  @doc "The combined courses' labels by id, from `Curriculum.list_units_for_scope/1`."
  def course_labels(units),
    do: for({:course, %CombinedCourse{id: id, label: label}} <- units, into: %{}, do: {id, label})

  @doc "« Anglais · Niveau 2 » (the combined course's label) or « Maths · 6e A »."
  def lesson_title(%{unit: {:course, id}} = group, labels),
    do: Map.get(labels, id) || solo_title(group)

  def lesson_title(group, _labels), do: solo_title(group)

  defp solo_title(%{members: [first | _]}) do
    case subject(first) do
      nil -> class_label(first)
      subject -> "#{subject} · #{class_label(first)}"
    end
  end

  @doc "The member classes, « COME 2 · ELEQ 2 · ESF 2 »."
  def classes_line(%{members: members}), do: Enum.map_join(members, " · ", &class_label/1)

  @doc "The lesson's students, from `%{class id => count}`."
  def students(group, sizes),
    do: group |> LessonGroups.class_ids() |> Enum.map(&Map.get(sizes, &1, 0)) |> Enum.sum()

  @doc """
  The line under a lesson: « mêmes classes · 2e heure » after the same course,
  else « 5 classes · 39 élèves » (« 28 élèves » for one class).
  """
  def lesson_sub(%{hour: hour} = group, _sizes) when hour > 1 do
    if LessonGroups.combined?(group),
      do: gettext("mêmes classes · %{n}e heure", n: hour),
      else: gettext("%{n}e heure", n: hour)
  end

  def lesson_sub(group, sizes) do
    students = ngettext("%{count} élève", "%{count} élèves", students(group, sizes))

    if LessonGroups.combined?(group),
      do:
        ngettext("%{count} classe", "%{count} classes", length(group.members)) <>
          " · " <> students,
      else: students
  end

  defp subject(%{subject: subject}), do: subject
  defp subject(_member), do: nil

  defp class_label(%{class_group: %{label: label}}), do: label
  defp class_label(%{class_label: label}), do: label

  @doc "Who took the group's slot for their moved lesson (`:covered`), else nil."
  def covered_by_name(%{members: [%{covered_by: %{teacher: teacher}} | _]}),
    do: User.display_name(teacher)

  def covered_by_name(_lesson), do: nil

  @doc "The hour the group's lesson was moved to (« 09:10 »), else nil."
  def moved_to_time(%{members: [%{moved_to: %{start_time: t}} | _]}), do: hm(t)
  def moved_to_time(_lesson), do: nil

  @doc "The roll-call state of a lesson as a small tag (« Appel fait », « En cours »…)."
  attr :status, :atom, required: true
  # Spec 2026-11-12: a lesson held outside its slot, a slot taken by a colleague, a
  # slot vacated for another period.
  attr :moved?, :boolean, default: false
  attr :covered_by, :string, default: nil
  attr :moved_to, :string, default: nil

  def status_tag(%{status: :done, moved?: true} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 whitespace-nowrap rounded-full bg-success/15 px-2 py-[3px] text-[0.7rem] font-semibold text-success">
      <.icon name="hero-arrow-uturn-right-mini" class="size-3.5" /> {gettext("Déplacé")}
    </span>
    """
  end

  def status_tag(%{status: :covered} = assigns) do
    assigns = assign(assigns, :name, assigns.covered_by || "—")

    ~H"""
    <.tag tone={:muted}>{gettext("Pris par %{name}", name: @name)}</.tag>
    """
  end

  def status_tag(%{status: :not_held, moved_to: time} = assigns) when is_binary(time) do
    ~H"""
    <.tag tone={:muted}>{gettext("Non assuré · déplacé à %{time}", time: @moved_to)}</.tag>
    """
  end

  def status_tag(%{status: :done} = assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1 whitespace-nowrap rounded-full bg-success/15 px-2 py-[3px] text-[0.7rem] font-semibold text-success">
      <.icon name="hero-check-mini" class="size-3.5" /> {gettext("Appel fait")}
    </span>
    """
  end

  def status_tag(%{status: :in_progress} = assigns),
    do: ~H|<.tag tone={:now}>{gettext("En cours")}</.tag>|

  def status_tag(%{status: :missed} = assigns),
    do: ~H|<.tag tone={:error}>{gettext("Non fait")}</.tag>|

  def status_tag(%{status: :upcoming} = assigns),
    do: ~H|<.tag tone={:outline}>{gettext("À venir")}</.tag>|

  def status_tag(%{status: :on_paper} = assigns),
    do: ~H|<.tag tone={:muted}>{gettext("Sur feuille")}</.tag>|

  def status_tag(%{status: :not_held} = assigns),
    do: ~H|<.tag tone={:muted}>{gettext("Non assuré")}</.tag>|

  attr :tone, :atom, required: true
  slot :inner_block, required: true

  defp tag(assigns) do
    ~H"""
    <span class={[
      "whitespace-nowrap rounded-full px-2 py-[3px] text-[0.7rem] font-semibold",
      tone_class(@tone)
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp tone_class(:now), do: "bg-primary text-primary-content"
  defp tone_class(:error), do: "bg-error/15 text-error"
  defp tone_class(:muted), do: "bg-base-200 text-base-content/70"
  defp tone_class(:outline), do: "border border-base-300 text-base-content/70"

  def hm(time), do: Calendar.strftime(time, "%H:%M")
end
