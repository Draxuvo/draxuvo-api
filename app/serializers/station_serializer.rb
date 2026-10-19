class StationSerializer
  def initialize(station)
    @station = station
  end

  def as_json(*)
    { id: @station.id, name: @station.name, is_default: @station.is_default, active: @station.active, position: @station.position }
  end
end
