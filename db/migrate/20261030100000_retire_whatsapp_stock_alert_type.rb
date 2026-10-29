# Spec 048: el aviso de stock bajo deja de ser un tipo de mensaje de WhatsApp (sale por correo y por el panel y la app).
# La fila de `whatsapp_message_types` se conserva (historial) pero queda apagada y sin avisos pendientes. Solo datos:
# no cambia el esquema. `down` no hace nada: la fila nunca se borró y quien la reactive lo hace a mano.
class RetireWhatsappStockAlertType < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      UPDATE whatsapp_message_types
      SET enabled = FALSE, problem_notified_at = NULL, updated_at = NOW()
      WHERE kind = 'stock_alert'
    SQL
  end

  def down
    # Sin acción: no hay nada que restaurar.
  end
end
