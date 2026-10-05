-- The colour a link takes in .docx.
--
-- Every link pandoc writes carries the reference document's Hyperlink
-- character style, and that is the only thing saying what colour it is. A
-- document that asks for linkcolor, urlcolor, citecolor or filecolor is
-- asking for four colours from one style, so four styles are written into the
-- reference document instead -- each based on Hyperlink, so a writer's own
-- changes to it still come through -- and each link is given the one that
-- suits it.
--
-- A style is only reached by a run inside the link: pandoc ignores
-- custom-style on a Link but honours it on a Span within one, where the
-- rStyle it writes takes the place of Hyperlink.
--
-- toccolor is not here. The lists of contents, figures and tables are built
-- by docxcontents.lua out of word markup of its own, whose runs carry no
-- style at all, so the colour is written straight into them there.
--
-- The styles themselves are written into the reference document by
-- docxreferencedoc.lua, along with everything else a render changes there,
-- so that the file is written once; referencedoc.lua has the code for them.
-- This filter gives each link the style that suits it.

if FORMAT ~= "docx" then
  return
end

local utilsapa = require("utilsapa")
local referencedoc = require("referencedoc")

-- Which field a link's target asks for, read the way latex reads it
local field_for = utilsapa.link_field

local styles = referencedoc.link_styles

-- field -> six hex digits, for the fields this document actually named
local wanted = {}

function Meta(meta)
  wanted = referencedoc.link_colours(meta)
end

function Link(link)
  local field = field_for(link.target)
  if not wanted[field] then return nil end
  local span = pandoc.Span(link.content,
    pandoc.Attr("", {}, { ["custom-style"] = styles[field] }))
  link.content = pandoc.Inlines({ span })
  return link
end

return {
  { Meta = Meta },
  { Link = Link },
}
