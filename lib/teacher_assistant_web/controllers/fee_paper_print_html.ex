defmodule TeacherAssistantWeb.FeePaperPrintHTML do
  use TeacherAssistantWeb, :html

  alias TeacherAssistant.Academics.ReturnNoteReason
  alias TeacherAssistantWeb.Money

  embed_templates "fee_paper_print_html/*"

  def date(%Date{} = d), do: Calendar.strftime(d, "%d/%m/%Y")

  @doc "The receipt's A5 print styles, shared by notes and warnings."
  def paper_style(assigns) do
    ~H"""
    <style>
      @page { size: A5; margin: 10mm; }
      body { font-family: Georgia, "Times New Roman", serif; color: #111; margin: 0; padding: 16px; font-size: 10.5pt; line-height: 1.4; }
      .sheet { max-width: 560px; margin: 0 auto 24px; position: relative; }
      .sheet + .sheet { page-break-before: always; break-before: page; }
      .national { text-align: center; font-size: 8.5pt; }
      .national .fr { font-variant: small-caps; font-weight: bold; }
      .national .en { color: #444; }
      .school { text-align: center; font-weight: bold; font-size: 12pt; margin: 6px 0 2px; }
      h1 { text-align: center; font-size: 14pt; margin: 8px 0 2px; }
      .number { text-align: center; font-size: 9.5pt; color: #444; margin-bottom: 10px; }
      dl { display: grid; grid-template-columns: 34% 1fr; gap: 3px 10px; margin: 8px 0; }
      dt { font-variant: small-caps; color: #444; }
      table { width: 100%; border-collapse: collapse; margin: 8px 0; }
      th, td { border: 1px solid #999; padding: 3px 6px; } th { background: #f0f0f0; font-variant: small-caps; font-weight: normal; }
      td.n, th.n { text-align: right; white-space: nowrap; }
      .foot { display: flex; justify-content: space-between; align-items: flex-end; gap: 12px; margin-top: 10px; }
      .check { font-size: 8pt; color: #333; }
      .check .code { font-family: ui-monospace, monospace; font-size: 11pt; font-weight: bold; letter-spacing: .08em; }
      .cancelled { position: absolute; inset: 35% 0 auto; text-align: center; font-size: 30pt; font-weight: bold; color: rgba(160, 30, 20, .35); transform: rotate(-18deg); pointer-events: none; }
      .actions { max-width: 560px; margin: 16px auto 0; font-family: system-ui, sans-serif; }
      .actions button { font: inherit; font-size: 10pt; padding: 8px 12px; border-radius: 8px; border: 1px solid #11663a; background: #11663a; color: #fff; cursor: pointer; }
      @media print { .actions { display: none; } body { padding: 0; } }
    </style>
    """
  end

  attr :school, :map, required: true

  def heading(assigns) do
    ~H"""
    <div class="national">
      <div class="fr">République du Cameroun — Paix – Travail – Patrie</div>
      <div class="en">Republic of Cameroon — Peace – Work – Fatherland</div>
    </div>
    <div class="school">{@school.name}</div>
    """
  end

  attr :paper, :map, required: true

  def check_foot(assigns) do
    ~H"""
    <div class="foot">
      <div>
        <div :if={@paper.issued_by_name}>
          {gettext("L'intendance : %{name}", name: @paper.issued_by_name)}
        </div>
        <div class="check">
          {gettext(
            "Vérifiez ce document en scannant le code QR, ou sur %{url} avec le numéro et le code :",
            url: @paper.lookup_url
          )}
          <div class="code">{@paper.code}</div>
        </div>
      </div>
      <div>{Phoenix.HTML.raw(@paper.qr)}</div>
    </div>
    """
  end
end
