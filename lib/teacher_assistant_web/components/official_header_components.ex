defmodule TeacherAssistantWeb.OfficialHeaderComponents do
  @moduledoc """
  Spec bulletin v2 §5.1: the official header of the school's papers — French on the
  left, English on the right, the logo and school code between, then the school's
  own lines and the flag stripe. Shared by the bulletin and the class roster; each
  page styles `.header`, `.school` and `.flag` in its own `<style>`.
  """
  use Phoenix.Component
  use TeacherAssistantWeb, :verified_routes

  alias TeacherAssistant.Academics.BulletinTemplate

  @backend TeacherAssistantWeb.Gettext

  attr :header, :map, required: true, doc: "a resolved template's `header`"
  attr :logo?, :boolean, required: true

  def official_header(assigns) do
    ~H"""
    <div class="header">
      <div class="col">
        <div :for={line <- official_lines(@header, :fr)}>{line}</div>
      </div>
      <div class="mid">
        <img :if={@logo?} src={~p"/school/logo"} alt="" />
        <div :if={present?(Map.get(@header, :school_code))} class="code">
          CODE : {@header.school_code}
        </div>
      </div>
      <div class="col">
        <div :for={line <- official_lines(@header, :en)}>{line}</div>
      </div>
    </div>
    <div class="school">
      <div>
        <div
          :for={{line, i} <- Enum.with_index(school_lines(@header, :fr))}
          class={if i == 0, do: "name"}
        >
          {line}
        </div>
      </div>
      <div></div>
      <div>
        <div
          :for={{line, i} <- Enum.with_index(school_lines(@header, :en))}
          class={if i == 0, do: "name"}
        >
          {line}
        </div>
      </div>
    </div>
    <div class="flag"></div>
    """
  end

  defp official_lines(header, lang), do: BulletinTemplate.official_lines(header, lang)

  # The school's own lines under each column; the English one names the school in English.
  defp school_lines(header, :fr),
    do: in_locale(:fr, fn -> BulletinTemplate.school_lines(header) end)

  defp school_lines(header, :en) do
    name = if present?(Map.get(header, :name_en)), do: header.name_en, else: header.name
    in_locale(:en, fn -> BulletinTemplate.school_lines(%{header | name: name}) end)
  end

  defp in_locale(lang, fun), do: Gettext.with_locale(@backend, Atom.to_string(lang), fun)

  defp present?(text), do: is_binary(text) and String.trim(text) != ""
end
