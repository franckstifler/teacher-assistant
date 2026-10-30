// Spec 2026-10-29: the exam picture — date band, the student's photo as stored, then the
// name and the codes in bold blue on white. Sizes and colours live here, so the
// directorate's official format, once known, is a change in one place.
import {drawCover} from "../hooks/photo_studio"

const W = 600, TOP = 64, PHOTO_H = 800, BOTTOM = 160, H = TOP + PHOTO_H + BOTTOM
const BLUE = "#1414C8", FONT = "Arial, Helvetica, sans-serif", QUALITY = 0.9
const MARGIN = 24, DATE_PX = 26, NAME_PX = 30, CODES_PX = 46, MIN_PX = 12

// One fetch per photo (previews and the export share it). The small JPEG is kept, not
// its decoded bitmap: 100 decoded photos would hold ~190 MB, too much for a phone.
const photos = new Map()

function loadPhoto(url) {
  if (!photos.has(url)) {
    const blob = fetch(url, {credentials: "same-origin"}).then((r) => {
      if (!r.ok) throw new Error(`photo ${r.status}`)
      return r.blob()
    })
    blob.catch(() => photos.delete(url)) // a failure is retried next time
    photos.set(url, blob)
  }
  return photos.get(url)
}

const font = (px) => `bold ${px}px ${FONT}`

// The largest size ≤ `px` at which `text` fits the band's width.
function fittingSize(ctx, text, px) {
  ctx.font = font(px)
  while (px > MIN_PX && ctx.measureText(text).width > W - 2 * MARGIN) ctx.font = font(--px)
  return px
}

// The first name variant that fits at full size; else the shortest, in smaller letters.
function fitName(ctx, names) {
  ctx.font = font(NAME_PX)
  const fits = names.find((n) => ctx.measureText(n).width <= W - 2 * MARGIN)
  if (fits) return {text: fits, px: NAME_PX}
  const text = names[names.length - 1]
  return {text, px: fittingSize(ctx, text, NAME_PX)}
}

function centred(ctx, text, px, y) {
  ctx.font = font(px)
  ctx.fillText(text, W / 2, y)
}

// `scale` < 1 draws a smaller copy (previews), so a class of previews stays light.
export async function drawExamCard(canvas, {photo_url, date, names, codes}, scale = 1) {
  const bitmap = await createImageBitmap(await loadPhoto(photo_url))
  canvas.width = W * scale
  canvas.height = H * scale
  const ctx = canvas.getContext("2d")
  ctx.scale(scale, scale)
  ctx.fillStyle = "#fff"
  ctx.fillRect(0, 0, W, H)

  ctx.save()
  ctx.translate(0, TOP)
  drawCover(ctx, bitmap, bitmap.width, bitmap.height)
  ctx.restore()
  bitmap.close()

  ctx.fillStyle = BLUE
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  if (date) centred(ctx, date, DATE_PX, TOP / 2)
  const name = fitName(ctx, names)
  centred(ctx, name.text, name.px, TOP + PHOTO_H + 48)
  if (codes) centred(ctx, codes, fittingSize(ctx, codes, CODES_PX), TOP + PHOTO_H + 112)
}

// The preview of a photo that could not be read: a grey card saying so.
export function drawUnreadable(canvas, text, scale = 1) {
  canvas.width = W * scale
  canvas.height = H * scale
  const ctx = canvas.getContext("2d")
  ctx.scale(scale, scale)
  ctx.fillStyle = "#e5e7eb"
  ctx.fillRect(0, 0, W, H)
  ctx.fillStyle = "#b91c1c"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  centred(ctx, text, NAME_PX, H / 2)
}

export const examCardJpeg = (canvas) =>
  new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", QUALITY))
