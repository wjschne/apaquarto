local word_count = 0

local function count_words_in_string(str)
  local _, count = string.gsub(str, "%S+", "")
  return count
end


local function count_words_in_inlines(inlines)
  for _, inline in ipairs(inlines) do
    if inline.t == "Str" then
      if inline.text:match("%P") then
        word_count = word_count + 1
      end
    end
    if inline.t == "Code" or inline.t == "CodeBlock" then
      
      word_count = word_count + count_words_in_string(inline.text)
    end
    
    if inline.t == "Cite" then
      word_count = word_count + 1
    end
    
    if inline.t == "Span" or inline.t == "Emph" or inline.t == "Strong" or inline.t == "Link" or inline.t == "Quoted" or inline.t == "Para" or inline.t == "Strikeout" then
      count_words_in_inlines(inline.content)
    end
  end
end

local function processblocks(b)

  for _, block in ipairs(b) do
      if block.t == "Para" or block.t == "Plain" or block.t == "Header" or block.t == "BlockQuote" then
        count_words_in_inlines(block.content)
      end
      if block.t == "Div" then
        processblocks(block.content)
      end
  end
end

function Note(el)
    processblocks(el.content)
end

function Math(el)
    word_count = word_count + count_words_in_string(el.text)
end

function CodeBlock(el)
    word_count = word_count + count_words_in_string(el.text)
end

function BulletList(el)
  for _, block in ipairs(el.content) do
    processblocks(block)
  end
end

function OrderedList(el)
  for _, block in ipairs(el.content) do
    processblocks(block)
  end
end

function DefinitionList(el)
  for _, block in ipairs(el.content) do
    processblocks(block)
  end
end

function Pandoc(doc)
  processblocks(doc.blocks)
  doc.meta.wordn = word_count
  return doc
end




