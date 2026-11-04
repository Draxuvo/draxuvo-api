require "pagy/extras/limit"
# Spec 054 (H-46): una página más allá de la última devuelve la última, no un 500.
require "pagy/extras/overflow"

Pagy::DEFAULT[:limit]       = 20
Pagy::DEFAULT[:limit_param] = :page_size
Pagy::DEFAULT[:limit_max]   = 100
Pagy::DEFAULT[:overflow]    = :last_page
