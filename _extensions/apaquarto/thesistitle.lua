-- The shape of a dissertation title: capitals, in an inverted pyramid.
--
-- The Graduate School asks for the title of a dissertation or thesis in
-- capitals, and for an inverted pyramid when it runs to more than one line:
-- the first line longest, each line after it shorter.
--
-- The lines are worked out here rather than left to each format, because a
-- .docx cannot measure anything while it is being written. One set of lines
-- is decided in lua and every format is given the same ones, so the title
-- page has the same shape in all four.

local M = {}

-- Advance widths of Times Bold, in thousandths of an em, which is what a
-- title is set in. These are the widths of the Times-Bold afm, the metrics
-- that Times New Roman Bold and TeX Gyre Termes Bold both follow. Only what
-- a title in capitals can hold is listed; anything else is taken to be 600,
-- which is about the average of them.
local bold_widths = {
  A = 722, B = 667, C = 722, D = 722, E = 667, F = 611, G = 778, H = 778,
  I = 389, J = 500, K = 778, L = 667, M = 944, N = 722, O = 778, P = 611,
  Q = 778, R = 722, S = 556, T = 667, U = 722, V = 722, W = 1000, X = 722,
  Y = 722, Z = 667,
  ["0"] = 500, ["1"] = 500, ["2"] = 500, ["3"] = 500, ["4"] = 500,
  ["5"] = 500, ["6"] = 500, ["7"] = 500, ["8"] = 500, ["9"] = 500,
  [" "] = 250, ["."] = 250, [","] = 250, [":"] = 333, [";"] = 333,
  ["-"] = 333, ["("] = 333, [")"] = 333, ["["] = 333, ["]"] = 333,
  ["?"] = 500, ["!"] = 333, ["/"] = 278, ["&"] = 833,
  ["\u{2019}"] = 333, ["\u{2018}"] = 333,
  ["\u{201C}"] = 500, ["\u{201D}"] = 500,
  ["\u{2014}"] = 1000, ["\u{2013}"] = 500,
}

local kDefaultWidth = 600
local kSpace = 250

local function text_width(text)
  local total = 0
  for _, code in utf8.codes(text) do
    total = total + (bold_widths[utf8.char(code)] or kDefaultWidth)
  end
  return total
end

-- How wide a stretch of inlines is, in thousandths of an em.
function M.width(inlines)
  local total = 0
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      total = total + text_width(inline.text)
    elseif inline.t == "Space" or inline.t == "SoftBreak" then
      total = total + kSpace
    elseif inline.content then
      total = total + M.width(inline.content)
    else
      total = total + text_width(pandoc.utils.stringify(inline))
    end
  end
  return total
end

-- The title in capitals, which is how the Graduate School asks for it.
M.upper = require("utilsapa").upper

-- The words of the title, each with the width it will take.
local function words_of(inlines)
  local words = pandoc.List({})
  local current = pandoc.Inlines({})
  local function flush()
    if #current > 0 then
      words:insert({ inlines = current, width = M.width(current) })
      current = pandoc.Inlines({})
    end
  end
  for _, inline in ipairs(inlines) do
    if inline.t == "Space" or inline.t == "SoftBreak" then
      flush()
    else
      current:insert(inline)
    end
  end
  flush()
  return words
end

local function join_words(words, first, last)
  local out = pandoc.Inlines({})
  for i = first, last do
    if i > first then out:insert(pandoc.Space()) end
    out:extend(words[i].inlines)
  end
  return out
end

local function span_width(words, first, last)
  local total = 0
  for i = first, last do total = total + words[i].width end
  return total + (last - first) * kSpace
end

-- The best arrangement of the words into exactly this many lines.
--
-- The shape wanted is a straight taper, from a full measure down to nothing:
-- for a title of k lines, line m is aimed at (k + 1 - m) / k of the measure.
-- Every way of cutting the words into k lines is costed by how far its lines
-- fall from that aim, and the closest is kept.
--
-- A word is never broken, so an arrangement needing a line wider than the
-- measure is passed over, and so is one whose lines do not fall away --- a
-- line longer than the one above it is not an inverted pyramid.
local function best_arrangement(words, measure, lines)
  local n = #words
  if lines > n then return nil end

  local target = {}
  for m = 1, lines do target[m] = measure * (lines + 1 - m) / lines end

  -- cost[m][j] is the least cost of setting the first j words in m lines
  local cost, from = {}, {}
  for m = 0, lines do cost[m], from[m] = {}, {} end
  cost[0][0] = 0

  for m = 1, lines do
    for j = m, n do
      for i = m - 1, j - 1 do
        if cost[m - 1][i] ~= nil then
          local width = span_width(words, i + 1, j)
          if width <= measure then
            local gap = width - target[m]
            local total = cost[m - 1][i] + gap * gap
            if cost[m][j] == nil or total < cost[m][j] then
              cost[m][j] = total
              from[m][j] = i
            end
          end
        end
      end
    end
  end
  if cost[lines][n] == nil then return nil end

  local breaks, j = {}, n
  for m = lines, 1, -1 do
    breaks[m] = { from[m][j] + 1, j }
    j = from[m][j]
  end
  for m = 2, lines do
    local above = span_width(words, breaks[m - 1][1], breaks[m - 1][2])
    local here = span_width(words, breaks[m][1], breaks[m][2])
    if here > above then return nil end
  end
  return { cost = cost[lines][n], breaks = breaks }
end

local kMaxLines = 8

-- The title as lines, in an inverted pyramid. measure is the width of the
-- text block in thousandths of an em of the title's own size, which is what
-- the widths above are in.
--
-- Trying every number of lines and keeping the arrangement that sits nearest
-- its taper settles how many lines the title wants, so that nobody has to
-- say.
function M.pyramid(inlines, measure)
  local words = words_of(inlines)
  if #words == 0 then return pandoc.List({ pandoc.Inlines(inlines) }) end
  if span_width(words, 1, #words) <= measure then
    return pandoc.List({ join_words(words, 1, #words) })
  end

  local best = nil
  for lines = 2, math.min(kMaxLines, #words) do
    local tried = best_arrangement(words, measure, lines)
    if tried and (best == nil or tried.cost < best.cost) then best = tried end
  end

  -- Nothing fits, which means a single word wider than the measure and no
  -- arrangement that can mend it. The title is left as one line.
  if best == nil then return pandoc.List({ join_words(words, 1, #words) }) end

  local out = pandoc.List({})
  for _, span in ipairs(best.breaks) do
    out:insert(join_words(words, span[1], span[2]))
  end
  return out
end

-- The lines a writer broke themselves, or nil when they broke none. A line
-- break is written in yaml with a backslash at the end of the line:
--
--   title: |
--     This is the First Line of My Title \
--     And This is the Second Line
function M.written_lines(inlines)
  local out = pandoc.List({})
  local current = pandoc.Inlines({})
  local found = false
  for _, inline in ipairs(inlines) do
    if inline.t == "LineBreak" then
      found = true
      out:insert(current)
      current = pandoc.Inlines({})
    else
      current:insert(inline)
    end
  end
  if not found then return nil end
  out:insert(current)
  -- A break at the end leaves an empty line, which is not a line of a title.
  while #out > 0 and #out[#out] == 0 do out:remove(#out) end
  return out
end

return M
