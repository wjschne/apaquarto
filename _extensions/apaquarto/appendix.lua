FloatRefTarget = function(ft)
   
  if ft.type == "Figure" and ft.identifier == "fig-appendfig" then
    quarto.log.output(ft)
      for i,j in pairs(ft) do
        --print(i); print(j)
        
        if i == "order" then
          --j.order = "A1"
          --quarto.log.output(j)
        end
        if i == "__quarto_custom_node" then
          --quarto.log.output(quarto._quarto.ast.custom_node_data[j.attributes.__quarto_custom_id])
        end
      end
  end
end--


