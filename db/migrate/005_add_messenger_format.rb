# frozen_string_literal: true

class AddMessengerFormat < ActiveRecord::Migration[4.2]
  def change
    add_column :messenger_settings, :messenger_format, :string
  end
end
