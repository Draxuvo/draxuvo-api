# Lee un PDF de etiquetas sin dependencias: Prawn no comprime, así que cada página es un MediaBox y un flujo de
# contenido con las órdenes de dibujo (`x y w h re` son las barras del código). Spec 035.
module LabelPdfHelpers
  Page = Struct.new(:width, :height, :rects, keyword_init: true)

  def read_pdf(bytes)
    boxes = bytes.scan(%r{/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]}).map { |w, h| [ w.to_f, h.to_f ] }
    streams = bytes.scan(/stream\n(.*?)\nendstream/m).flatten
    boxes.each_with_index.map do |(width, height), index|
      rects = streams[index].to_s.scan(/^(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+) re$/).map { |r| r.map(&:to_f) }
      Page.new(width: width, height: height, rects: rects)
    end
  end

  # Barras agrupadas por etiqueta: cada grupo es el conjunto de rectángulos con el mismo y (misma etiqueta) y cercanos en x.
  def label_groups(page, label_width_pt)
    page.rects.group_by { |x, y, _w, _h| [ (x / label_width_pt).floor, y.round(1) ] }.values
  end

  # El texto dibujado: Prawn escribe cada cadena en hexadecimal dentro de arreglos `[<..> 80 <..>] TJ` en Windows-1252.
  def pdf_text(bytes)
    bytes.scan(/\[(.*?)\] TJ/m).flatten.map do |array|
      array.scan(/<([0-9a-fA-F]*)>/).flatten.map { |hex| [ hex ].pack("H*") }.join
    end.join("\n").force_encoding("Windows-1252").encode("UTF-8")
  end
end
