# Las fuentes incluidas de Prawn (Helvetica, Times…) solo traen Windows-1252: acentos y ñ sí. El aviso que imprime Prawn
# cada vez que se carga una de ellas es ruido en los registros y en las pruebas.
require "prawn"
Prawn::Fonts::AFM.hide_m17n_warning = true
