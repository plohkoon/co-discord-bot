class CreateWowTokenPrices < ActiveRecord::Migration[8.1]
  # WoW Token price history, per region.
  #
  # A single current price is a trivia lookup; the *series* is the interesting
  # thing, because "the token is up 40k this week" is what people actually react
  # to. Blizzard only ever serves the latest value, so the history only exists
  # if we keep it.
  def change
    create_table :wow_token_prices do |t|
      t.string :region, null: false
      # Copper, as Blizzard reports it. Stored raw rather than converted to gold
      # so nothing is lost to rounding; WowTokenPrice#gold does the division.
      t.bigint :price, null: false
      # Blizzard's own timestamp for the price, not our fetch time — the token
      # changes on their schedule, and polling more often than it moves would
      # otherwise create fake data points.
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    # Re-polling an unchanged price is a no-op rather than a duplicate row.
    add_index :wow_token_prices, %i[region recorded_at], unique: true
  end
end
