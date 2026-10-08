-- Widens a .docx table's column that is too narrow for its longest word.
--
-- A table with a cell too long for one line of the source is given its
-- columns' widths in proportion to the dashes under its head, and pandoc
-- writes them to Word as a fixed layout. A column of short numbers under a
-- short heading gets few dashes, and in Word, which takes its cell margins
-- out of that width and breaks a word that does not fit, a heading such as
-- "Num" was set as "Nu" over "m". latex and typst let such a word run on
-- into the space between the columns rather than break it, so this is a
-- .docx matter only (tests/docx-column-widths.qmd).
--
-- So a column given less than its longest word needs is widened to that,
-- and the columns that have room to spare, the ones whose text wraps
-- anyway, give it up in proportion to their widths. A table without such
-- widths is left to Word, which sizes its columns to their contents and
-- never breaks a word to do it.
--
-- Words are measured in Times New Roman at 12pt, apaquarto's .docx font,
-- from its widths per thousandth of an em (Adobe's Times-Roman metrics,
-- which Times New Roman shares), with a little to spare for bold and for
-- other fonts. The text is taken to be 6in wide, the narrowest apaquarto
-- sets: letter paper's is 6.5in, A4's 6.27in and a thesis's 6in.

if FORMAT ~= "docx" then
  return
end

local times = {
  [" "] = 250, ["!"] = 333, ['"'] = 408, ["#"] = 500, ["$"] = 500,
  ["%"] = 833, ["&"] = 778, ["'"] = 333, ["("] = 333, [")"] = 333,
  ["*"] = 500, ["+"] = 564, [","] = 250, ["-"] = 333, ["."] = 250,
  ["/"] = 278, [":"] = 278, [";"] = 278, ["<"] = 564, ["="] = 564,
  [">"] = 564, ["?"] = 444, ["@"] = 921, ["["] = 333, ["\\"] = 278,
  ["]"] = 333, ["^"] = 469, ["_"] = 500, ["`"] = 333, ["{"] = 480,
  ["|"] = 200, ["}"] = 480, ["~"] = 541,
  A = 722, B = 667, C = 667, D = 722, E = 611, F = 556, G = 722, H = 722,
  I = 333, J = 389, K = 722, L = 611, M = 889, N = 722, O = 722, P = 556,
  Q = 722, R = 667, S = 556, T = 611, U = 722, V = 722, W = 944, X = 722,
  Y = 722, Z = 611,
  a = 444, b = 500, c = 444, d = 500, e = 444, f = 333, g = 500, h = 500,
  i = 278, j = 278, k = 500, l = 278, m = 778, n = 500, o = 500, p = 500,
  q = 500, r = 333, s = 389, t = 278, u = 500, v = 500, w = 722, x = 500,
  y = 500, z = 444,
}
-- Digits are all 500, and so is anything not above: a letter with an
-- accent is as wide as the letter, near enough.
local default_width = 500

local font_size = 12      -- points
local spare = 1.08        -- for bold, and for a font a little wider
local cell_margins = 5.8  -- points: the Table style's 58 twips each side
local text_width = 432    -- points: 6in

-- How wide a word is set, in points. A word that is not whole UTF-8 is
-- counted a byte at a time at the usual width.
local function word_width(word)
  local thousandths = 0
  if utf8.len(word) then
    for _, code in utf8.codes(word) do
      thousandths = thousandths + (times[utf8.char(code)] or default_width)
    end
  else
    thousandths = #word * default_width
  end
  return thousandths / 1000 * font_size * spare
end

-- The width each column needs: its longest word and the cell's margins.
-- A cell spanning columns is left out, since its words may lie in any of
-- them, and so is a picture's alt text, which is not set on the page: a
-- figure's panels are laid out in a table too.
local no_pictures = { Image = function() return {} end }

local function needed_widths(tbl)
  local needs = {}
  for i = 1, #tbl.colspecs do needs[i] = cell_margins end
  local function measure(rows)
    for _, row in ipairs(rows) do
      local column = 1
      for _, cell in ipairs(row.cells) do
        if cell.col_span == 1 and needs[column] then
          local text = pandoc.utils.stringify(
            pandoc.Blocks(cell.contents):walk(no_pictures))
          -- Words split at ASCII spaces alone: %s takes byte A0 for one on
          -- some systems, which cut a non-breaking space in two, and a
          -- non-breaking space joins two words into one that cannot break.
          for word in text:gmatch("[^ \t\r\n]+") do
            needs[column] = math.max(needs[column],
              word_width(word) + cell_margins)
          end
        end
        column = column + cell.col_span
      end
    end
  end
  measure(tbl.head.rows)
  for _, body in ipairs(tbl.bodies) do
    measure(body.head)
    measure(body.body)
  end
  measure(tbl.foot.rows)
  return needs
end

function Table(tbl)
  local widths, total = {}, 0
  for i, spec in ipairs(tbl.colspecs) do
    local width = spec[2]
    if type(width) ~= "number" or width <= 0 then return nil end
    widths[i] = width
    total = total + width
  end
  if #widths == 0 then return nil end

  -- Word stretches the table to the text's width, so a column's share of
  -- the widths is its share of the text.
  local needs = needed_widths(tbl)
  local narrow, wanted, spare_width = {}, 0, 0
  for i, width in ipairs(widths) do
    local has = width / total * text_width
    if has < needs[i] then
      narrow[i] = true
      wanted = wanted + needs[i]
    else
      spare_width = spare_width + width
    end
  end
  if wanted == 0 then return nil end

  -- The others share what is left in proportion to their widths. A column
  -- that would then be too narrow itself is held at its need in turn.
  local left = text_width - wanted
  local changed = true
  while changed do
    changed = false
    for i, width in ipairs(widths) do
      if not narrow[i] and width / spare_width * left < needs[i] then
        narrow[i] = true
        left = left - needs[i]
        spare_width = spare_width - width
        changed = true
      end
    end
  end

  -- Too many words too long to fit side by side: Word is left to size the
  -- columns itself, as it does a table with no widths.
  local colspecs = pandoc.List()
  if left < 0 then
    for _, spec in ipairs(tbl.colspecs) do
      colspecs:insert({ spec[1], nil })
    end
  else
    for i, spec in ipairs(tbl.colspecs) do
      local points = narrow[i] and needs[i] or widths[i] / spare_width * left
      colspecs:insert({ spec[1], points / text_width * total })
    end
  end
  tbl.colspecs = colspecs
  return tbl
end
