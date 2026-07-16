module MessageActions
  # 🥩 every message that mentions meat.
  class MeatReact < Base
    match word: "meat"

    def perform = react("🥩")
  end
end
