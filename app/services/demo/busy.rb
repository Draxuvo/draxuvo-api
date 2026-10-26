# No hay ranura de aprovisionamiento libre o se llegó al tope de demos activas (spec 039, R5).
module Demo
  class Busy < StandardError; end
end
